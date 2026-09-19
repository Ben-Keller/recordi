import Foundation
import CryptoKit
import Darwin

public struct RecordiError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}
public let fm = FileManager.default
public func atomic<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(value).write(to: url, options: .atomic)
}
public func readJSON<T: Decodable>(_ type: T.Type, _ url: URL) throws -> T {
    try JSONDecoder().decode(type, from: Data(contentsOf: url))
}
public struct Paths {
    public let home: URL
    public init(home: URL = fm.homeDirectoryForCurrentUser) { self.home = home }
    public var support: URL { home.appendingPathComponent("Library/Application Support/Recordi") }
    public var recordi: URL { home.appendingPathComponent("Documents/Recordi") }
    public var audio: URL { recordi.appendingPathComponent("recordings") }
    public var transcripts: URL { recordi.appendingPathComponent("transcripts") }
    public var logs: URL { recordi.appendingPathComponent("logs") }
    public var queue: URL { support.appendingPathComponent("queue") }
    public var state: URL { support.appendingPathComponent("state") }
    public var completions: URL { support.appendingPathComponent("completions") }
    public var commands: URL { support.appendingPathComponent("commands") }
    public var model: URL { support.appendingPathComponent("models/ggml-large-v3-turbo.bin") }
    public var app: URL { home.appendingPathComponent("Applications/Recordi.app") }
    public var executable: URL { app.appendingPathComponent("Contents/MacOS/Recordi") }
    public func create() throws {
        for dir in [audio, transcripts, logs, queue, state, completions, commands, model.deletingLastPathComponent()] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
public final class FileLock {
    private var fd: Int32 = -1
    public init(_ url: URL, wait: Bool = false) throws {
        fd = Darwin.open(url.path, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RecordiError("Cannot open lock: \(url.path)") }
        guard flock(fd, LOCK_EX | (wait ? 0 : LOCK_NB)) == 0 else {
            Darwin.close(fd); fd = -1; throw RecordiError("Another Recordi process is busy.")
        }
    }
    deinit { if fd >= 0 { flock(fd, LOCK_UN); Darwin.close(fd) } }
}
public struct Source: Codable, Equatable {
    public let path: String
    public let size: Int64
    public let modified: Double
    public let id: String
    public init(_ url: URL, paths: Paths) throws {
        let resolved = url.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.deletingLastPathComponent() == paths.audio.standardizedFileURL.resolvingSymlinksInPath(),
              ["flac", "wav", "mp3"].contains(resolved.pathExtension.lowercased()) else {
            throw RecordiError("Recording must be an MP3, FLAC or WAV directly inside \(paths.audio.path).")
        }
        let attrs = try fm.attributesOfItem(atPath: resolved.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular,
              let n = attrs[.size] as? NSNumber, n.int64Value > 0,
              let m = attrs[.modificationDate] as? Date else { throw RecordiError("Recording is empty or not a regular file.") }
        path = resolved.path; size = n.int64Value; modified = m.timeIntervalSince1970
        // Identity intentionally excludes metadata: an existing source path is never a new output destination.
        id = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    public var basename: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }
}
public struct Job: Codable {
    public var source: Source
    public var status: String = "pending"
    public var attempts: Int = 0
    public var error: String?
    public var created: Date = Date()
    public var completed: Date?
}
public struct Completion: Codable {
    public let source: Source
    public let completed: Date
    public let outputs: [String]
}
public final class JobStore {
    public let paths: Paths
    public init(_ paths: Paths) { self.paths = paths }
    public func jobs() throws -> [Job] {
        try fm.contentsOfDirectory(at: paths.queue, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { try readJSON(Job.self, $0) }
            .sorted { $0.created < $1.created }
    }
    public func save(_ job: Job) throws { try atomic(job, to: paths.queue.appendingPathComponent(job.source.id + ".json")) }
    public func marker(_ source: Source) -> URL { paths.completions.appendingPathComponent(source.basename + ".recordi-complete.json") }
    public func successful(_ source: Source) -> Bool {
        guard let c = try? readJSON(Completion.self, marker(source)), c.source == source,
              c.outputs == ["txt"] else { return false }
        return c.outputs.allSatisfy { fm.fileExists(atPath: paths.transcripts.appendingPathComponent(source.basename + "." + $0).path) }
    }
    @discardableResult public func enqueue(_ url: URL) throws -> Bool {
        let lock = try FileLock(paths.state.appendingPathComponent("queue.lock"), wait: true)
        defer { withExtendedLifetime(lock) {} }
        let source = try Source(url, paths: paths)
        if successful(source) { return false }
        if var existing = try jobs().first(where: { $0.source.id == source.id }) {
            if existing.status == "complete", existing.source == source {
                existing.status = "pending"; existing.completed = nil; try save(existing); return true
            }
            return false
        }
        // A WAV and a FLAC with the same basename must not overwrite each other's products.
        if try jobs().contains(where: { $0.source.basename == source.basename }) {
            throw RecordiError("Another recording already owns transcript basename: \(source.basename)")
        }
        if fm.fileExists(atPath: marker(source).path) {
            guard let completion = try? readJSON(Completion.self, marker(source)), completion.source == source else {
                throw RecordiError("Source changed after completion: \(source.basename). Existing transcript retained.")
            }
        } else if ["txt"].contains(where: { fm.fileExists(atPath: paths.transcripts.appendingPathComponent(source.basename + "." + $0).path) }) {
            throw RecordiError("Existing transcript has no Recordi completion record: \(source.basename). It was left untouched.")
        }
        try save(Job(source: source)); return true
    }
    public func retryFailed() throws {
        let lock = try FileLock(paths.state.appendingPathComponent("queue.lock"), wait: true)
        defer { withExtendedLifetime(lock) {} }
        for var job in try jobs() where job.status == "failed" {
            job.status = "pending"; job.error = nil; try save(job)
        }
    }
    public func latest() -> URL? {
        let markers = (try? fm.contentsOfDirectory(at: paths.completions, includingPropertiesForKeys: nil)) ?? []
        return markers.filter { $0.lastPathComponent.hasSuffix(".recordi-complete.json") }
            .compactMap { try? readJSON(Completion.self, $0) }.filter { successful($0.source) }
            .max { $0.completed < $1.completed }.map { paths.transcripts.appendingPathComponent($0.source.basename + ".txt") }
    }
}

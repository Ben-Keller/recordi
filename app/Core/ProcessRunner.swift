import Foundation
import Darwin

public final class ProcessRunner {
    private let lock = NSLock()
    private var child: Process?
    private var cancelled = false
    public init() {}
    public func cancel() {
        lock.lock(); cancelled = true; let p = child; lock.unlock()
        if let p, p.isRunning { p.terminate() }
    }
    public var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    @discardableResult public func run(_ executable: String, _ arguments: [String], log: URL, timeout: TimeInterval? = nil) throws -> Int32 {
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = arguments
        if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
        let output = try FileHandle(forWritingTo: log); try output.seekToEnd()
        defer { try? output.close() }
        p.standardInput = FileHandle.nullDevice; p.standardOutput = output; p.standardError = output
        lock.lock()
        if cancelled { lock.unlock(); throw RecordiError("Processing interrupted; queued for next launch.") }
        do { try p.run(); child = p; lock.unlock() } catch { lock.unlock(); throw error }
        let start = Date(); var stoppedAt: Date?
        while p.isRunning {
            if isCancelled || timeout.map({ Date().timeIntervalSince(start) > $0 }) == true {
                if stoppedAt == nil { p.terminate(); stoppedAt = Date() }
                else if Date().timeIntervalSince(stoppedAt!) > 2 { kill(p.processIdentifier, SIGKILL) }
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        p.waitUntilExit(); lock.lock(); child = nil; lock.unlock()
        if stoppedAt != nil { throw RecordiError(isCancelled ? "Processing interrupted; queued for next launch." : "Command timed out.") }
        return p.terminationStatus
    }
    public func capture(_ executable: String, _ arguments: [String], timeout: TimeInterval = 10) throws -> String {
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: tmp) }
        let code = try run(executable, arguments, log: tmp, timeout: timeout)
        let text = (try? String(contentsOf: tmp, encoding: .utf8)) ?? ""
        guard code == 0 else { throw RecordiError("Command failed (\(code)): \(text.suffix(800))") }
        return text
    }
}
public struct Configuration: Codable {
    public var whisper: String
    public var model: String
    public var ffmpeg: String?
    public var directFLAC: Bool
    public var audioHijack: String?
    public init(whisper: String, model: String, ffmpeg: String? = nil, directFLAC: Bool = true, audioHijack: String? = nil) {
        self.whisper = whisper; self.model = model; self.ffmpeg = ffmpeg; self.directFLAC = directFLAC; self.audioHijack = audioHijack
    }
    public static func load(_ paths: Paths) throws -> Configuration {
        try readJSON(Configuration.self, paths.support.appendingPathComponent("config.json"))
    }
}

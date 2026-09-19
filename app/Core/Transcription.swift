import Foundation
import AVFoundation

public func validateAudio(_ url: URL) throws {
    let file = try AVAudioFile(forReading: url)
    guard file.length > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16384) else {
        throw RecordiError("Recording has no decodable audio.")
    }
    var frames: AVAudioFramePosition = 0
    while file.framePosition < file.length {
        try file.read(into: buffer)
        guard buffer.frameLength > 0 else { throw RecordiError("Audio ended unexpectedly.") }
        frames += AVAudioFramePosition(buffer.frameLength)
    }
    guard frames == file.length else { throw RecordiError("Recording could not be fully decoded.") }
}
public struct WhisperOutput: Decodable {
    public struct Segment: Decodable {
        public struct Offsets: Decodable { public let from: Int; public let to: Int }
        public let offsets: Offsets
        public let text: String
    }
    public let transcription: [Segment]
    public func validate() throws {
        var last = -1
        for s in transcription {
            guard s.offsets.from >= last, s.offsets.to >= s.offsets.from else { throw RecordiError("Invalid transcript timestamps.") }
            last = s.offsets.from
        }
    }
}
public final class Worker {
    let store: JobStore
    public let runner: ProcessRunner
    public init(paths: Paths, runner: ProcessRunner = ProcessRunner()) { store = JobStore(paths); self.runner = runner }
    @discardableResult public func runOne(config: Configuration) throws -> Job? {
        let paths = store.paths
        // This helper owns the lock until its child has exited, even if the menu app crashes.
        guard let workerLock = try? FileLock(paths.state.appendingPathComponent("worker.lock")) else { return nil }
        defer { withExtendedLifetime(workerLock) {} }
        var selected: Job?
        do {
            let queueLock = try FileLock(paths.state.appendingPathComponent("queue.lock"), wait: true)
            defer { withExtendedLifetime(queueLock) {} }
            for var job in try store.jobs() where job.status == "processing" {
                job.status = store.successful(job.source) ? "complete" : "pending"; try store.save(job)
            }
            selected = try store.jobs().first { $0.status == "pending" }
            if var job = selected { job.status = "processing"; job.attempts += 1; job.error = nil; try store.save(job); selected = job }
        }
        guard var job = selected else { return nil }
        let log = paths.logs.appendingPathComponent(job.source.basename + ".log")
        func note(_ text: String) {
            if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
            if let handle = try? FileHandle(forWritingTo: log) {
                defer { try? handle.close() }; _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: Data("\(Date().ISO8601Format()) \(text)\n".utf8))
            }
        }
        let staging = paths.queue.appendingPathComponent(job.source.id + ".work")
        defer { try? fm.removeItem(at: staging) }
        do {
            note("Attempt \(job.attempts); source: \(job.source.path); Whisper: \(config.whisper); model: \(config.model)")
            guard fm.isExecutableFile(atPath: config.whisper) else { throw RecordiError("whisper-cli is missing. Rerun install.sh.") }
            guard fm.fileExists(atPath: config.model) else { throw RecordiError("Whisper model is missing. Rerun install.sh.") }
            guard try Source(URL(fileURLWithPath: job.source.path), paths: paths) == job.source else {
                throw RecordiError("Source changed after enqueueing. Original audio was left untouched.")
            }
            if store.successful(job.source) { job.status = "complete"; try store.save(job); return job }
            try validateAudio(URL(fileURLWithPath: job.source.path))
            let help = try runner.capture(config.whisper, ["--help"])
            for flag in ["--model", "--file", "--language", "--output-txt", "--output-json-full", "--output-file"] {
                guard help.contains(flag) else { throw RecordiError("Installed whisper-cli lacks \(flag). Rerun install.sh.") }
            }
            note((try? runner.capture(config.whisper, ["--version"])) ?? "Version unavailable")
            try? fm.removeItem(at: staging); try fm.createDirectory(at: staging, withIntermediateDirectories: true)
            var input = job.source.path
            if !config.directFLAC && URL(fileURLWithPath: input).pathExtension.lowercased() == "flac" {
                guard let ffmpeg = config.ffmpeg else { throw RecordiError("FLAC conversion requires ffmpeg. Rerun install.sh.") }
                let wav = staging.appendingPathComponent("input.wav").path
                note("Converting FLAC to temporary WAV")
                guard try runner.run(ffmpeg, ["-nostdin", "-v", "error", "-i", input, "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", wav], log: log) == 0 else { throw RecordiError("Audio conversion failed.") }
                input = wav
            }
            let base = staging.appendingPathComponent("transcript").path
            let exitCode = try runner.run(config.whisper, ["--model", config.model, "--file", input, "--language", "auto", "--output-txt", "--output-json-full", "--output-file", base], log: log)
            note("Whisper exited: \(exitCode)")
            guard exitCode == 0 else { throw RecordiError("Whisper exited with code \(exitCode). See the recording log.") }
            let raw = try Data(contentsOf: URL(fileURLWithPath: base + ".json"))
            let transcript = try JSONDecoder().decode(WhisperOutput.self, from: raw)
            try transcript.validate()
            // Empty text is valid for silence; missing or malformed UTF-8 is not.
            _ = try String(contentsOfFile: base + ".txt", encoding: .utf8)
            guard !runner.isCancelled else { throw RecordiError("Processing interrupted.") }
            guard try Source(URL(fileURLWithPath: job.source.path), paths: paths) == job.source else { throw RecordiError("Source changed during transcription.") }
            for ext in ["txt"] {
                try Data(contentsOf: URL(fileURLWithPath: base + "." + ext)).write(to: paths.transcripts.appendingPathComponent(job.source.basename + "." + ext), options: .atomic)
            }
            let completed = Date()
            try atomic(Completion(source: job.source, completed: completed, outputs: ["txt"]), to: store.marker(job.source))
            job.status = "complete"; job.completed = completed; job.error = nil
            note("Transcription complete")
        } catch {
            job.status = runner.isCancelled ? "pending" : "failed"
            job.error = error.localizedDescription; note("\(job.status): \(error.localizedDescription)")
        }
        let queueLock = try FileLock(paths.state.appendingPathComponent("queue.lock"), wait: true)
        defer { withExtendedLifetime(queueLock) {} }
        try store.save(job); return job
    }
}
public final class RecoveryScanner {
    private var observed: [String: (Source, Date)] = [:]
    public init() {}
    public func scan(paths: Paths, confirmedIdle: Bool, now: Date = Date()) throws {
        guard confirmedIdle else { observed.removeAll(); return }
        let store = JobStore(paths)
        let known = Set(try store.jobs().filter { $0.status != "complete" }.map { $0.source.id })
        for url in try fm.contentsOfDirectory(at: paths.audio, includingPropertiesForKeys: nil) where ["flac", "wav"].contains(url.pathExtension.lowercased()) {
            guard let source = try? Source(url, paths: paths), !known.contains(source.id), !store.successful(source) else { continue }
            if let previous = observed[source.path], previous.0 == source, now.timeIntervalSince(previous.1) >= 15,
               now.timeIntervalSince1970 - source.modified >= 15 {
                // Worker validates full decoding before invoking Whisper; unreadable files become failed jobs.
                try store.enqueue(url)
            } else if observed[source.path]?.0 != source { observed[source.path] = (source, now) }
        }
    }
}

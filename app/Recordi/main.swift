import Foundation
import AppKit
import ServiceManagement
import RecordiCore
import Darwin

let env = ProcessInfo.processInfo.environment
let paths = Paths(home: env["RECORDI_HOME"].map { URL(fileURLWithPath: $0) } ?? fm.homeDirectoryForCurrentUser)
let args = Array(CommandLine.arguments.dropFirst())
let bridge = AudioHijackBridge(paths: paths, executable: paths.executable.path)
if args.isEmpty {
    let app = NSApplication.shared
    let delegate = AppDelegate(paths: paths); app.delegate = delegate
    withExtendedLifetime(delegate) { app.run() }
} else {
    do {
        try paths.create()
        switch args[0] {
        case "--enqueue":
            guard args.count == 2 else { throw RecordiError("Usage: --enqueue /absolute/recording.mp3") }
            _ = try JobStore(paths).enqueue(URL(fileURLWithPath: args[1]))
        case "--reply":
            guard args.count == 2 else { throw RecordiError("Usage: --reply JSON") }
            try bridge.saveReply(args[1])
        case "--work-one":
            let runner = ProcessRunner()
            signal(SIGTERM, SIG_IGN); signal(SIGINT, SIG_IGN)
            let term = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
            let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
            term.setEventHandler { runner.cancel() }; interrupt.setEventHandler { runner.cancel() }
            term.resume(); interrupt.resume()
            let result = try Worker(paths: paths, runner: runner).runOne(config: Configuration.load(paths))
            withExtendedLifetime((term, interrupt)) {}
            if let result {
                print("\(result.status): \(result.source.basename)")
                if result.status == "failed" { throw RecordiError(result.error ?? "Transcription failed.") }
            }
        case "--configure":
            guard args.count >= 3 else { throw RecordiError("Usage: --configure WHISPER AUDIO_HIJACK [MODEL]") }
            let help = try ProcessRunner().capture(args[1], ["--help"])
            let direct = help.contains("supported audio formats: flac")
            let ffmpeg = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"].first { fm.isExecutableFile(atPath: $0) }
            guard (direct && help.contains("mp3")) || ffmpeg != nil else { throw RecordiError("This Whisper build requires ffmpeg. Install it with brew install ffmpeg.") }
            let config = Configuration(whisper: args[1], model: args.count > 3 ? args[3] : paths.model.path, ffmpeg: ffmpeg, directFLAC: direct, audioHijack: args[2])
            try atomic(config, to: paths.support.appendingPathComponent("config.json"))
            try bridge.installScripts()
        case "--generate-script": print(bridge.completionScript())
        case "--status":
            let config = try Configuration.load(paths)
            let reply = try bridge.perform("status", audioHijack: config.audioHijack ?? "")
            print(String(data: try JSONEncoder().encode(reply), encoding: .utf8)!)
        case "--diagnose":
            let config = try Configuration.load(paths)
            print("Audio Hijack: \(config.audioHijack ?? "missing")")
            print("Whisper: \(config.whisper) (\(fm.isExecutableFile(atPath: config.whisper) ? "available" : "missing"))")
            print("Model: \(config.model) (\(fm.fileExists(atPath: config.model) ? "available" : "missing"))")
            print("Queue: \(try JobStore(paths).jobs().count) jobs")
            print("Audio routing requires one-time manual verification.")
        case "--unregister-login":
            if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval { try SMAppService.mainApp.unregister() }
        case "--quit-app":
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: "local.recordi.app")
                .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            for app in running { _ = app.terminate() }
            let deadline = Date().addingTimeInterval(15)
            // NSRunningApplication caches isTerminated until a run-loop turn; use a live process check here.
            while running.contains(where: { kill($0.processIdentifier, 0) == 0 }) && Date() < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            guard running.allSatisfy({ kill($0.processIdentifier, 0) != 0 }) else { throw RecordiError("Quit Recordi from its menu, then rerun installation.") }
        case "--enable-login":
            try SMAppService.mainApp.register()
            print("Launch at login: \(SMAppService.mainApp.status == .enabled ? "enabled" : "approve in System Settings → General → Login Items")")
        default: throw RecordiError("Unknown Recordi command: \(args[0])")
        }
    } catch {
        fputs("Recordi: \(error.localizedDescription)\n", stderr); exit(1)
    }
}

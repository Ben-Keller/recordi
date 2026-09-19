import Foundation
import JavaScriptCore
import RecordiCore

final class CoreTests {
    var paths: Paths!
    var root: URL!
    func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("Recordi tests ü ' " + UUID().uuidString)
        paths = Paths(home: root); try paths.create()
    }
    func tearDownWithError() throws { try? fm.removeItem(at: root) }
    func audio(_ name: String = "Meeting ' İstanbul.wav") throws -> URL {
        let url = paths.audio.appendingPathComponent(name)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("fixtures/jfk.wav")
        try fm.copyItem(at: fixture, to: url); return url
    }
    func mock(fail: Bool = false, delay: Bool = false) throws -> Configuration {
        let script = root.appendingPathComponent("mock whisper ' ü")
        let body = """
        #!/bin/bash
        set -eu
        if [[ "$1" == "--help" ]]; then
          echo '--model --file --language --output-txt --output-srt --output-json-full --output-file'; exit 0
        fi
        if [[ "$1" == "--version" ]]; then echo 'Mock 1'; exit 0; fi
        \(delay ? "/bin/sleep 0.5" : ":")
        \(fail ? "exit 9" : ":")
        while [[ $# -gt 0 ]]; do
          if [[ "$1" == "--output-file" ]]; then base="$2"; shift 2; else shift; fi
        done
        printf '%s' 'Hello from a local meeting.' > "$base.txt"
        printf '1\\n00:00:00,000 --> 00:00:02,000\\nHello from a local meeting.\\n' > "$base.srt"
        printf '%s' '{"transcription":[{"offsets":{"from":0,"to":2000},"text":" Hello from a local meeting."}]}' > "$base.json"
        """
        try Data(body.utf8).write(to: script)
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        try Data("mock".utf8).write(to: paths.model)
        return Configuration(whisper: script.path, model: paths.model.path)
    }
    func testQueueDeduplicatesAndRejectsOutsidePaths() throws {
        let store = JobStore(paths); let file = try audio()
        checkTrue(try store.enqueue(file)); checkFalse(try store.enqueue(file))
        checkEqual(try store.jobs().count, 1)
        checkThrows(try store.enqueue(root.appendingPathComponent("anything.wav")))
    }
    func testSequentialOutputAndCompletionSurviveStateRemoval() throws {
        let config = try mock(); let store = JobStore(paths)
        let first = try audio(); let second = try audio("Next meeting.wav")
        let original = try Data(contentsOf: first)
        try store.enqueue(first); try store.enqueue(second)
        let worker = Worker(paths: paths)
        checkEqual(try worker.runOne(config: config)?.status, "complete")
        checkEqual(try store.jobs().filter { $0.status == "pending" }.count, 1)
        checkEqual(try worker.runOne(config: config)?.status, "complete")
        checkNil(try worker.runOne(config: config))
        checkEqual(try Data(contentsOf: first), original)
        let source = try Source(first, paths: paths)
        checkTrue(store.successful(source)); checkEqual(store.latest()?.pathExtension, "txt")
        checkTrue(try fm.contentsOfDirectory(at: paths.transcripts, includingPropertiesForKeys: nil).allSatisfy { $0.pathExtension == "txt" })
        try fm.removeItem(at: paths.queue); try fm.createDirectory(at: paths.queue, withIntermediateDirectories: true)
        checkFalse(try store.enqueue(first))
        try fm.removeItem(at: paths.transcripts.appendingPathComponent(source.basename + ".txt"))
        checkFalse(store.successful(source))
    }
    func testFailureExplicitRetryAndInterruptedRecovery() throws {
        let file = try audio(); let store = JobStore(paths); try store.enqueue(file)
        checkEqual(try Worker(paths: paths).runOne(config: mock(fail: true))?.status, "failed")
        checkNil(try Worker(paths: paths).runOne(config: mock()))
        try store.retryFailed()
        var job = try unwrap(store.jobs().first); job.status = "processing"; try store.save(job)
        checkEqual(try Worker(paths: paths).runOne(config: mock())?.status, "complete")
        checkTrue(fm.fileExists(atPath: file.path))
    }
    func testMissingDependenciesAndBadAudioFailWithoutDeleting() throws {
        let file = try audio(); let store = JobStore(paths); try store.enqueue(file)
        var config = try mock(); config.whisper = root.appendingPathComponent("absent").path
        checkEqual(try Worker(paths: paths).runOne(config: config)?.status, "failed")
        try store.retryFailed(); config = try mock(); config.model = root.appendingPathComponent("no model").path
        checkEqual(try Worker(paths: paths).runOne(config: config)?.status, "failed")
        checkTrue(fm.fileExists(atPath: file.path))
        let bad = paths.audio.appendingPathComponent("bad.flac"); try Data("not audio".utf8).write(to: bad)
        try store.enqueue(bad)
        checkEqual(try Worker(paths: paths).runOne(config: mock())?.status, "failed")
        checkEqual(try String(contentsOf: bad), "not audio")
    }
    func testWorkerLockExcludesAnotherWorker() throws {
        let store = JobStore(paths); try store.enqueue(audio())
        let lock = try FileLock(paths.state.appendingPathComponent("worker.lock"))
        checkNil(try Worker(paths: paths).runOne(config: mock()))
        checkEqual(try store.jobs().first?.status, "pending")
        withExtendedLifetime(lock) {}
    }
    func testRecordingControlsRemainUsableDuringTranscription() throws {
        let store = JobStore(paths); try store.enqueue(audio()); let config = try mock(delay: true)
        let done = DispatchSemaphore(value: 0)
        let worker = Worker(paths: paths)
        DispatchQueue.global().async { _ = try? worker.runOne(config: config); done.signal() }
        var state = CaptureState(); checkTrue(state.begin("status"))
        state.accept(SessionReply(id: "x", running: false, runTime: 0))
        checkTrue(state.begin("start")); checkFalse(state.begin("start"))
        state.accept(SessionReply(id: "x", running: true, runTime: 0))
        checkTrue(state.begin("stop"))
        checkEqual(done.wait(timeout: .now() + 10), .success)
        checkEqual(try store.jobs().first?.status, "complete")
    }
    func testRecoveryDefersActiveUnknownAndUnstableFiles() throws {
        let file = try audio(); let source = try Source(file, paths: paths); let store = JobStore(paths)
        let scan = RecoveryScanner(); let now = Date(timeIntervalSince1970: source.modified + 30)
        try scan.scan(paths: paths, confirmedIdle: false, now: now)
        checkTrue(try store.jobs().isEmpty)
        try scan.scan(paths: paths, confirmedIdle: true, now: now)
        checkTrue(try store.jobs().isEmpty)
        try scan.scan(paths: paths, confirmedIdle: false, now: now.addingTimeInterval(20))
        try scan.scan(paths: paths, confirmedIdle: true, now: now.addingTimeInterval(40))
        checkTrue(try store.jobs().isEmpty)
        try scan.scan(paths: paths, confirmedIdle: true, now: now.addingTimeInterval(60))
        checkEqual(try store.jobs().count, 1)
    }
    func testBridgeAcknowledgementTimeoutAndMissingApp() throws {
        let bridge = AudioHijackBridge(paths: paths, executable: "/some/helper")
        let result = try bridge.perform("status", audioHijack: root.path, timeout: 0.2, isRunning: { true }) { command in
            let id = command.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "request-", with: "")
            try atomic(SessionReply(id: id, running: true, runTime: 42), to: self.paths.state.appendingPathComponent("reply-" + id + ".json"))
        }
        checkEqual(result.runTime, 42)
        checkThrows(try bridge.perform("status", audioHijack: root.path, timeout: 0.1, isRunning: { true }) { _ in })
        for action in ["status", "stop"] {
            let idle = try bridge.perform(action, audioHijack: root.path, isRunning: { false }) { _ in
                throw RecordiError("Must not launch Audio Hijack while idle")
            }
            checkEqual(idle.running, false)
        }
        var launched = false
        let started = try bridge.perform("start", audioHijack: root.path, isRunning: { false }) { command in
            launched = true
            let id = command.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "request-", with: "")
            try atomic(SessionReply(id: id, running: true, runTime: 0), to: self.paths.state.appendingPathComponent("reply-" + id + ".json"))
        }
        checkTrue(launched)
        checkEqual(started.running, true)
        checkThrows(try bridge.perform("status", audioHijack: "/absent"))
        var state = CaptureState(); _ = state.begin("status"); state.fail("Timeout")
        checkFalse(state.begin("start")); checkTrue(state.begin("status"))
    }
    func testGeneratedJavaScriptUsesActualStateAndRejectsMissingSession() throws {
        let bridge = AudioHijackBridge(paths: paths, executable: "/A ' ü/Recordi")
        let context = JSContext()!
        context.evaluateScript("""
        var starts = 0, stops = 0, payload;
        var s = {name: 'Meeting Recorder', running: false, runTime: 0,
          start: function(){ starts++; this.running=true; }, stop: function(){ stops++; this.running=false; }};
        var app = {sessions:[s], shellEscapeArgument:function(x){ payload=x; return x; }, runShellCommand:function(){return [0,'',''];}};
        """)
        for action in ["start", "start", "stop", "stop"] {
            context.evaluateScript(bridge.script(action: action, id: UUID().uuidString, expires: Date().timeIntervalSince1970 + 60))
            checkNil(context.exception)
        }
        checkEqual(context.objectForKeyedSubscript("starts").toInt32(), 1)
        checkEqual(context.objectForKeyedSubscript("stops").toInt32(), 1)
        context.evaluateScript("app.sessions=[];")
        context.evaluateScript(bridge.script(action: "start", id: UUID().uuidString, expires: Date().timeIntervalSince1970 + 60))
        checkTrue(context.objectForKeyedSubscript("payload").toString().contains("found 0"))
        context.evaluateScript("app.sessions=[s];")
        context.evaluateScript(bridge.script(action: "start", id: UUID().uuidString, expires: 0))
        checkEqual(context.objectForKeyedSubscript("starts").toInt32(), 1)
    }
    func testProcessArgumentsAreLiteralAndTimeoutIsBounded() throws {
        let value = "spaces ' ü $(touch /tmp/recordi-should-never-exist); `whoami`"
        checkEqual(try ProcessRunner().capture("/usr/bin/printf", ["%s", value]), value)
        checkThrows(try ProcessRunner().capture("/bin/sleep", ["2"], timeout: 0.1))
    }
    func testMalformedOutputsAreNotSuccessful() throws {
        let file = try audio(); let source = try Source(file, paths: paths)
        try Data("partial".utf8).write(to: paths.transcripts.appendingPathComponent(source.basename + ".md"))
        checkFalse(JobStore(paths).successful(source))
        let bad = Data("{\"transcription\":[{\"offsets\":{\"from\":4,\"to\":2},\"text\":\"x\"}]}".utf8)
        let parsed = try JSONDecoder().decode(WhisperOutput.self, from: bad)
        checkThrows(try parsed.validate())
    }
    func testCancellationRequeuesAndSourceChangesFailSafely() throws {
        let file = try audio(); let store = JobStore(paths); try store.enqueue(file)
        let config = try mock(delay: true)
        let runner = ProcessRunner(); let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { _ = try? Worker(paths: self.paths, runner: runner).runOne(config: config); done.signal() }
        Thread.sleep(forTimeInterval: 0.1); runner.cancel()
        checkEqual(done.wait(timeout: .now() + 5), .success)
        checkEqual(try store.jobs().first?.status, "pending")
        checkTrue(fm.fileExists(atPath: file.path))
        let handle = try FileHandle(forWritingTo: file); try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
        checkEqual(try Worker(paths: paths).runOne(config: config)?.status, "failed")
        checkTrue(fm.fileExists(atPath: file.path))
    }
}

import AppKit
import UserNotifications
import ServiceManagement
import RecordiCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    let paths: Paths
    let store: JobStore
    let bridge: AudioHijackBridge
    var appLock: FileLock?
    var statusItem: NSStatusItem!
    var menu = NSMenu()
    var capture = CaptureState()
    var elapsedBase: (Double, Date)?
    var timer: Timer?
    var tick = 0
    var worker: Process?
    var workerOutput: FileHandle?
    var scanBusy = false
    let scanner = RecoveryScanner()
    let scannerQueue = DispatchQueue(label: "Recordi.recovery", qos: .utility)
    var jobs: [Job] = []
    var notified: [String: String] = [:]
    var latest: URL?
    var latestRefreshBusy = false
    var runtimeError: String?
    var panel: NSWindow?
    var diagnosticsText: NSTextField?
    var quitting = false
    init(paths: Paths) {
        self.paths = paths; store = JobStore(paths)
        bridge = AudioHijackBridge(paths: paths, executable: paths.executable.path)
        super.init()
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        do { try paths.create(); appLock = try FileLock(paths.state.appendingPathComponent("app.lock")) }
        catch { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.isVisible = true
        menu.delegate = self; statusItem.menu = menu
        UNUserNotificationCenter.current().delegate = self
        if ProcessInfo.processInfo.environment["RECORDI_SMOKE_TEST"] != "1" {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        notified = (try? readJSON([String: String].self, paths.state.appendingPathComponent("notified.json"))) ?? [:]
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke), name: NSWorkspace.didWakeNotification, object: nil)
        refreshJobs(); query("status"); render()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.pulse() }
        // A noninteractive launch smoke test uses the real AppKit lifecycle/menu and exits cleanly.
        if ProcessInfo.processInfo.environment["RECORDI_SMOKE_TEST"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                let menuTitles = self.menu.items.map(\.title)
                try? atomic(menuTitles, to: self.paths.state.appendingPathComponent("launch-smoke.json"))
                self.diagnostics()
                try? atomic(["windowCreated": self.panel != nil, "textMatches": self.diagnosticsText?.stringValue == self.diagnosticSummary()], to: self.paths.state.appendingPathComponent("diagnostics-smoke.json"))
                self.closePanel()
                // Regression: a scan due on the same tick as status must see the last confirmed idle state.
                // Seed one stable observation of the isolated test fixture, then exercise the real pulse().
                self.timer?.invalidate()
                do { try self.scanner.scan(paths: self.paths, confirmedIdle: true, now: Date().addingTimeInterval(-20)) }
                catch { self.runtimeError = error.localizedDescription }
                self.capture.accept(SessionReply(id: "smoke", running: false, runTime: 0))
                self.tick = 14
                self.pulse()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    let recovered = (try? self.store.jobs().contains { $0.source.basename == "Recovery fixture" }) ?? false
                    try? atomic(["recoveredOnStatusTick": recovered], to: self.paths.state.appendingPathComponent("recovery-smoke.json"))
                    self.quit()
                }
            }
        }
    }
    @objc func woke() { elapsedBase = nil; query("status") }
    func pulse() {
        guard !quitting else { return }
        tick += 1
        if tick % 2 == 0 { refreshJobs(); startWorker() }
        if tick % 15 == 0 { recover() }
        // Scan before starting a status request: query() marks capture busy synchronously.
        // The old order made every 15-second scan skip, since status also runs every 5 seconds.
        if tick % (capture.error == nil ? 5 : 30) == 0 { query("status") }
        render()
    }
    func query(_ action: String) {
        guard !quitting, capture.begin(action) else { return }
        render()
        DispatchQueue.global(qos: .utility).async {
            let result = Result { () -> SessionReply in
                let config = try Configuration.load(self.paths)
                guard let ah = config.audioHijack else { throw RecordiError("Audio Hijack is not configured. Rerun install.sh.") }
                var reply = try self.bridge.perform(action, audioHijack: ah)
                if action != "status" {
                    let wanted = action == "start"
                    let deadline = Date().addingTimeInterval(3)
                    while reply.running != wanted && Date() < deadline {
                        Thread.sleep(forTimeInterval: 0.15)
                        reply = try self.bridge.perform("status", audioHijack: ah)
                    }
                    guard reply.running == wanted else {
                        throw RecordiError("Audio Hijack did not reach the requested state. Checking again before allowing another command.")
                    }
                }
                return reply
            }
            DispatchQueue.main.async {
                switch result {
                case .success(let reply):
                    self.capture.accept(reply)
                    self.elapsedBase = reply.running == true ? reply.runTime.map { ($0, Date()) } : nil
                case .failure(let error): self.capture.fail(error.localizedDescription); self.elapsedBase = nil
                }
                self.render()
            }
        }
    }
    func refreshJobs() {
        do {
            jobs = try store.jobs()
            refreshLatest()
            var notificationsChanged = false
            for job in jobs where job.status == "complete" || job.status == "failed" {
                let key = "\(job.status)-\(job.attempts)"
                if notified[job.source.id] != key {
                    let content = UNMutableNotificationContent()
                    content.title = job.status == "complete" ? "Meeting transcript ready" : "Meeting transcription failed"
                    content.body = job.source.basename
                    if job.status == "complete" { content.userInfo = ["path": paths.transcripts.appendingPathComponent(job.source.basename + ".txt").path] }
                    UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: job.source.id + key, content: content, trigger: nil))
                    notified[job.source.id] = key
                    notificationsChanged = true
                }
            }
            if notificationsChanged { try atomic(notified, to: paths.state.appendingPathComponent("notified.json")) }
        } catch { runtimeError = error.localizedDescription }
    }
    func refreshLatest() {
        guard !latestRefreshBusy else { return }
        latestRefreshBusy = true
        DispatchQueue.global(qos: .utility).async {
            let transcript = self.store.latest()
            DispatchQueue.main.async {
                self.latest = transcript
                self.latestRefreshBusy = false
            }
        }
    }
    func startWorker() {
        guard worker == nil, jobs.contains(where: { ["pending", "processing"].contains($0.status) }), !quitting else { return }
        let process = Process(); process.executableURL = paths.executable; process.arguments = ["--work-one"]
        do {
            let log = paths.logs.appendingPathComponent("Recordi.log")
            if !fm.fileExists(atPath: log.path) { fm.createFile(atPath: log.path, contents: nil) }
            let handle = try FileHandle(forWritingTo: log); try handle.seekToEnd(); workerOutput = handle
            process.standardInput = FileHandle.nullDevice; process.standardOutput = handle; process.standardError = handle
            process.terminationHandler = { [weak self] _ in DispatchQueue.main.async {
                guard let self else { return }; self.worker = nil; try? self.workerOutput?.close(); self.workerOutput = nil
                self.refreshJobs(); self.render()
            } }
            try process.run(); worker = process
        } catch { runtimeError = error.localizedDescription }
    }
    func recover() {
        guard !scanBusy else { return }
        scanBusy = true
        let idle = capture.running == false && !capture.busy
        scannerQueue.async {
            let result = Result { try self.scanner.scan(paths: self.paths, confirmedIdle: idle) }
            DispatchQueue.main.async {
                self.scanBusy = false
                if case .failure(let error) = result { self.runtimeError = error.localizedDescription }
            }
        }
    }
    var elapsed: String {
        guard let (seconds, date) = elapsedBase else { return "Recording" }
        let s = max(0, Int(seconds + Date().timeIntervalSince(date)))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%02d:%02d", s / 60, s % 60)
    }
    func menuWillOpen(_ menu: NSMenu) { render(); query("status") }
    func render() {
        guard statusItem != nil else { return }
        let recording = capture.running == true
        statusItem.length = recording ? NSStatusItem.variableLength : NSStatusItem.squareLength
        let button = statusItem.button!
        button.imagePosition = recording ? .imageLeading : .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.image = IconArt.menu(recording: recording, needsAttention: capture.error != nil)
        button.contentTintColor = recording ? .systemRed : nil
        button.title = recording ? " " + elapsed : ""
        button.toolTip = recording ? "Recordi — recording" : "Recordi"
        var desired: [NSMenuItem] = []
        func item(_ title: String, _ selector: Selector?, enabled: Bool = true) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: ""); item.target = self; item.isEnabled = enabled; desired.append(item); return item
        }
        menu.autoenablesItems = false
        let title = capture.busy ? (capture.running == nil ? "Checking Audio Hijack…" : "Updating…") : (recording ? "Stop Recording" : "Start Recording")
        _ = item(title, #selector(toggleRecording), enabled: !capture.busy && capture.running != nil)
        if recording { _ = item("Recording: " + elapsed, nil, enabled: false) }
        let count = jobs.filter { ["pending", "processing"].contains($0.status) }.count
        if count > 0 { _ = item("Transcribing: \(count) meeting\(count == 1 ? "" : "s")", nil, enabled: false) }
        if capture.error != nil { _ = item("Audio Hijack needs setup — Diagnostics", #selector(diagnostics)) }
        let failed = jobs.filter { $0.status == "failed" }.count
        if failed > 0 { _ = item("\(failed) failed — Diagnostics", #selector(diagnostics)) }
        desired.append(.separator())
        _ = item("Open Recordi Folder", #selector(openRecordi))
        _ = item("Open Latest Transcript", #selector(openLatest), enabled: latest != nil)
        _ = item("Diagnostics", #selector(diagnostics))
        let login = item("Launch at Login", #selector(toggleLogin)); login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        desired.append(.separator()); _ = item("Quit", #selector(quit))
        // Preserve tracked menu items while the timer updates; avoid replacing a row under the pointer.
        if menu.items.count == desired.count && zip(menu.items, desired).allSatisfy({ $0.isSeparatorItem == $1.isSeparatorItem }) {
            for (existing, updated) in zip(menu.items, desired) {
                existing.title = updated.title; existing.action = updated.action; existing.target = self
                existing.isEnabled = updated.isEnabled; existing.state = updated.state
            }
        } else {
            menu.removeAllItems(); desired.forEach { menu.addItem($0) }
        }
        diagnosticsText?.stringValue = diagnosticSummary()
    }
    @objc func toggleRecording() { query(capture.running == true ? "stop" : "start") }
    @objc func openRecordi() { NSWorkspace.shared.open(paths.recordi) }
    @objc func openLatest() { if let latest { NSWorkspace.shared.activateFileViewerSelecting([latest]) } }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register(); if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() } }
        } catch { runtimeError = error.localizedDescription; diagnostics() }
        render()
    }
    func diagnosticSummary() -> String {
        let config = try? Configuration.load(paths)
        let ah = config?.audioHijack.map { fm.fileExists(atPath: $0) } ?? false
        return """
        Audio Hijack installed: \(ah ? "Yes" : "No")
        Session: \(capture.running == nil ? "Unknown / needs setup" : "Meeting Recorder")
        Session running: \(capture.running.map { $0 ? "Yes" : "No" } ?? "Unknown")
        Recorder output/routing: Requires one-time manual verification
        whisper-cli: \(config.map { fm.isExecutableFile(atPath: $0.whisper) } == true ? "Available" : "Missing")
        large-v3-turbo model: \(config.map { fm.fileExists(atPath: $0.model) } == true ? "Available" : "Missing")
        Audio folder writable: \(fm.isWritableFile(atPath: paths.audio.path) ? "Yes" : "No")
        Transcript folder writable: \(fm.isWritableFile(atPath: paths.transcripts.path) ? "Yes" : "No")
        Queue writable: \(fm.isWritableFile(atPath: paths.queue.path) ? "Yes" : "No")
        Pending / processing: \(jobs.filter { ["pending", "processing"].contains($0.status) }.count)
        Failed: \(jobs.filter { $0.status == "failed" }.count)

        \(capture.error ?? runtimeError ?? jobs.last(where: { $0.status == "failed" })?.error ?? "No errors reported.")

        Quit leaves Audio Hijack recording. Pending transcription resumes next launch.
        """
    }
    @objc func diagnostics() {
        if panel == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 610, height: 430), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Recordi Diagnostics"; window.isReleasedWhenClosed = false; window.center()
            let text = NSTextField(wrappingLabelWithString: diagnosticSummary()); text.font = .systemFont(ofSize: 13); text.isSelectable = true
            text.frame = NSRect(x: 22, y: 70, width: 566, height: 338); window.contentView?.addSubview(text); diagnosticsText = text
            let buttons: [(String, Selector)] = [("Recordi Folder", #selector(openRecordi)), ("Retry Failed Jobs", #selector(retry)), ("Reveal Log", #selector(revealLog)), ("Close", #selector(closePanel))]
            for (i, spec) in buttons.enumerated() {
                let button = NSButton(title: spec.0, target: self, action: spec.1); button.bezelStyle = .rounded
                button.frame = NSRect(x: 18 + i * 146, y: 20, width: 140, height: 32); window.contentView?.addSubview(button)
            }
            panel = window
        }
        render(); panel?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
    }
    @objc func closePanel() { panel?.close() }
    @objc func retry() { do { try store.retryFailed(); runtimeError = nil; refreshJobs(); startWorker() } catch { runtimeError = error.localizedDescription }; render() }
    @objc func revealLog() {
        let url = jobs.last(where: { $0.status == "failed" }).map { paths.logs.appendingPathComponent($0.source.basename + ".log") } ?? paths.logs
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        quitting = true; timer?.invalidate()
        guard let worker, worker.isRunning else { return .terminateNow }
        worker.terminate()
        DispatchQueue.global().async {
            worker.waitUntilExit()
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        }
        return .terminateLater
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["path"] as? String {
            DispatchQueue.main.async { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        }
        completionHandler()
    }
}

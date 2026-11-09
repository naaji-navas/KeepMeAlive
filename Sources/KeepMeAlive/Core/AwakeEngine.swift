import AppKit
import Foundation
import Observation
import ServiceManagement
import UserNotifications

/// The brain: owns the session and wires lid, sleep, apps, network and safety together.
@MainActor
@Observable
final class AwakeEngine {
    nonisolated static let commandNotification = Notification.Name("com.keepmealive.command")

    // Settings
    var config: Config { didSet { if config != oldValue { configChanged(from: oldValue) } } }

    // Session
    private(set) var active = false
    private(set) var mode: SessionMode = .indefinite
    private(set) var engaged = false
    private(set) var startedAt: Date?

    // Live status
    private(set) var lidClosed = false
    private(set) var hasLid = true
    private(set) var lidProofReady = false
    private(set) var sleepDisabledByUs = false
    private(set) var frozenApps: [String] = []
    private(set) var networkSummary = "—"
    private(set) var networkAction = ""
    private(set) var networkOnline = true
    private(set) var onHotspot = false
    private(set) var battery: PowerSafety.Battery?
    private(set) var agentProcesses: [String] = []
    private(set) var runningKeepAliveApps: Set<String> = []
    private(set) var lastEvent = ""
    private(set) var now = Date()
    private(set) var launchAtLogin = false

    private let freezer = AppFreezer()
    private let network = NetworkGuardian()
    private var timer: Timer?
    private var tickCount = 0
    private var mutedByUs = false
    private var activity: NSObjectProtocol?
    private var signalSources: [DispatchSourceSignal] = []

    init() {
        config = Config.load()
        seedDefaultsIfNeeded()
        recoverFromPreviousRun()
        lidProofReady = SleepControl.isLidProofAuthorized()
        hasLid = Lid.isClosed() != nil
        lidClosed = Lid.isClosed() ?? false
        launchAtLogin = SMAppService.mainApp.status == .enabled
        battery = PowerSafety.battery()
        refreshAgents()

        network.onUpdate = { [weak self] in self?.syncNetwork() }
        network.notify = { [weak self] t, b in self?.notify(t, b) }

        if Bundle.main.bundleIdentifier != nil {
            Watchdog.install()
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer!, forMode: .common)

        DistributedNotificationCenter.default().addObserver(forName: Self.commandNotification, object: nil, queue: .main) { [weak self] note in
            let cmd = note.object as? String ?? ""
            Task { @MainActor in self?.handleCommand(cmd) }
        }
        installSignalHandlers()
        persist()
        Log.info("KeepMeAlive started (lid-proof ready: \(lidProofReady))")
    }

    // MARK: Session control

    func start(_ mode: SessionMode) {
        self.mode = mode
        active = true
        startedAt = Date()
        if case .until(let d) = mode { config.lastDurationMinutes = Int(d.timeIntervalSinceNow / 60) }
        if case .indefinite = mode { config.lastDurationMinutes = 0 }
        lidProofReady = SleepControl.isLidProofAuthorized()
        if !config.hotspotSSID.isEmpty, config.failoverEnabled, !LocationGate.shared.isAuthorized {
            LocationGate.shared.request()
        }
        event("Session started · \(modeDescription)")
        evaluate()
    }

    func start(minutes: Int) {
        start(minutes <= 0 ? .indefinite : .until(Date().addingTimeInterval(TimeInterval(minutes * 60))))
    }

    func extend(minutes: Int) {
        guard active else { return start(minutes: minutes) }
        if case .until(let d) = mode {
            mode = .until(max(d, Date()).addingTimeInterval(TimeInterval(minutes * 60)))
            event("Extended by \(minutes)m")
            persist()
        }
    }

    func stop(reason: String = "Stopped") {
        guard active else { return }
        active = false
        event("Session ended · \(reason)")
        evaluate()
    }

    func toggle() { active ? stop() : start(minutes: config.lastDurationMinutes) }

    var remaining: TimeInterval? {
        if case .until(let d) = mode, active { return max(0, d.timeIntervalSince(now)) }
        return nil
    }

    var modeDescription: String {
        switch mode {
        case .indefinite: return "until you stop it"
        case .until(let d): return "until \(d.formatted(date: .omitted, time: .shortened))"
        case .whileAgentsRun: return "while agents run"
        }
    }

    /// Should we be holding the Mac awake right now?
    private var shouldEngage: Bool {
        guard active else { return false }
        if case .whileAgentsRun = mode {
            return !runningKeepAliveApps.isEmpty || !agentProcesses.isEmpty
        }
        return true
    }

    private func evaluate() {
        let want = shouldEngage
        if want && !engaged { engage() }
        if !want && engaged { disengage() }
        persist()
    }

    private func engage() {
        engaged = true
        SleepControl.holdIdleAssertion(true)
        if activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                             reason: "Keeping agent sessions alive")
        }
        if lidProofReady {
            if SleepControl.isSleepDisabled() {
                Log.info("SleepDisabled already 1 (set by someone else); leaving it alone on exit")
            } else if SleepControl.setSleepDisabled(true) {
                sleepDisabledByUs = true
            } else {
                event("Could not make the session lid-proof")
            }
        }
        applyAppNapPolicy()
        network.start(config: config)
        if lidClosed { applyLidClosed() }
        Log.info("engaged")
    }

    private func disengage() {
        engaged = false
        restoreLidActions()
        if sleepDisabledByUs {
            if SleepControl.setSleepDisabled(false) { sleepDisabledByUs = false }
            else { event("Could not re-enable sleep — run: sudo pmset -a disablesleep 0") }
        }
        SleepControl.holdIdleAssertion(false)
        if let a = activity { ProcessInfo.processInfo.endActivity(a); activity = nil }
        network.stop()
        Log.info("disengaged")
    }

    /// Called on quit and on SIGTERM. Must leave the system exactly as we found it.
    func shutdown() {
        active = false
        if engaged { disengage() }
        freezer.resumeAll()
        if sleepDisabledByUs, SleepControl.setSleepDisabled(false) { sleepDisabledByUs = false }
        var s = RuntimeState.empty
        s.sleepDisabledByUs = sleepDisabledByUs // keep for the watchdog if the undo failed
        s.appPid = sleepDisabledByUs ? 0 : getpid()
        if sleepDisabledByUs { s.save() } else { try? FileManager.default.removeItem(at: Paths.state) }
        Log.info("KeepMeAlive quit")
    }

    // MARK: Lid

    private func applyLidClosed() {
        event("Lid closed — keeping \(keepSummary) alive")
        if config.freezeOthersOnLidClose { freezeSweep() }
        if config.sleepDisplayOnLidClose { SleepControl.sleepDisplaysNow() }
        if config.muteOnLidClose, !AudioMute.isMuted() { AudioMute.set(true); mutedByUs = true }
        persist()
    }

    private func restoreLidActions() {
        freezer.resumeAll()
        frozenApps = []
        if mutedByUs { AudioMute.set(false); mutedByUs = false }
        persist()
    }

    private func freezeSweep() {
        freezer.freeze(keepBundleIDs: keepBundleIDs, keepProcessNames: Set(config.keepAliveProcesses))
        frozenApps = freezer.frozenAppNames
    }

    private var keepBundleIDs: Set<String> { Set(config.keepAliveApps.map(\.bundleID)) }

    private var keepSummary: String {
        let names = config.keepAliveApps.filter { runningKeepAliveApps.contains($0.bundleID) }.map(\.name) + agentProcesses
        return names.isEmpty ? "the Mac" : names.prefix(3).joined(separator: ", ") + (names.count > 3 ? "…" : "")
    }

    // MARK: Tick

    private func tick() {
        tickCount += 1
        now = Date()

        if let closed = Lid.isClosed(), closed != lidClosed {
            lidClosed = closed
            if engaged {
                if closed { applyLidClosed() } else { restoreLidActions(); event("Lid opened — apps resumed") }
            }
        }

        if active, case .until(let d) = mode, d <= now { stop(reason: "timer finished") }

        if tickCount % 3 == 0 { refreshAgents(); if active { evaluate() } }

        if engaged && lidClosed {
            if config.freezeOthersOnLidClose && tickCount % 5 == 0 { freezeSweep(); persist() }
            if config.sleepDisplayOnLidClose && tickCount % 15 == 0 && SleepControl.anyDisplayAwake() {
                SleepControl.sleepDisplaysNow()
            }
        }

        if tickCount % 15 == 0 { safetyCheck() }
        if tickCount % 30 == 0 { lidProofReady = SleepControl.isLidProofAuthorized() }
    }

    private func safetyCheck() {
        battery = PowerSafety.battery()
        guard engaged else { return }
        if let b = battery, !b.onAC, config.batteryFloorPercent > 0, b.percent <= config.batteryFloorPercent {
            notify("Battery low — letting the Mac sleep", "Battery at \(b.percent)%. Session ended to protect the Mac.")
            stop(reason: "battery at \(b.percent)%")
        }
        if config.endOnCriticalHeat, PowerSafety.thermal == .critical {
            notify("Mac is too hot — letting it sleep", "Thermal state is critical. Session ended.")
            stop(reason: "critical heat")
        }
    }

    private func refreshAgents() {
        let ids = keepBundleIDs
        runningKeepAliveApps = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier).filter { ids.contains($0) })
        agentProcesses = AppFreezer.runningAgentProcesses(Set(config.keepAliveProcesses))
    }

    private func syncNetwork() {
        networkSummary = network.summary
        networkAction = network.lastAction
        networkOnline = network.isOnline || !engaged
        onHotspot = network.onHotspot
        persist()
    }

    // MARK: Settings side effects

    private func configChanged(from old: Config) {
        config.save()
        if old.keepAliveApps != config.keepAliveApps || old.disableAppNapForKeepAlive != config.disableAppNapForKeepAlive {
            applyAppNapPolicy()
            refreshAgents()
        }
        network.update(config: config)
        if engaged && lidClosed && !config.freezeOthersOnLidClose { restoreLidActions() }
    }

    /// Writes / removes `NSAppSleepDisabled` only for apps we manage.
    private func applyAppNapPolicy() {
        let want = config.disableAppNapForKeepAlive ? Set(config.keepAliveApps.map(\.bundleID)) : []
        let have = Set(config.appNapDisabledFor)
        for bid in want.subtracting(have) { AppNap.disable(for: bid) }
        for bid in have.subtracting(want) { AppNap.restore(for: bid) }
        if want != have { config.appNapDisabledFor = Array(want).sorted() }
    }

    func addApp(at url: URL) {
        guard let b = Bundle(url: url), let bid = b.bundleIdentifier else { return }
        let name = (b.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (b.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        addApp(KeepAliveApp(bundleID: bid, name: name, path: url.path))
    }

    func addApp(_ app: KeepAliveApp) {
        guard !config.keepAliveApps.contains(where: { $0.bundleID == app.bundleID }), app.bundleID != Paths.bundleID else { return }
        config.keepAliveApps.append(app)
        event("Keeping \(app.name) alive")
    }

    func removeApp(_ bundleID: String) {
        config.keepAliveApps.removeAll { $0.bundleID == bundleID }
    }

    func setupLidProof() {
        let r = SleepControl.installLidProofRule()
        lidProofReady = r.ok
        event(r.ok ? "Lid-proof mode enabled" : "Setup not completed: \(r.message)")
        if r.ok, engaged, !sleepDisabledByUs, !SleepControl.isSleepDisabled(), SleepControl.setSleepDisabled(true) {
            sleepDisabledByUs = true
            persist()
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch { event("Launch at login: \(error.localizedDescription)") }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func testFailover() {
        if !engaged { network.start(config: config) }
        network.joinHotspot(reason: "manual test")
    }

    func saveHotspot(ssid: String, password: String) -> Bool {
        let s = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        config.hotspotSSID = s
        guard !s.isEmpty else { return true }
        if password.isEmpty { return HotspotKeychain.read(ssid: s) != nil }
        let ok = HotspotKeychain.save(ssid: s, password: password)
        network.update(config: config)
        return ok
    }

    // MARK: Persistence & recovery

    private func persist() {
        let s = RuntimeState(appPid: getpid(), sleepDisabledByUs: sleepDisabledByUs,
                             frozenPids: freezer.pidList, frozenIdentities: freezer.identities,
                             engaged: engaged, engagedAt: startedAt,
                             until: { if case .until(let d) = mode { return d }; return nil }(),
                             lidClosed: lidClosed, network: networkSummary, mutedByUs: mutedByUs)
        s.save()
    }

    /// If a previous run crashed before the watchdog fired, undo its leftovers now.
    private func recoverFromPreviousRun() {
        guard let old = RuntimeState.load(), old.appPid != getpid() else { return }
        if !old.frozenIdentities.isEmpty { AppFreezer.resume(identities: old.frozenIdentities) }
        if old.mutedByUs { AudioMute.set(false) }
        if old.sleepDisabledByUs, SleepControl.isSleepDisabled() {
            if SleepControl.setSleepDisabled(false) { Log.info("recovered: re-enabled sleep left by a previous run") }
        }
        try? FileManager.default.removeItem(at: Paths.state)
    }

    private func seedDefaultsIfNeeded() {
        guard !config.seededDefaults else { return }
        for bid in Config.suggestedBundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bid) {
                let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
                config.keepAliveApps.append(KeepAliveApp(bundleID: bid, name: name, path: url.path))
            }
        }
        config.seededDefaults = true
    }

    // MARK: Commands (CLI) & signals

    private func handleCommand(_ cmd: String) {
        let parts = cmd.split(separator: ":").map(String.init)
        switch parts.first {
        case "on":
            if parts.count > 1, parts[1] == "auto" { start(.whileAgentsRun) }
            else { start(minutes: parts.count > 1 ? Int(parts[1]) ?? 0 : 0) }
        case "off": stop(reason: "command line")
        case "toggle": toggle()
        case "extend": extend(minutes: parts.count > 1 ? Int(parts[1]) ?? 30 : 30)
        default: break
        }
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            src.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.shutdown() }
                exit(0)
            }
            src.resume()
            signalSources.append(src)
        }
    }

    // MARK: Feedback

    private func event(_ s: String) {
        lastEvent = s
        Log.info(s)
    }

    func notify(_ title: String, _ body: String) {
        Log.info("notify: \(title) — \(body)")
        guard Bundle.main.bundleIdentifier != nil else { return }
        let c = UNMutableNotificationContent()
        c.title = title
        c.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
    }
}

import Foundation

/// Command-line control of the running menu bar app.
///
///     KeepMeAlive on            # until stopped
///     KeepMeAlive on 90         # 90 minutes   (also: 2h, 45m)
///     KeepMeAlive on auto       # while agents run
///     KeepMeAlive extend 30
///     KeepMeAlive off
///     KeepMeAlive status
enum CLI {
    static func runIfCommand(_ args: [String]) -> Int32? {
        guard let cmd = args.first, ["on", "off", "toggle", "extend", "status", "preview", "help", "--help"].contains(cmd) else {
            return nil
        }
        switch cmd {
        case "status": return status()
        case "preview": return preview()
        case "help", "--help": print(usage); return 0
        default: break
        }
        guard appIsRunning() else {
            FileHandle.standardError.write(Data("KeepMeAlive is not running. Open it first.\n".utf8))
            return 1
        }
        var payload = cmd
        if args.count > 1 {
            if args[1] == "auto" { payload += ":auto" }
            else if let m = minutes(args[1]) { payload += ":\(m)" }
            else { FileHandle.standardError.write(Data("Bad duration: \(args[1])\n".utf8)); return 2 }
        }
        DistributedNotificationCenter.default().postNotificationName(
            AwakeEngine.commandNotification, object: payload, userInfo: nil, deliverImmediately: true)
        Thread.sleep(forTimeInterval: 1.5)
        return status()
    }

    static func minutes(_ s: String) -> Int? {
        let t = s.lowercased()
        if t.hasSuffix("h"), let v = Double(t.dropLast()) { return Int(v * 60) }
        if t.hasSuffix("m"), let v = Int(t.dropLast()) { return v }
        return Int(t)
    }

    static func appIsRunning() -> Bool {
        guard let s = RuntimeState.load(), s.appPid > 0 else { return false }
        return kill(s.appPid, 0) == 0
    }

    static func status() -> Int32 {
        guard appIsRunning(), let s = RuntimeState.load() else { print("KeepMeAlive: not running"); return 1 }
        var parts = [s.engaged ? "AWAKE" : "idle"]
        if s.engaged {
            parts.append(s.sleepDisabledByUs ? "lid-proof" : "lid close will sleep")
            if let u = s.until { parts.append("until \(u.formatted(date: .omitted, time: .shortened))") }
        }
        parts.append("lid \(s.lidClosed ? "closed" : "open")")
        if !s.network.isEmpty { parts.append("net: \(s.network)") }
        let frozen = s.frozenPids.split(separator: " ").count
        if frozen > 0 { parts.append("\(frozen) processes paused") }
        print("KeepMeAlive: " + parts.joined(separator: " · "))
        return s.engaged ? 0 : 3
    }

    /// Dry run: what would be paused if the lid closed right now. Changes nothing.
    static func preview() -> Int32 {
        let cfg = Config.load()
        let keep = Set(cfg.keepAliveApps.map(\.bundleID))
        let plan = AppFreezer().plan(keepBundleIDs: keep, keepProcessNames: Set(cfg.keepAliveProcesses))
        print("Kept alive: " + (cfg.keepAliveApps.map(\.name) + cfg.keepAliveProcesses.map { "\($0) (cli)" }).joined(separator: ", "))
        if plan.isEmpty { print("Would pause: nothing"); return 0 }
        print("Would pause on lid close:")
        for (app, pids) in plan {
            print("  • \(app.localizedName ?? app.bundleIdentifier ?? "?")  (\(pids.count) process\(pids.count == 1 ? "" : "es"))")
        }
        return 0
    }

    static let usage = """
    usage: KeepMeAlive <command>
      on [minutes|2h|45m|auto]   start a session (auto = while agents run)
      extend [minutes]           add time to a timed session
      off                        end the session
      toggle                     start or end
      status                     print one status line (exit 0 when awake)
      preview                    list the apps a lid close would pause (changes nothing)
    """
}

import AppKit
import Darwin
import Foundation

/// A snapshot of the user's processes, built with libproc (no `ps` parsing).
struct ProcessTable {
    struct Entry {
        let pid: pid_t
        let ppid: pid_t
        let name: String
        let startMicros: UInt64
        var identity: String { "\(pid):\(startMicros)" }
    }

    let entries: [pid_t: Entry]
    let children: [pid_t: [pid_t]]

    static func snapshot() -> ProcessTable {
        let estimate = proc_listallpids(nil, 0)
        var pids = [pid_t](repeating: 0, count: Int(max(estimate, 0)) + 256)
        let n = pids.withUnsafeMutableBufferPointer { buf in
            proc_listallpids(buf.baseAddress, Int32(buf.count * MemoryLayout<pid_t>.size))
        }
        var entries: [pid_t: Entry] = [:]
        var children: [pid_t: [pid_t]] = [:]
        for pid in pids.prefix(Int(max(n, 0))) where pid > 0 {
            guard let e = info(pid) else { continue }
            entries[pid] = e
            children[e.ppid, default: []].append(pid)
        }
        return ProcessTable(entries: entries, children: children)
    }

    static func info(_ pid: pid_t) -> Entry? {
        var bsd = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsd, size) == size else { return nil }
        let name: String = withUnsafePointer(to: &bsd.pbi_name) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(2 * MAXCOMLEN)) { String(cString: $0) }
        }
        let comm: String = withUnsafePointer(to: &bsd.pbi_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) { String(cString: $0) }
        }
        return Entry(pid: pid, ppid: pid_t(bsd.pbi_ppid), name: name.isEmpty ? comm : name,
                     startMicros: UInt64(bsd.pbi_start_tvsec) * 1_000_000 + UInt64(bsd.pbi_start_tvusec))
    }

    func descendants(of pid: pid_t) -> [pid_t] {
        var out: [pid_t] = []
        var stack = children[pid] ?? []
        var seen = Set<pid_t>()
        while let p = stack.popLast() {
            guard seen.insert(p).inserted else { continue }
            out.append(p)
            stack.append(contentsOf: children[p] ?? [])
        }
        return out
    }

    func ancestors(of pid: pid_t) -> [pid_t] {
        var out: [pid_t] = []
        var cur = entries[pid]?.ppid ?? 0
        while cur > 1, let e = entries[cur], !out.contains(cur) {
            out.append(cur)
            cur = e.ppid
        }
        return out
    }
}

/// Pauses ("puts to sleep") every app that is not on the keep-alive list while the lid is
/// closed, using SIGSTOP/SIGCONT. Paused apps use no CPU and no network, but keep all
/// their state, so they resume exactly where they were when the lid opens.
final class AppFreezer {
    struct Frozen: Hashable { let pid: pid_t; let startMicros: UInt64; let label: String }

    private(set) var frozen: [Frozen] = []

    /// Never paused, whatever the settings say: the OS shell, input, accessibility,
    /// password managers, and meeting / recording apps (pausing them drops the call).
    static let protectedBundleIDs: Set<String> = [
        Paths.bundleID,
        "com.apple.finder", "com.apple.dock", "com.apple.loginwindow", "com.apple.systemuiserver",
        "com.apple.controlcenter", "com.apple.notificationcenterui", "com.apple.Spotlight",
        "com.apple.WindowManager", "com.apple.ActivityMonitor", "com.apple.systempreferences",
        "com.apple.SecurityAgent", "com.apple.FaceTime", "com.apple.VoiceOver",
        "com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.cisco.webexmeetingsapp",
        "Cisco-Systems.Spark", "com.webex.meetingmanager", "com.obsproject.obs-studio", "com.loom.desktop",
        // VPN / device management: pausing these can drop the corporate tunnel agents depend on.
        "com.cisco.secureclient.gui", "com.cisco.anyconnect.gui", "com.paloaltonetworks.GlobalProtect.client",
        "io.tailscale.ipn.macos", "io.tailscale.ipn.macsys", "com.wireguard.macos", "net.openvpn.connect.app",
        "com.cloudflare.1dot1dot1dot1.macos", "com.zscaler.zscaler", "com.jamfsoftware.selfservice.mac",
        // Dictation
        "com.electron.wispr-flow",
    ]

    /// Decides what to pause. Kept: keep-alive apps, agent CLI processes, everything they
    /// spawned, and everything they run inside (e.g. the terminal hosting `codex`).
    func plan(keepBundleIDs: Set<String>, keepProcessNames: Set<String>) -> [(NSRunningApplication, [pid_t])] {
        let table = ProcessTable.snapshot()
        let me = getpid()

        var protected = Set<pid_t>([me])
        let apps = NSWorkspace.shared.runningApplications

        var keepRoots: [pid_t] = []
        for app in apps {
            let bid = app.bundleIdentifier ?? ""
            if keepBundleIDs.contains(bid) || Self.protectedBundleIDs.contains(bid) { keepRoots.append(app.processIdentifier) }
        }
        let lowerNames = Set(keepProcessNames.map { $0.lowercased() })
        for e in table.entries.values where lowerNames.contains(e.name.lowercased()) { keepRoots.append(e.pid) }

        for root in keepRoots {
            protected.insert(root)
            protected.formUnion(table.descendants(of: root))
            protected.formUnion(table.ancestors(of: root))
        }

        let alreadyFrozen = Set(frozen.map(\.pid))
        var result: [(NSRunningApplication, [pid_t])] = []
        for app in apps where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard pid > 0, !protected.contains(pid), app.bundleIdentifier != nil else { continue }
            let tree = ([pid] + table.descendants(of: pid)).filter { !protected.contains($0) && !alreadyFrozen.contains($0) }
            if !tree.isEmpty { result.append((app, tree)) }
        }
        return result
    }

    /// Pauses everything `plan` returns. Returns the names of apps paused.
    @discardableResult
    func freeze(keepBundleIDs: Set<String>, keepProcessNames: Set<String>) -> [String] {
        var names: [String] = []
        for (app, pids) in plan(keepBundleIDs: keepBundleIDs, keepProcessNames: keepProcessNames) {
            let label = app.localizedName ?? app.bundleIdentifier ?? "pid \(app.processIdentifier)"
            var any = false
            for pid in pids {
                guard let e = ProcessTable.info(pid) else { continue }
                if kill(pid, SIGSTOP) == 0 {
                    frozen.append(Frozen(pid: pid, startMicros: e.startMicros, label: label))
                    any = true
                }
            }
            if any { names.append(label) }
        }
        if !names.isEmpty { Log.info("paused: \(names.joined(separator: ", "))") }
        return names
    }

    /// Resumes everything we paused. Only resumes a pid whose start time still matches,
    /// so a recycled pid belonging to something else is never touched.
    func resumeAll() {
        guard !frozen.isEmpty else { return }
        var labels = Set<String>()
        for f in frozen {
            if let e = ProcessTable.info(f.pid), e.startMicros == f.startMicros {
                kill(f.pid, SIGCONT)
                labels.insert(f.label)
            }
        }
        Log.info("resumed: \(labels.sorted().joined(separator: ", "))")
        frozen.removeAll()
    }

    /// Resumes pids recorded by a previous run that crashed (from `RuntimeState`).
    static func resume(identities: [String]) {
        for id in identities {
            let parts = id.split(separator: ":")
            guard parts.count == 2, let pid = pid_t(parts[0]), let start = UInt64(parts[1]) else { continue }
            if let e = ProcessTable.info(pid), e.startMicros == start { kill(pid, SIGCONT) }
        }
    }

    var frozenAppNames: [String] { Array(Set(frozen.map(\.label))).sorted() }
    var pidList: String { frozen.map { String($0.pid) }.joined(separator: " ") }
    var identities: [String] { frozen.map { "\($0.pid):\($0.startMicros)" } }

    /// Is any keep-alive app or agent process running right now? Drives "while agents run" mode.
    static func anyKeepAliveRunning(keepBundleIDs: Set<String>, keepProcessNames: Set<String>) -> Bool {
        if NSWorkspace.shared.runningApplications.contains(where: { keepBundleIDs.contains($0.bundleIdentifier ?? "") }) {
            return true
        }
        let names = Set(keepProcessNames.map { $0.lowercased() })
        return ProcessTable.snapshot().entries.values.contains { names.contains($0.name.lowercased()) }
    }

    /// Agent CLI processes currently running (for the status panel).
    static func runningAgentProcesses(_ keepProcessNames: Set<String>) -> [String] {
        let names = Set(keepProcessNames.map { $0.lowercased() })
        var counts: [String: Int] = [:]
        for e in ProcessTable.snapshot().entries.values where names.contains(e.name.lowercased()) {
            counts[e.name.lowercased(), default: 0] += 1
        }
        return counts.keys.sorted().map { counts[$0]! > 1 ? "\($0) ×\(counts[$0]!)" : $0 }
    }
}

/// App Nap can still throttle a kept app's timers with the lid closed. AppKit apps honour
/// `NSAppSleepDisabled` in their own defaults domain (takes effect at their next launch).
enum AppNap {
    static func disable(for bundleID: String) {
        Shell.run("/usr/bin/defaults", ["write", bundleID, "NSAppSleepDisabled", "-bool", "YES"])
    }

    static func restore(for bundleID: String) {
        Shell.run("/usr/bin/defaults", ["delete", bundleID, "NSAppSleepDisabled"])
    }
}

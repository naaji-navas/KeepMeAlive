import Foundation

/// Installs a per-user LaunchAgent that undoes KeepMeAlive's system changes if the app dies.
enum Watchdog {
    static let label = "com.keepmealive.watchdog"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path) && FileManager.default.fileExists(atPath: Paths.watchdogScript.path)
    }

    /// Idempotent. Copies the script out of the bundle (so moving the app never breaks it).
    static func install() {
        guard let bundled = Bundle.main.url(forResource: "watchdog", withExtension: "sh"),
              let script = try? Data(contentsOf: bundled) else {
            Log.warn("watchdog.sh not in bundle; running unbundled?")
            return
        }
        let fm = FileManager.default
        let existing = try? Data(contentsOf: Paths.watchdogScript)
        if existing != script {
            try? script.write(to: Paths.watchdogScript, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Paths.watchdogScript.path)
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/sh", Paths.watchdogScript.path],
            "StartInterval": 60,
            "RunAtLoad": true,
            "ProcessType": "Background",
            "StandardErrorPath": Paths.logs.appendingPathComponent("watchdog.err").path,
        ]
        let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        let current = try? Data(contentsOf: plistURL)
        let domain = "gui/\(getuid())"
        if current != data {
            try? fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            Shell.run("/bin/launchctl", ["bootout", domain, plistURL.path])
            try? data?.write(to: plistURL, options: .atomic)
            Shell.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
            Log.info("watchdog LaunchAgent installed")
        } else if Shell.run("/bin/launchctl", ["print", "\(domain)/\(label)"]).status != 0 {
            Shell.run("/bin/launchctl", ["bootstrap", domain, plistURL.path])
        }
    }

    static func uninstall() {
        Shell.run("/bin/launchctl", ["bootout", "gui/\(getuid())", plistURL.path])
        try? FileManager.default.removeItem(at: plistURL)
        try? FileManager.default.removeItem(at: Paths.watchdogScript)
    }
}

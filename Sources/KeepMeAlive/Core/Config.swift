import Foundation

/// An app the user wants kept running while the lid is closed.
struct KeepAliveApp: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var path: String?
    var id: String { bundleID }
}

/// How a session decides when to stay awake.
enum SessionMode: Codable, Hashable {
    /// Until the user turns it off.
    case indefinite
    /// Until a fixed time.
    case until(Date)
    /// Only while at least one keep-alive app or agent process is running.
    case whileAgentsRun
}

struct Config: Codable, Equatable {
    // Apps & processes
    var keepAliveApps: [KeepAliveApp] = []
    /// Command-line agents matched by process name (e.g. `codex` in a terminal tab).
    /// A matching process — and every app it runs inside — is never frozen.
    var keepAliveProcesses: [String] = ["codex", "claude", "cursor-agent", "aider", "gemini", "opencode", "amp"]
    var freezeOthersOnLidClose = true
    var disableAppNapForKeepAlive = true
    /// Bundle IDs we wrote `NSAppSleepDisabled` for, so we only undo our own changes.
    var appNapDisabledFor: [String] = []

    // Lid
    var sleepDisplayOnLidClose = true
    var muteOnLidClose = false

    // Safety
    var batteryFloorPercent = 10
    var endOnCriticalHeat = true

    // Network
    var failoverEnabled = true
    var hotspotSSID = ""
    var failoverGraceSeconds = 20
    var returnToPrimaryWiFi = true

    // Session defaults
    var lastDurationMinutes = 0 // 0 = indefinite

    var seededDefaults = false

    init() {}

    // Tolerant decoding: missing keys fall back to defaults, so new settings never break old files.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        keepAliveApps = (try? c.decodeIfPresent([KeepAliveApp].self, forKey: .keepAliveApps)) ?? d.keepAliveApps
        keepAliveProcesses = (try? c.decodeIfPresent([String].self, forKey: .keepAliveProcesses)) ?? d.keepAliveProcesses
        freezeOthersOnLidClose = (try? c.decodeIfPresent(Bool.self, forKey: .freezeOthersOnLidClose)) ?? d.freezeOthersOnLidClose
        disableAppNapForKeepAlive = (try? c.decodeIfPresent(Bool.self, forKey: .disableAppNapForKeepAlive)) ?? d.disableAppNapForKeepAlive
        appNapDisabledFor = (try? c.decodeIfPresent([String].self, forKey: .appNapDisabledFor)) ?? d.appNapDisabledFor
        sleepDisplayOnLidClose = (try? c.decodeIfPresent(Bool.self, forKey: .sleepDisplayOnLidClose)) ?? d.sleepDisplayOnLidClose
        muteOnLidClose = (try? c.decodeIfPresent(Bool.self, forKey: .muteOnLidClose)) ?? d.muteOnLidClose
        batteryFloorPercent = (try? c.decodeIfPresent(Int.self, forKey: .batteryFloorPercent)) ?? d.batteryFloorPercent
        endOnCriticalHeat = (try? c.decodeIfPresent(Bool.self, forKey: .endOnCriticalHeat)) ?? d.endOnCriticalHeat
        failoverEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .failoverEnabled)) ?? d.failoverEnabled
        hotspotSSID = (try? c.decodeIfPresent(String.self, forKey: .hotspotSSID)) ?? d.hotspotSSID
        failoverGraceSeconds = (try? c.decodeIfPresent(Int.self, forKey: .failoverGraceSeconds)) ?? d.failoverGraceSeconds
        returnToPrimaryWiFi = (try? c.decodeIfPresent(Bool.self, forKey: .returnToPrimaryWiFi)) ?? d.returnToPrimaryWiFi
        lastDurationMinutes = (try? c.decodeIfPresent(Int.self, forKey: .lastDurationMinutes)) ?? d.lastDurationMinutes
        seededDefaults = (try? c.decodeIfPresent(Bool.self, forKey: .seededDefaults)) ?? d.seededDefaults
    }

    static func load() -> Config {
        guard let data = try? Data(contentsOf: Paths.config),
              let cfg = try? JSONDecoder().decode(Config.self, from: data) else { return Config() }
        return cfg
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self) else { return }
        try? data.write(to: Paths.config, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.config.path)
    }

    /// Well-known agent hosts. On first launch, the ones installed on this Mac become the keep-alive list.
    static let suggestedBundleIDs: [String] = [
        "com.anthropic.claudefordesktop",   // Claude (incl. Claude Code desktop)
        "com.openai.codex",                 // Codex
        "com.openai.chat",                  // ChatGPT
        "com.todesktop.230313mzl4w4u92",    // Cursor
        "com.exafunction.windsurf",         // Windsurf
        "com.microsoft.VSCode",             // VS Code
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "dev.zed.Zed",
    ]
}

/// Crash-safe record of what KeepMeAlive changed on the system. Read by the watchdog
/// (`watchdog.sh`) with `plutil`, so keep the field names flat and simple.
struct RuntimeState: Codable {
    var appPid: Int32
    var sleepDisabledByUs: Bool
    /// Space-separated pids we SIGSTOPped (easy for the shell watchdog to read).
    var frozenPids: String
    /// "pid:startMicros" pairs used by the app to avoid resuming a recycled pid.
    var frozenIdentities: [String]
    var engaged: Bool
    var engagedAt: Date?
    var until: Date?
    var lidClosed: Bool
    var network: String
    var mutedByUs: Bool

    static let empty = RuntimeState(appPid: 0, sleepDisabledByUs: false, frozenPids: "", frozenIdentities: [],
                                    engaged: false, engagedAt: nil, until: nil, lidClosed: false,
                                    network: "", mutedByUs: false)

    static func load() -> RuntimeState? {
        guard let data = try? Data(contentsOf: Paths.state) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(RuntimeState.self, from: data)
    }

    func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(self) else { return }
        try? data.write(to: Paths.state, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Paths.state.path)
    }
}

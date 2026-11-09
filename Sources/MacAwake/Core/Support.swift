import Foundation
import os

/// Filesystem locations used by MacAwake. Everything is per-user and owner-only.
enum Paths {
    static let appName = "MacAwake"
    static let bundleID = "com.macawake.app"

    static var support: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(appName, isDirectory: true)
        ensureDir(url)
        return url
    }

    static var logs: URL {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(appName)", isDirectory: true)
        ensureDir(url)
        return url
    }

    static var config: URL { support.appendingPathComponent("config.json") }
    static var state: URL { support.appendingPathComponent("state.json") }
    static var watchdogScript: URL { support.appendingPathComponent("watchdog.sh") }
    static var logFile: URL { logs.appendingPathComponent("macawake.log") }

    private static func ensureDir(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
    }
}

/// Tiny logger: unified log + a capped file in ~/Library/Logs/MacAwake.
enum Log {
    private static let logger = Logger(subsystem: Paths.bundleID, category: "core")
    private static let queue = DispatchQueue(label: "macawake.log")
    private static let maxBytes = 1_000_000

    static func info(_ msg: String) { write("INFO", msg); logger.info("\(msg, privacy: .private)") }
    static func warn(_ msg: String) { write("WARN", msg); logger.warning("\(msg, privacy: .private)") }
    static func error(_ msg: String) { write("ERROR", msg); logger.error("\(msg, privacy: .private)") }

    private static func write(_ level: String, _ msg: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) [\(level)] \(msg)\n"
        queue.async {
            let url = Paths.logFile
            let fm = FileManager.default
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > maxBytes {
                let old = url.appendingPathExtension("1")
                try? fm.removeItem(at: old)
                try? fm.moveItem(at: url, to: old)
            }
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(Data(line.utf8))
                try? h.close()
            }
        }
    }
}

/// Runs a command synchronously, never through a shell, with a hard timeout.
enum Shell {
    struct Result { let status: Int32; let out: String; let err: String }

    @discardableResult
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 10) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch {
            return Result(status: -1, out: "", err: "\(error)")
        }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate(); return Result(status: -2, out: "", err: "timed out") }
        let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Result(status: p.terminationStatus, out: o, err: e)
    }
}

extension TimeInterval {
    /// "2h 05m", "45m", "30s"
    var shortDuration: String {
        let s = Int(self.rounded())
        if s >= 3600 { return String(format: "%dh %02dm", s / 3600, (s % 3600) / 60) }
        if s >= 60 { return "\(s / 60)m" }
        return "\(max(s, 0))s"
    }
}

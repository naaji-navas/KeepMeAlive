import AppKit
import Foundation
import IOKit
import IOKit.pwr_mgt

/// Lid-proof sleep prevention.
///
/// macOS ignores ordinary power assertions when a MacBook's lid closes on battery
/// (clamshell sleep). The only supported switch that survives a lid close is
/// `pmset -a disablesleep 1`, which needs root. KeepMeAlive gets that through a
/// narrow sudoers rule allowing exactly two commands, installed once by the user.
///
/// An IOKit assertion is also held, so idle sleep is blocked even before setup.
enum SleepControl {
    static let pmset = "/usr/bin/pmset"
    static let sudoersPath = "/etc/sudoers.d/keepmealive"

    // MARK: Privileged (lid-proof)

    /// True when the sudoers rule lets us flip `disablesleep` without a password.
    static func isLidProofAuthorized() -> Bool {
        Shell.run("/usr/bin/sudo", ["-n", "-l", pmset, "-a", "disablesleep", "1"], timeout: 5).status == 0
    }

    /// Reads `SleepDisabled` from `pmset -g`. macOS omits the line when it is 0.
    static func isSleepDisabled() -> Bool {
        let r = Shell.run(pmset, ["-g"], timeout: 5)
        for line in r.out.split(separator: "\n") where line.contains("SleepDisabled") {
            // pmset separates key and value with tabs, so split on any whitespace.
            return line.split(whereSeparator: { $0.isWhitespace }).last == "1"
        }
        return false
    }

    @discardableResult
    static func setSleepDisabled(_ disabled: Bool) -> Bool {
        let r = Shell.run("/usr/bin/sudo", ["-n", pmset, "-a", "disablesleep", disabled ? "1" : "0"], timeout: 10)
        if r.status != 0 {
            Log.error("pmset disablesleep \(disabled ? 1 : 0) failed (\(r.status)): \(r.err)")
            return false
        }
        // The command succeeded, so we own this change and must undo it later, whatever
        // the read-back says. A mismatch only means another tool may be fighting us.
        let readBack = isSleepDisabled()
        if readBack != disabled { Log.warn("pmset read-back mismatch: wanted \(disabled), got \(readBack)") }
        Log.info("pmset disablesleep \(disabled ? 1 : 0)")
        return true
    }

    /// Installs the sudoers rule through the standard macOS admin prompt.
    /// The rule allows only `pmset -a disablesleep 0|1` for the current user.
    static func installLidProofRule() -> (ok: Bool, message: String) {
        let user = NSUserName()
        guard user.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
            return (false, "Unsupported user name")
        }
        let rule = """
        # Installed by KeepMeAlive. Lets \(user) toggle lid-proof sleep prevention without a password.
        \(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0

        """
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("keepmealive-sudoers-\(UUID().uuidString)")
        do { try rule.write(to: tmp, atomically: true, encoding: .utf8) } catch {
            return (false, "Could not write temp file: \(error.localizedDescription)")
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        let t = tmp.path.replacingOccurrences(of: "'", with: "")
        let cmd = "/usr/sbin/visudo -cf '\(t)' && /usr/bin/install -m 0440 -o root -g wheel '\(t)' \(sudoersPath)"
        let script = "do shell script \"\(cmd)\" with administrator privileges with prompt \"KeepMeAlive needs your password once so it can keep your Mac awake with the lid closed.\""
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if let err {
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "Cancelled"
            Log.warn("sudoers install failed: \(msg)")
            return (false, msg)
        }
        Log.info("sudoers rule installed at \(sudoersPath)")
        return (isLidProofAuthorized(), "Installed")
    }

    // MARK: Assertions (idle sleep, no root needed)

    private static var assertionID: IOPMAssertionID = 0

    static func holdIdleAssertion(_ hold: Bool) {
        if hold, assertionID == 0 {
            var id: IOPMAssertionID = 0
            let r = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                "KeepMeAlive keeps agent sessions alive" as CFString, &id)
            if r == kIOReturnSuccess { assertionID = id }
        } else if !hold, assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }

    // MARK: Display

    /// Puts displays to sleep without sleeping the system (no root needed).
    static func sleepDisplaysNow() {
        Shell.run(pmset, ["displaysleepnow"], timeout: 5)
    }

    static func anyDisplayAwake() -> Bool {
        var count: UInt32 = 0
        CGGetOnlineDisplayList(0, nil, &count)
        guard count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetOnlineDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).contains { CGDisplayIsAsleep($0) == 0 }
    }
}

/// Reads the MacBook lid from the power-management root domain.
enum Lid {
    /// nil on Macs without a lid.
    static func isClosed() -> Bool? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let prop = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString,
                                                         kCFAllocatorDefault, 0)?.takeRetainedValue() else { return nil }
        return (prop as? Bool) ?? ((prop as? NSNumber)?.boolValue)
    }
}

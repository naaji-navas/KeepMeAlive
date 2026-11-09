import Foundation
import IOKit.ps

/// Battery and heat readings used by the safety rules.
enum PowerSafety {
    struct Battery { let percent: Int; let onAC: Bool; let charging: Bool }

    static func battery() -> Battery? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any],
                  (d[kIOPSTypeKey] as? String) == kIOPSInternalBatteryType else { continue }
            let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = d[kIOPSMaxCapacityKey] as? Int ?? 100
            let onAC = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let charging = d[kIOPSIsChargingKey] as? Bool ?? false
            return Battery(percent: max > 0 ? cur * 100 / max : cur, onAC: onAC, charging: charging)
        }
        return nil
    }

    static var thermal: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }
}

/// Output mute through AppleScript's standard volume command (no private APIs).
enum AudioMute {
    static func isMuted() -> Bool {
        Shell.run("/usr/bin/osascript", ["-e", "output muted of (get volume settings)"], timeout: 5)
            .out.trimmingCharacters(in: .whitespacesAndNewlines) == "true"
    }

    static func set(_ muted: Bool) {
        Shell.run("/usr/bin/osascript", ["-e", "set volume output muted \(muted)"], timeout: 5)
    }
}

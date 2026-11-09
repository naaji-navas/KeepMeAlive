import CoreLocation
import CoreWLAN
import Foundation
import Network
import Security

/// Hotspot password storage in the login Keychain.
enum HotspotKeychain {
    static let service = "com.keepmealive.hotspot"

    static func save(ssid: String, password: String) -> Bool {
        delete(ssid: ssid)
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
            kSecValueData as String: Data(password.utf8),
            kSecAttrLabel as String: "KeepMeAlive hotspot (\(ssid))",
        ]
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func read(ssid: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(ssid: String) -> Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service, kSecAttrAccount as String: ssid]
        return SecItemDelete(q as CFDictionary) == errSecSuccess
    }
}

/// macOS hides Wi-Fi network names from apps without Location Services access.
/// KeepMeAlive never reads your location; it only needs the permission to see SSIDs.
final class LocationGate: NSObject, CLLocationManagerDelegate {
    static let shared = LocationGate()
    private let manager = CLLocationManager()
    var onChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }
    var isAuthorized: Bool { status == .authorizedAlways || status == .authorized }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { onChange?() }
}

/// Keeps the Mac online while a session runs.
///
/// - Probes real reachability (not just "an interface is up") every few seconds.
/// - If Wi-Fi is switched off, switches it back on.
/// - After a grace period offline, joins your phone's Personal Hotspot (mobile data).
/// - When your normal Wi-Fi is back in range, moves back to it to save mobile data.
@MainActor
final class NetworkGuardian {
    enum Link: Equatable {
        case unknown
        case online(String)
        case offline(since: Date)
    }

    private(set) var link: Link = .unknown
    private(set) var onHotspot = false
    private(set) var lastAction = ""
    var onUpdate: (() -> Void)?
    var notify: ((String, String) -> Void)?

    private var config = Config()
    private var hotspotPassword: String?
    private var primarySSID: String?
    private var pathMonitor: NWPathMonitor?
    private var timer: Timer?
    private var probing = false
    private var lastJoinAttempt = Date.distantPast
    private var lastReturnCheck = Date.distantPast
    private var running = false

    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 6
        c.timeoutIntervalForResource = 8
        c.waitsForConnectivity = false
        c.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: c)
    }()

    private var wifi: CWInterface? { CWWiFiClient.shared().interface() }

    /// Call while the user is present (lid open): reads the Keychain once so no prompt can
    /// ever block a failover later with the lid closed.
    func start(config: Config) {
        self.config = config
        if !config.hotspotSSID.isEmpty { hotspotPassword = HotspotKeychain.read(ssid: config.hotspotSSID) }
        rememberPrimary()
        guard !running else { return }
        running = true
        let m = NWPathMonitor()
        m.pathUpdateHandler = { [weak self] _ in Task { @MainActor in self?.check() } }
        m.start(queue: .global(qos: .utility))
        pathMonitor = m
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        check()
        Log.info("network guardian started (hotspot: \(config.hotspotSSID.isEmpty ? "not set" : config.hotspotSSID))")
    }

    func update(config: Config) {
        let ssidChanged = config.hotspotSSID != self.config.hotspotSSID
        self.config = config
        if ssidChanged || hotspotPassword == nil, !config.hotspotSSID.isEmpty {
            hotspotPassword = HotspotKeychain.read(ssid: config.hotspotSSID)
        }
    }

    func stop() {
        running = false
        pathMonitor?.cancel(); pathMonitor = nil
        timer?.invalidate(); timer = nil
        link = .unknown
        onUpdate?()
    }

    var summary: String {
        switch link {
        case .unknown: return "Checking…"
        case .online(let via): return via
        case .offline(let since): return "Offline \(Date().timeIntervalSince(since).shortDuration)"
        }
    }

    var isOnline: Bool { if case .online = link { return true } else { return false } }

    // MARK: Loop

    private func check() {
        guard running, !probing else { return }
        probing = true
        Task {
            let ok = await probe()
            probing = false
            handle(online: ok)
        }
    }

    private func handle(online: Bool) {
        guard running else { return }
        onHotspot = detectHotspot()
        if online {
            if case .offline = link { notifyOnce("Back online", "Connected via \(describeRoute()).") }
            link = .online(describeRoute())
            if !onHotspot { rememberPrimary() }
            maybeReturnToPrimary()
        } else {
            let since: Date
            if case .offline(let s) = link { since = s } else { since = Date(); Log.warn("internet unreachable") }
            link = .offline(since: since)
            recover(offlineFor: Date().timeIntervalSince(since))
        }
        onUpdate?()
    }

    private func recover(offlineFor: TimeInterval) {
        guard config.failoverEnabled, let iface = wifi else { return }
        if !iface.powerOn() {
            do { try iface.setPower(true); act("Turned Wi-Fi back on") } catch { act("Could not turn Wi-Fi on: \(error.localizedDescription)") }
            return
        }
        guard offlineFor >= TimeInterval(config.failoverGraceSeconds) else { return }
        guard Date().timeIntervalSince(lastJoinAttempt) > 30 else { return }
        lastJoinAttempt = Date()
        if onHotspot { act("Offline on hotspot — check the phone's signal") ; return }
        joinHotspot(reason: "internet down for \(Int(offlineFor))s")
    }

    /// Joins the configured hotspot. Also used by "Test failover now".
    func joinHotspot(reason: String) {
        let ssid = config.hotspotSSID
        guard !ssid.isEmpty else { act("No hotspot configured"); return }
        guard let password = hotspotPassword ?? HotspotKeychain.read(ssid: ssid) else {
            act("Hotspot password missing — set it in Settings"); return
        }
        hotspotPassword = password
        act("Joining \(ssid) (\(reason))…")
        let ifName = wifi?.interfaceName
        Task.detached(priority: .userInitiated) {
            let result = Self.associate(interfaceName: ifName, ssid: ssid, password: password)
            await MainActor.run {
                switch result {
                case .success:
                    self.onHotspot = true
                    self.act("Joined \(ssid)")
                    self.notifyOnce("Switched to mobile data", "Wi-Fi dropped, so KeepMeAlive joined \(ssid).")
                case .failure(let e):
                    self.act("Hotspot join failed: \(e.message)")
                }
                self.check()
            }
        }
    }

    private nonisolated static func associate(interfaceName: String?, ssid: String, password: String?) -> Result<Void, JoinFailure> {
        let client = CWWiFiClient.shared()
        guard let iface = interfaceName.flatMap({ client.interface(withName: $0) }) ?? client.interface() else {
            return .failure(JoinFailure("no Wi-Fi interface"))
        }
        do {
            // Scanning a specific SSID also prompts an iPhone's Instant Hotspot to wake up.
            var networks: Set<CWNetwork> = []
            for attempt in 0..<3 {
                networks = try iface.scanForNetworks(withSSID: ssid.data(using: .utf8))
                if !networks.isEmpty { break }
                Thread.sleep(forTimeInterval: Double(2 + attempt * 2))
            }
            guard let net = networks.max(by: { $0.rssiValue < $1.rssiValue }) else {
                return .failure(JoinFailure("\(ssid) not in range (is Personal Hotspot on?)"))
            }
            try iface.associate(to: net, password: password)
            return .success(())
        } catch {
            return .failure(JoinFailure(error.localizedDescription))
        }
    }

    /// While on the hotspot, periodically look for the normal Wi-Fi and move back to it.
    private func maybeReturnToPrimary() {
        guard config.returnToPrimaryWiFi, onHotspot, let primary = primarySSID,
              primary != config.hotspotSSID, Date().timeIntervalSince(lastReturnCheck) > 120 else { return }
        lastReturnCheck = Date()
        let ifName = wifi?.interfaceName
        let hotspot = config.hotspotSSID
        let hotspotPassword = self.hotspotPassword
        Task.detached(priority: .utility) {
            let client = CWWiFiClient.shared()
            guard let iface = ifName.flatMap({ client.interface(withName: $0) }),
                  let nets = try? iface.scanForNetworks(withSSID: primary.data(using: .utf8)),
                  let best = nets.max(by: { $0.rssiValue < $1.rssiValue }), best.rssiValue > -75 else { return }
            // Known networks: CoreWLAN uses the saved system credentials when password is nil.
            let moved = (try? iface.associate(to: best, password: nil)) != nil
            try? await Task.sleep(for: .seconds(8))
            let ok = await self.probe()
            if !ok || !moved {
                _ = Self.associate(interfaceName: ifName, ssid: hotspot, password: hotspotPassword)
            }
            await MainActor.run {
                if ok && moved {
                    self.onHotspot = false
                    self.act("Back on \(primary) — hotspot released")
                    self.notifyOnce("Back on Wi-Fi", "Moved from the hotspot back to \(primary).")
                } else {
                    self.act("\(primary) seen but not usable yet; staying on hotspot")
                }
                self.check()
            }
        }
    }

    // MARK: Probing

    /// Real internet check: two independent endpoints, either one passing counts.
    nonisolated func probe() async -> Bool {
        async let a = fetch("http://captive.apple.com/hotspot-detect.html", expect: "Success")
        async let b = fetch("https://www.cloudflare.com/cdn-cgi/trace", expect: "h=")
        let (ra, rb) = await (a, b)
        return ra || rb
    }

    private nonisolated func fetch(_ url: String, expect: String) async -> Bool {
        guard let u = URL(string: url) else { return false }
        var req = URLRequest(url: u)
        req.setValue("KeepMeAlive/1.0", forHTTPHeaderField: "User-Agent")
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return String(decoding: data, as: UTF8.self).contains(expect)
    }

    // MARK: Helpers

    private func currentSSID() -> String? { wifi?.ssid() }

    private func rememberPrimary() {
        if let s = currentSSID(), !s.isEmpty, s != config.hotspotSSID { primarySSID = s }
    }

    /// iPhone Personal Hotspot always hands out 172.20.10.x; SSID match needs Location access.
    private func detectHotspot() -> Bool {
        if let s = currentSSID(), !config.hotspotSSID.isEmpty { return s == config.hotspotSSID }
        guard let name = wifi?.interfaceName, let ip = Self.ipv4(of: name) else { return onHotspot }
        return ip.hasPrefix("172.20.10.")
    }

    private func describeRoute() -> String {
        if onHotspot { return "Hotspot \(config.hotspotSSID.isEmpty ? "" : config.hotspotSSID)".trimmingCharacters(in: .whitespaces) }
        if let s = currentSSID() { return "Wi-Fi · \(s)" }
        if let name = wifi?.interfaceName, Self.ipv4(of: name) != nil { return "Wi-Fi" }
        return "Ethernet / other"
    }

    static func ipv4(of interface: String) -> String? {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return nil }
        defer { freeifaddrs(ifap) }
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let a = p.pointee
            guard String(cString: a.ifa_name) == interface, a.ifa_addr?.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(a.ifa_addr, socklen_t(a.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    private func act(_ s: String) {
        lastAction = s
        Log.info("network: \(s)")
        onUpdate?()
    }

    private var lastNotice = ""
    private func notifyOnce(_ title: String, _ body: String) {
        guard lastNotice != title + body else { return }
        lastNotice = title + body
        notify?(title, body)
    }
}

struct JoinFailure: Error, CustomStringConvertible {
    let message: String
    init(_ m: String) { message = m }
    var description: String { message }
}

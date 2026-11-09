import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarLabel: View {
    let engine: AwakeEngine

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            if let r = engine.remaining { Text(r.shortDuration).monospacedDigit() }
        }
    }

    private var icon: String {
        if !engine.engaged { return engine.active ? "moon.haze" : "moon.zzz" }
        if !engine.networkOnline { return "wifi.exclamationmark" }
        return engine.lidClosed ? "laptopcomputer" : "sun.max.fill"
    }
}

/// The popover that opens from the menu bar.
struct MenuPanel: View {
    @Environment(AwakeEngine.self) private var engine
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !engine.lidProofReady { setupCard }
            durationPicker
            statusCard
            keepAliveSection
            if !engine.lastEvent.isEmpty {
                Text(engine.lastEvent).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 360)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle().fill(engine.engaged ? Color.orange.gradient : Color.secondary.opacity(0.18).gradient)
                Image(systemName: engine.engaged ? "sun.max.fill" : "moon.zzz.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(engine.engaged ? .white : .secondary)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text("MacAwake").font(.headline)
                Text(headline).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { engine.active }, set: { $0 ? engine.start(minutes: engine.config.lastDurationMinutes) : engine.stop() }))
                .toggleStyle(.switch)
                .controlSize(.large)
                .labelsHidden()
        }
    }

    private var headline: String {
        if !engine.active { return "Sleep allowed" }
        if !engine.engaged { return "Waiting for an agent to start" }
        if let r = engine.remaining { return "Awake · \(r.shortDuration) left" }
        return "Awake \(engine.modeDescription)"
    }

    // MARK: Setup

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Closing the lid will still sleep the Mac", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text("One-time setup lets MacAwake switch lid sleep off during a session (asks for your password once).")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Enable lid-proof mode…") { engine.setupLidProof() }
                .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10)))
    }

    // MARK: Duration

    private struct Choice: Identifiable { let id: String; let label: String; let minutes: Int? }
    private let choices = [
        Choice(id: "inf", label: "∞", minutes: 0), Choice(id: "1", label: "1h", minutes: 60),
        Choice(id: "2", label: "2h", minutes: 120), Choice(id: "4", label: "4h", minutes: 240),
        Choice(id: "8", label: "8h", minutes: 480), Choice(id: "auto", label: "Auto", minutes: nil),
    ]

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ForEach(choices) { c in
                    Button { c.minutes.map { engine.start(minutes: $0) } ?? engine.start(.whileAgentsRun) } label: {
                        Text(c.label)
                            .font(.callout.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(RoundedRectangle(cornerRadius: 7).fill(isSelected(c) ? Color.accentColor : Color.secondary.opacity(0.12)))
                            .foregroundStyle(isSelected(c) ? Color.white : Color.primary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(c.minutes == nil ? "Stay awake only while a keep-alive app or agent CLI is running" :
                            c.minutes == 0 ? "Until you turn it off" : "For \(c.label)")
                }
            }
            if engine.active, engine.remaining != nil {
                HStack {
                    Text("Ends \(engine.modeDescription.replacingOccurrences(of: "until ", with: "at "))")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("+30m") { engine.extend(minutes: 30) }.controlSize(.small)
                    Button("+1h") { engine.extend(minutes: 60) }.controlSize(.small)
                }
            }
        }
    }

    private func isSelected(_ c: Choice) -> Bool {
        guard engine.active else { return false }
        switch engine.mode {
        case .indefinite: return c.minutes == 0
        case .whileAgentsRun: return c.minutes == nil
        case .until: return c.minutes == engine.config.lastDurationMinutes && c.minutes != 0
        }
    }

    // MARK: Status

    private var statusCard: some View {
        VStack(spacing: 8) {
            StatusRow(icon: engine.lidClosed ? "laptopcomputer" : "laptopcomputer.and.arrow.down",
                      title: "Lid", value: engine.hasLid ? (engine.lidClosed ? "Closed" : "Open") : "No lid",
                      tint: .secondary)
            StatusRow(icon: "bed.double", title: "Sleep", value: sleepText, tint: sleepTint)
            StatusRow(icon: engine.onHotspot ? "personalhotspot" : (engine.networkOnline ? "wifi" : "wifi.exclamationmark"),
                      title: "Internet", value: engine.engaged ? engine.networkSummary : "Not monitored",
                      tint: engine.engaged ? (engine.networkOnline ? .green : .red) : .secondary)
            if engine.engaged, !engine.networkAction.isEmpty {
                Text(engine.networkAction).font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing).lineLimit(1)
            }
            StatusRow(icon: "pause.circle", title: "Paused apps",
                      value: engine.frozenApps.isEmpty ? (engine.config.freezeOthersOnLidClose ? "None (lid open)" : "Off")
                                                       : engine.frozenApps.joined(separator: ", "),
                      tint: engine.frozenApps.isEmpty ? .secondary : .blue)
            if let b = engine.battery {
                StatusRow(icon: b.onAC ? "battery.100.bolt" : batteryIcon(b.percent), title: "Battery",
                          value: "\(b.percent)%\(b.onAC ? " · charging" : " · stops at \(engine.config.batteryFloorPercent)%")",
                          tint: b.percent <= 20 && !b.onAC ? .red : .secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }

    private var sleepText: String {
        guard engine.engaged else { return "Normal" }
        if engine.sleepDisabledByUs { return "Blocked, even with lid closed" }
        return engine.lidProofReady ? "Blocked" : "Idle sleep blocked only"
    }

    private var sleepTint: Color {
        guard engine.engaged else { return .secondary }
        return engine.sleepDisabledByUs || engine.lidProofReady ? .green : .orange
    }

    private func batteryIcon(_ p: Int) -> String {
        p > 75 ? "battery.100" : p > 50 ? "battery.75" : p > 25 ? "battery.50" : p > 10 ? "battery.25" : "battery.0"
    }

    // MARK: Keep-alive apps

    private var keepAliveSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keep alive").font(.subheadline.weight(.semibold))
                Text("everything else pauses when the lid closes").font(.caption).foregroundStyle(.secondary)
                Spacer()
                AddAppMenu()
            }
            if engine.config.keepAliveApps.isEmpty {
                Text("No apps yet — add Claude, Codex, Cursor or your terminal.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(engine.config.keepAliveApps) { app in
                        AppChip(app: app, running: engine.runningKeepAliveApps.contains(app.bundleID)) {
                            engine.removeApp(app.bundleID)
                        }
                    }
                }
            }
            if !engine.agentProcesses.isEmpty {
                Label("Agent CLIs running: \(engine.agentProcesses.joined(separator: ", "))", systemImage: "terminal")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: { Label("Settings…", systemImage: "gearshape") }
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }
}

struct StatusRow: View {
    let icon: String, title: String, value: String, tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(tint)
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).lineLimit(1).truncationMode(.tail).multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

struct AppChip: View {
    let app: KeepAliveApp
    let running: Bool
    let onRemove: () -> Void
    @ViewState private var hover = false

    var body: some View {
        HStack(spacing: 5) {
            Image(nsImage: AppIcon.image(for: app)).resizable().frame(width: 16, height: 16)
            Text(app.name).font(.caption).lineLimit(1)
            if hover {
                Button(action: onRemove) { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).font(.caption)
            } else {
                Circle().fill(running ? Color.green : Color.secondary.opacity(0.35)).frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Capsule().fill(Color.secondary.opacity(0.12)))
        .onHover { hover = $0 }
        .help(running ? "\(app.name) is running and will be kept alive" : "\(app.name) is not running")
    }
}

/// "+" menu: pick from running apps, or browse for any .app.
struct AddAppMenu: View {
    @Environment(AwakeEngine.self) private var engine

    var body: some View {
        Menu {
            let kept = Set(engine.config.keepAliveApps.map(\.bundleID))
            let apps = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil && !kept.contains($0.bundleIdentifier!) && $0.bundleIdentifier != Paths.bundleID }
                .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
            Section("Running apps") {
                ForEach(apps, id: \.processIdentifier) { app in
                    Button {
                        if let url = app.bundleURL { engine.addApp(at: url) }
                    } label: {
                        Text(app.localizedName ?? app.bundleIdentifier!)
                    }
                }
            }
            Divider()
            Button("Choose an app…") { chooseApp() }
        } label: {
            Image(systemName: "plus.circle.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK { panel.urls.forEach { engine.addApp(at: $0) } }
    }
}

enum AppIcon {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor static func image(for app: KeepAliveApp) -> NSImage {
        if let i = cache[app.bundleID] { return i }
        let path = app.path ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID)?.path
        let img = path.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!
        cache[app.bundleID] = img
        return img
    }
}

/// Wrapping horizontal layout for app chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > width, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

/// The Command Line Tools ship without SwiftUI's macro plugin, so the `@State` macro
/// can't expand there. This alias selects SwiftUI's plain property wrapper instead,
/// letting the app build with `swift build` without a full Xcode install.
typealias ViewState<Value> = SwiftUICore.State<Value>

import AppKit
import CoreLocation
import SwiftUI

/// System Settings–style layout: a sidebar of panes on the left, the pane on the right.
struct SettingsView: View {
    @Environment(SettingsNavigation.self) private var nav

    var body: some View {
        @Bindable var nav = nav
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                Text(nav.pane.title)
                    .font(.title2.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.top, 22)
                    .padding(.bottom, 2)
                detail
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 460, maxHeight: .infinity)
        .ignoresSafeArea()
    }

    private var sidebar: some View {
        @Bindable var nav = nav
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("KeepMeAlive").font(.headline)
                    Text("Version \(SettingsView.version)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 44)   // clear the traffic-light buttons
            .padding(.bottom, 14)

            List(selection: Binding(get: { nav.pane }, set: { if let p = $0 { nav.pane = p } })) {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        Image(systemName: pane.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(pane.tint.gradient))
                    }
                    .padding(.vertical, 2)
                    .tag(pane)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 210)
        .frame(maxHeight: .infinity)
        .background(VisualEffect().ignoresSafeArea())
    }

    @ViewBuilder private var detail: some View {
        switch nav.pane {
        case .general: GeneralTab()
        case .apps: AppsTab()
        case .internet: NetworkTab()
        case .advanced: AdvancedTab()
        case .about: AboutPane()
        }
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}

/// Translucent sidebar material, like System Settings.
private struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .sidebar
        v.blendingMode = .behindWindow
        v.state = .followsWindowActiveState
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private struct AboutPane: View {
    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 112, height: 112)
            Text("KeepMeAlive").font(.title.weight(.semibold))
            Text("Version \(SettingsView.version)").foregroundStyle(.secondary)
            Text("Close the lid. Your agents keep working.")
                .font(.callout).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Link("GitHub", destination: URL(string: "https://github.com/naaji-navas/KeepMeAlive")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Report an issue", destination: URL(string: "https://github.com/naaji-navas/KeepMeAlive/issues")!)
                Text("·").foregroundStyle(.tertiary)
                Link("Releases", destination: URL(string: "https://github.com/naaji-navas/KeepMeAlive/releases")!)
            }
            .font(.callout)
            Spacer()
            Text("Open source under the MIT License.").font(.caption).foregroundStyle(.tertiary)
                .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GeneralTab: View {
    @Environment(AwakeEngine.self) private var engine

    var body: some View {
        @Bindable var engine = engine
        Form {
            Section("Lid close") {
                LabeledContent("Lid-proof mode") {
                    if engine.lidProofReady {
                        Label("Enabled", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    } else {
                        Button("Set Up…") { SetupWindowController.shared.show(engine: engine) }
                    }
                }
                Toggle("Pause all other apps while the lid is closed", isOn: $engine.config.freezeOthersOnLidClose)
                Toggle("Turn the display off when the lid closes", isOn: $engine.config.sleepDisplayOnLidClose)
                Toggle("Mute sound while the lid is closed", isOn: $engine.config.muteOnLidClose)
            }
            Section("Safety") {
                Stepper(value: $engine.config.batteryFloorPercent, in: 0...50, step: 5) {
                    LabeledContent("End session on battery below",
                                   value: engine.config.batteryFloorPercent == 0 ? "Never" : "\(engine.config.batteryFloorPercent)%")
                }
                Toggle("End session if the Mac gets critically hot", isOn: $engine.config.endOnCriticalHeat)
                Text("Keep the Mac on a hard surface with airflow — never in a closed bag while a session runs.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Open KeepMeAlive at login", isOn: Binding(get: { engine.launchAtLogin }, set: { engine.setLaunchAtLogin($0) }))
            }
        }
        .formStyle(.grouped)
    }
}

private struct AppsTab: View {
    @Environment(AwakeEngine.self) private var engine
    @ViewState private var newProcess = ""

    var body: some View {
        @Bindable var engine = engine
        Form {
            Section {
                ForEach(engine.config.keepAliveApps) { app in
                    HStack {
                        Image(nsImage: AppIcon.image(for: app)).resizable().frame(width: 20, height: 20)
                        VStack(alignment: .leading) {
                            Text(app.name)
                            Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if engine.runningKeepAliveApps.contains(app.bundleID) {
                            Text("running").font(.caption).foregroundStyle(.green)
                        }
                        Button(role: .destructive) { engine.removeApp(app.bundleID) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack { Spacer(); AddAppMenu() }
            } header: {
                Text("Apps kept alive with the lid closed")
            } footer: {
                Text("Every other app is paused (SIGSTOP) when the lid closes and resumes the instant it opens. Meeting apps, password managers and macOS itself are never paused.")
            }

            Section {
                ForEach(engine.config.keepAliveProcesses, id: \.self) { name in
                    HStack {
                        Image(systemName: "terminal")
                        Text(name).font(.body.monospaced())
                        Spacer()
                        Button(role: .destructive) { engine.config.keepAliveProcesses.removeAll { $0 == name } } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("process name, e.g. codex", text: $newProcess)
                        .onSubmit(addProcess)
                    Button("Add", action: addProcess).disabled(newProcess.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Command-line agents")
            } footer: {
                Text("A running process with one of these names — plus the terminal or editor it runs in — is always kept alive. \"Auto\" sessions stay awake only while one of these or a keep-alive app is running.")
            }

            Section {
                Toggle("Stop App Nap from throttling keep-alive apps", isOn: $engine.config.disableAppNapForKeepAlive)
            } footer: {
                Text("Sets NSAppSleepDisabled for those apps only. Takes effect the next time each app launches.")
            }
        }
        .formStyle(.grouped)
    }

    private func addProcess() {
        let n = newProcess.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, !engine.config.keepAliveProcesses.contains(n) else { return }
        engine.config.keepAliveProcesses.append(n)
        newProcess = ""
    }
}

private struct NetworkTab: View {
    @Environment(AwakeEngine.self) private var engine
    @ViewState private var ssid = ""
    @ViewState private var password = ""
    @ViewState private var saved: Bool?
    @ViewState private var locationStatus = LocationGate.shared.status

    var body: some View {
        @Bindable var engine = engine
        Form {
            Section {
                Toggle("Keep me online during a session", isOn: $engine.config.failoverEnabled)
                Stepper(value: $engine.config.failoverGraceSeconds, in: 10...300, step: 10) {
                    LabeledContent("Switch to mobile data after", value: "\(engine.config.failoverGraceSeconds)s offline")
                }
                Toggle("Move back to normal Wi-Fi when it returns", isOn: $engine.config.returnToPrimaryWiFi)
            } footer: {
                Text("KeepMeAlive checks real internet access every 10 seconds. If Wi-Fi is switched off it turns it back on; if the internet stays down, it joins your phone's Personal Hotspot.")
            }

            Section {
                TextField("Hotspot name (e.g. Alex's iPhone)", text: $ssid)
                SecureField("Hotspot password", text: $password)
                HStack {
                    if let saved {
                        Label(saved ? "Saved to Keychain" : "Could not save", systemImage: saved ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .foregroundStyle(saved ? .green : .red).font(.callout)
                    }
                    Spacer()
                    Button("Test failover now") { engine.testFailover() }
                        .disabled(engine.config.hotspotSSID.isEmpty)
                    Button("Save") { saved = engine.saveHotspot(ssid: ssid, password: password); password = "" }
                        .keyboardShortcut(.defaultAction)
                }
                LabeledContent("Location access") {
                    switch locationStatus {
                    case .authorizedAlways, .authorized:
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .denied, .restricted:
                        Button("Open Privacy Settings…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
                        }
                    default:
                        Button("Allow…") { LocationGate.shared.request() }
                    }
                }
            } header: {
                Text("Mobile data (Personal Hotspot)")
            } footer: {
                Text("On your iPhone turn on Settings → Personal Hotspot → Allow Others to Join. The password stays in your login Keychain. macOS needs Location access to show Wi-Fi names; KeepMeAlive never reads your location. A phone plugged in by USB is used automatically by macOS.")
            }

            if !engine.networkAction.isEmpty {
                Section("Last network action") { Text(engine.networkAction).font(.callout) }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            ssid = engine.config.hotspotSSID
            LocationGate.shared.onChange = { locationStatus = LocationGate.shared.status }
        }
    }
}

private struct AdvancedTab: View {
    @Environment(AwakeEngine.self) private var engine

    var body: some View {
        Form {
            Section("System changes KeepMeAlive can make") {
                LabeledContent("Sleep rule", value: FileManager.default.fileExists(atPath: SleepControl.sudoersPath) ? SleepControl.sudoersPath : "Not installed")
                LabeledContent("Crash watchdog", value: Watchdog.isInstalled ? "Running every minute" : "Not installed")
                Text("The sudoers rule allows exactly two commands: pmset -a disablesleep 1 and 0. If KeepMeAlive crashes, the watchdog re-enables sleep and resumes paused apps within a minute.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Command line") {
                Text(verbatim: "\(Bundle.main.executablePath ?? "KeepMeAlive") on 2h | on auto | off | status")
                    .font(.caption.monospaced()).textSelection(.enabled)
            }
            Section("Logs") {
                HStack {
                    Button("Show logs in Finder") { NSWorkspace.shared.activateFileViewerSelecting([Paths.logFile]) }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
    }
}

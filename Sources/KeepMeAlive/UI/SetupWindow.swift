import AppKit
import SwiftUI

/// The first-launch window that sets up lid-proof mode, which is what KeepMeAlive is for.
/// It explains exactly what will be installed before macOS asks for the password.
@MainActor
final class SetupWindowController: NSObject, NSWindowDelegate {
    static let shared = SetupWindowController()

    private var window: NSWindow?

    func show(engine: AwakeEngine) {
        AppWindows.dismissMenuBarPanel(except: window)
        let win = window ?? makeWindow(engine: engine)
        window = win
        if !win.isVisible { AppWindows.centerOnActiveScreen(win) }
        AppWindows.bringToFront(win)
    }

    func close() { window?.close() }

    private func makeWindow(engine: AwakeEngine) -> NSWindow {
        let host = NSHostingController(rootView: SetupView(close: { [weak self] in self?.close() }).environment(engine))
        host.sizingOptions = []
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 600),
                           styleMask: [.titled, .closable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.contentViewController = host
        win.title = "Set Up KeepMeAlive"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.moveToActiveSpace]
        win.setContentSize(NSSize(width: 540, height: 600))
        win.delegate = self
        return win
    }

    func windowWillClose(_ notification: Notification) {
        AppWindows.windowWillClose(window)
    }
}

private struct SetupView: View {
    @Environment(AwakeEngine.self) private var engine
    let close: () -> Void
    @ViewState private var working = false

    var body: some View {
        VStack(spacing: 0) {
            if engine.lidProofReady { doneState } else { introState }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .ignoresSafeArea()
    }

    // MARK: Intro

    private var introState: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 88, height: 88)
                .padding(.top, 46)
            Text("Welcome to KeepMeAlive").font(.title.weight(.semibold)).padding(.top, 12)
            Text("Close the lid. Your agents keep working.")
                .foregroundStyle(.secondary).padding(.top, 4)

            VStack(alignment: .leading, spacing: 18) {
                Text("Lid-proof mode needs a one-time setup")
                    .font(.headline)
                step("lock.shield.fill", .blue, "Your password, once",
                     "macOS only lets an administrator stop a MacBook sleeping when the lid closes. KeepMeAlive adds a rule that allows exactly one setting, `pmset disablesleep` on or off, and nothing else.")
                step("lifepreserver.fill", .green, "A safety net",
                     "A tiny background check runs once a minute. If KeepMeAlive ever quits unexpectedly, it turns sleep back on and resumes any paused apps.")
                step("bell.badge.fill", .orange, "Alerts",
                     "macOS will ask to allow notifications, so you hear when a session ends early, for example on low battery.")
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.secondary.opacity(0.08)))
            .padding(.horizontal, 32)
            .padding(.top, 26)

            if let err = engine.lastSetupError {
                Label("Setup wasn't completed: \(err)", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.red)
                    .padding(.top, 14).padding(.horizontal, 32)
            }

            Spacer(minLength: 16)

            HStack {
                Button("Not Now") {
                    engine.config.onboardingShown = true
                    close()
                }
                .controlSize(.large)
                Spacer()
                Button {
                    working = true
                    // Let the button redraw before macOS shows its password prompt.
                    DispatchQueue.main.async {
                        engine.setupLidProof()
                        working = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if working { ProgressView().controlSize(.small) }
                        Text(engine.lastSetupError == nil ? "Set Up Lid-Proof Mode" : "Try Again")
                    }
                    .frame(minWidth: 190)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(working)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 26)
        }
    }

    private func step(_ symbol: String, _ tint: Color, _ title: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Done

    private var doneState: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green.gradient)
            Text("You're all set").font(.title.weight(.semibold)).padding(.top, 16)
            Text("Click the moon in the menu bar to start a session, then close the lid. Your agents keep running and the screen stays off.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
                .padding(.top, 8)
            Toggle("Open KeepMeAlive at login",
                   isOn: Binding(get: { engine.launchAtLogin }, set: { engine.setLaunchAtLogin($0) }))
                .toggleStyle(.switch)
                .padding(.top, 26)
            Spacer()
            Button("Done", action: close)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.bottom, 26)
        }
        .padding(.horizontal, 32)
    }
}

import AppKit
import SwiftUI

/// Owns the Settings window.
///
/// KeepMeAlive is a menu bar app (no Dock icon), so a plain SwiftUI `Window` slips
/// behind other apps the moment you click away and there is no way to get it back.
/// While Settings is open the app becomes a regular app (Dock icon, Cmd-Tab), the
/// menu bar panel is dismissed, and the window behaves like any other Mac window.
/// Closing it returns KeepMeAlive to the menu bar only.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    func show(engine: AwakeEngine, pane: SettingsPane? = nil) {
        dismissMenuBarPanel()
        if let pane { SettingsNavigation.shared.pane = pane }

        let win = window ?? makeWindow(engine: engine)
        window = win

        AppWindows.bringToFront(win)
    }

    private func makeWindow(engine: AwakeEngine) -> NSWindow {
        let root = SettingsView()
            .environment(engine)
            .environment(SettingsNavigation.shared)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []   // the window owns its size; SwiftUI fills it
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.contentViewController = host
        win.title = "KeepMeAlive Settings"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.moveToActiveSpace]
        win.setContentSize(NSSize(width: 760, height: 540))
        win.contentMinSize = NSSize(width: 680, height: 460)
        win.delegate = self
        AppWindows.centerOnActiveScreen(win)
        win.setFrameAutosaveName("KeepMeAliveSettings")
        return win
    }

    func windowWillClose(_ notification: Notification) {
        AppWindows.windowWillClose(window)
    }

    private func dismissMenuBarPanel() { AppWindows.dismissMenuBarPanel(except: window) }
}

/// Shared behaviour for KeepMeAlive's real windows (Settings, Setup).
@MainActor
enum AppWindows {
    static var managed: [NSWindow] = []

    /// Becomes a regular app while a window is open, so it can't get lost behind others.
    static func bringToFront(_ win: NSWindow) {
        if !managed.contains(where: { $0 === win }) { managed.append(win) }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            win.makeKeyAndOrderFront(nil)
        }
    }

    /// Centers a window on the screen the pointer is on (where the menu bar was clicked).
    static func centerOnActiveScreen(_ win: NSWindow) {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main else {
            win.center(); return
        }
        let v = screen.visibleFrame, f = win.frame
        win.setFrameOrigin(NSPoint(x: v.midX - f.width / 2, y: v.midY - f.height / 2 + v.height * 0.08))
    }

    /// Back to menu-bar-only once the last window closes.
    static func windowWillClose(_ win: NSWindow?) {
        let othersOpen = managed.contains { $0 !== win && $0.isVisible }
        if !othersOpen { NSApp.setActivationPolicy(.accessory) }
    }

    /// Closes the MenuBarExtra popover so it doesn't sit on top of a window.
    static func dismissMenuBarPanel(except keep: NSWindow?) {
        for w in NSApp.windows where w.isVisible && w !== keep && !managed.contains(where: { $0 === w }) {
            let cls = String(describing: type(of: w))
            if cls.contains("MenuBarExtra") || (w is NSPanel && w.level.rawValue > NSWindow.Level.normal.rawValue) {
                w.close()
            }
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, apps, internet, advanced, about
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .apps: "Apps"
        case .internet: "Internet"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .apps: "square.grid.2x2.fill"
        case .internet: "wifi"
        case .advanced: "wrench.and.screwdriver.fill"
        case .about: "info.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: .gray
        case .apps: .blue
        case .internet: .teal
        case .advanced: .orange
        case .about: .indigo
        }
    }
}

@Observable
@MainActor
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var pane: SettingsPane = .general
}

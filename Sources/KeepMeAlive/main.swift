import AppKit
import SwiftUI

// `KeepMeAlive on|off|status|...` drives the running app from a terminal or an agent.
if let code = CLI.runIfCommand(Array(CommandLine.arguments.dropFirst())) {
    exit(code)
}

KeepMeAliveApp.main()

final class AppDelegate: NSObject, NSApplicationDelegate {
    var engine: AwakeEngine?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { engine?.shutdown() }
        return .terminateNow
    }
}

struct KeepMeAliveApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @ViewState private var engine = AwakeEngine()

    var body: some Scene {
        MenuBarExtra {
            MenuPanel()
                .environment(engine)
                .onAppear { delegate.engine = engine }
        } label: {
            MenuBarLabel(engine: engine)
                .onAppear { delegate.engine = engine }
        }
        .menuBarExtraStyle(.window)
        // Settings lives in an AppKit-managed window (SettingsWindowController) so it
        // behaves like a normal window instead of vanishing behind other apps.
    }
}

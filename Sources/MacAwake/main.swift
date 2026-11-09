import AppKit
import SwiftUI

// `MacAwake on|off|status|...` drives the running app from a terminal or an agent.
if let code = CLI.runIfCommand(Array(CommandLine.arguments.dropFirst())) {
    exit(code)
}

MacAwakeApp.main()

final class AppDelegate: NSObject, NSApplicationDelegate {
    var engine: AwakeEngine?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated { engine?.shutdown() }
        return .terminateNow
    }
}

struct MacAwakeApp: App {
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

        Window("MacAwake Settings", id: "settings") {
            SettingsView()
                .environment(engine)
                .frame(minWidth: 560, minHeight: 520)
        }
        .windowResizability(.contentSize)
    }
}

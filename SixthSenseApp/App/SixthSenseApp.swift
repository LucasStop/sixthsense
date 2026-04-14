import SwiftUI

@main
struct SixthSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar icon with popover
        MenuBarExtra {
            MenuBarView(appState: appState)
                .frame(width: 320, height: 480)
        } label: {
            Image(systemName: "hand.raised.fingers.spread")
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView(appState: appState)
        }
    }
}

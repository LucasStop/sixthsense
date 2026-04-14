import SwiftUI

@main
struct SixthSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        // Menu bar icon with popover
        MenuBarExtra {
            MenuBarView(appState: appState)
        } label: {
            Image(systemName: "hand.raised.fingers.spread")
        }
        .menuBarExtraStyle(.window)

        // Settings window
        Settings {
            SettingsView(appState: appState)
        }

        // Tutorial window
        Window("Tutorial — SixthSense", id: "tutorials") {
            OnboardingView()
        }
        .defaultSize(width: 780, height: 640)

        // Hand tracking training / debug window
        Window("Modo Treinamento", id: "hand-training") {
            HandTrainingView(
                handModule: appState.registry.handCommand,
                cameraSession: { appState.services.camera.avSession }
            )
        }
        .defaultSize(width: 620, height: 760)
    }
}

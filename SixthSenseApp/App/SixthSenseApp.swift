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

        // Tutorial window
        Window("SixthSense Tutorials", id: "tutorials") {
            OnboardingView()
        }
        .defaultSize(width: 800, height: 600)

        // Hand tracking training window
        Window("Modo Treinamento de Gestos", id: "hand-training") {
            HandTrainingView(
                handModule: appState.registry.handCommand,
                cameraSession: { appState.services.camera.avSession }
            )
        }
        .defaultSize(width: 560, height: 660)
    }
}

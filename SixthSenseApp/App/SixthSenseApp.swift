import SwiftUI

@main
struct SixthSenseApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(appState: appState)
                .task {
                    // Inject the AppState into the delegate once the
                    // SwiftUI scene tree is up so the delegate can reach
                    // the face recognition service and the camera.
                    appDelegate.appState = appState
                }
        } label: {
            Image(systemName: "hand.raised.fingers.spread")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(appState: appState)
        }

        Window("Tutorial — SixthSense", id: "tutorials") {
            OnboardingView()
        }
        .defaultSize(width: 780, height: 640)

        Window("Modo Treinamento", id: "hand-training") {
            HandTrainingView(
                handModule: appState.registry.handCommand,
                faceRecognition: appState.services.faceRecognition,
                cameraSession: { appState.services.camera.avSession }
            )
        }
        .defaultSize(width: 620, height: 780)
    }
}

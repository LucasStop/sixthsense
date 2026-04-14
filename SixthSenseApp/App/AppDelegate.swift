import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices
import SharedServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var setupWindow: NSWindow?
    private var enrollmentWindow: NSWindow?

    /// Injected by SixthSenseApp once its @State is created so the
    /// AppDelegate can reach the face recognition manager and the camera
    /// session when building modal windows from launch/notification.
    var appState: AppState?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set bundle identifier programmatically for SPM-based executables.
        if Bundle.main.bundleIdentifier == nil {
            let info = Bundle.main.infoDictionary ?? [:]
            if info["CFBundleIdentifier"] == nil {
                UserDefaults.standard.set("com.lucasstop.sixthsense",
                                          forKey: "CFBundleIdentifier")
            }
        }

        if !AXIsProcessTrusted() {
            print("[SixthSense] Acessibilidade ainda não concedida. Solicitaremos quando necessário.")
        } else {
            print("[SixthSense] Acessibilidade concedida.")
        }

        print("[SixthSense] Aplicativo iniciado com sucesso.")

        // Abre a sequência de onboarding (setup → enrollment) assim que
        // as scenes SwiftUI tiverem um chance de inicializar.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.beginOnboardingIfNeeded()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSetupRequest),
            name: .sixthSenseOpenSetup,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenEnrollmentRequest),
            name: .sixthSenseOpenEnrollment,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        print("[SixthSense] Encerrando...")
    }

    // MARK: - Onboarding flow

    /// Decide which onboarding step (if any) to open: permissions first,
    /// then face enrollment.
    private func beginOnboardingIfNeeded() {
        let cameraOK = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let accessibilityOK = AXIsProcessTrusted()

        if !cameraOK || !accessibilityOK {
            showSetupWindow()
            return
        }

        // Permissions are already granted — jump straight to enrollment
        // if the user hasn't configured face recognition yet.
        if shouldOfferEnrollment() {
            showEnrollmentWindow()
        }
    }

    /// True when the user hasn't made a face-lock choice yet. We consider
    /// the onboarding complete once `lockMode != .disabled` or the
    /// `face.onboarded` flag has been explicitly set (user skipped).
    private func shouldOfferEnrollment() -> Bool {
        guard let face = appState?.services.faceRecognition else { return false }
        // If any mode other than .disabled is set, enrollment has been
        // addressed at some point.
        if face.store.lockMode != .disabled { return false }
        // Respect the "onboarded" sentinel so we don't reopen the window
        // on every launch when the user chose to skip.
        if UserDefaults.standard.bool(forKey: "com.lucasstop.sixthsense.face.onboarded") {
            return false
        }
        return true
    }

    private func markEnrollmentOnboarded() {
        UserDefaults.standard.set(true, forKey: "com.lucasstop.sixthsense.face.onboarded")
    }

    // MARK: - Setup window

    @objc private func handleOpenSetupRequest() {
        showSetupWindow()
    }

    private func showSetupWindow() {
        if let window = setupWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SetupView { [weak self] in
            self?.closeSetupWindow()

            // After the user dismisses the setup window, if permissions
            // are now OK and the face onboarding hasn't run yet, chain
            // into the enrollment flow.
            if let self, self.shouldOfferEnrollment() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.showEnrollmentWindow()
                }
            }
        }

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Configuração Inicial"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 580, height: 580))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.titlebarAppearsTransparent = true

        setupWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeSetupWindow() {
        setupWindow?.close()
        setupWindow = nil
    }

    // MARK: - Face enrollment window

    @objc private func handleOpenEnrollmentRequest() {
        showEnrollmentWindow()
    }

    private func showEnrollmentWindow() {
        if let window = enrollmentWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let appState else { return }

        let faceRecognition = appState.services.faceRecognition
        let cameraSession: () -> AVCaptureSession? = { [weak appState] in
            appState?.services.camera.avSession
        }

        // Ensure the camera is alive so FaceRecognitionManager can sample
        // frames during enrollment. We don't start HandCommand here —
        // only the face manager subscribes.
        faceRecognition.start()

        let view = FaceEnrollmentView(
            faceRecognition: faceRecognition,
            cameraSession: cameraSession,
            onFinish: { [weak self] in
                self?.markEnrollmentOnboarded()
                self?.closeEnrollmentWindow()
                // Stop the camera again — HandCommand will turn it back
                // on when the user clicks "Ativar controle".
                faceRecognition.stop()
            }
        )

        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Reconhecimento Facial"
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 620, height: 720))
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.titlebarAppearsTransparent = true

        enrollmentWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closeEnrollmentWindow() {
        enrollmentWindow?.close()
        enrollmentWindow = nil
    }
}

// MARK: - Notifications

extension Notification.Name {
    /// Posted by menu dropdown → "Configuração Inicial".
    static let sixthSenseOpenSetup = Notification.Name("com.lucasstop.sixthsense.openSetup")

    /// Posted by menu dropdown → "Reconhecimento Facial" (e pela Settings tab).
    static let sixthSenseOpenEnrollment = Notification.Name("com.lucasstop.sixthsense.openEnrollment")
}

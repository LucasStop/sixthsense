import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate {

    /// Janela de setup mantida como referência forte enquanto aberta. A
    /// classe NSWindow é liberada quando o usuário fecha, então definimos
    /// isReleasedWhenClosed = false e limpamos manualmente no onFinish.
    private var setupWindow: NSWindow?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set bundle identifier programmatically for SPM-based executables.
        // Without this, MenuBarExtra and Settings scenes may not work correctly.
        if Bundle.main.bundleIdentifier == nil {
            let info = Bundle.main.infoDictionary ?? [:]
            if info["CFBundleIdentifier"] == nil {
                // Register a default identifier so the system can track window state
                UserDefaults.standard.set("com.lucasstop.sixthsense",
                                          forKey: "CFBundleIdentifier")
            }
        }

        // Verifica permissões de acessibilidade ao iniciar
        if !AXIsProcessTrusted() {
            print("[SixthSense] Acessibilidade ainda não concedida. Solicitaremos quando necessário.")
        } else {
            print("[SixthSense] Acessibilidade concedida.")
        }

        print("[SixthSense] Aplicativo iniciado com sucesso.")

        // Se alguma permissão essencial estiver pendente, abrir a janela
        // de configuração inicial. Delay para dar tempo das Scenes
        // SwiftUI terminarem de inicializar antes de trazermos outra
        // janela pra frente.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.openSetupWindowIfNeeded()
        }

        // Observer para reabrir a setup window via notification
        // (disparada pelo botão do menu bar).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSetupRequest),
            name: .sixthSenseOpenSetup,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self)
        print("[SixthSense] Encerrando...")
    }

    // MARK: - Setup window management

    /// Abre a setup window somente se alguma permissão essencial
    /// (câmera ou acessibilidade) estiver pendente.
    private func openSetupWindowIfNeeded() {
        let cameraOK = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let accessibilityOK = AXIsProcessTrusted()
        guard !cameraOK || !accessibilityOK else { return }
        showSetupWindow()
    }

    /// Força a abertura da setup window independentemente do estado
    /// das permissões. Usada pelo item "Configuração Inicial" do menu.
    @objc private func handleOpenSetupRequest() {
        showSetupWindow()
    }

    private func showSetupWindow() {
        // Se já existe, só traz pra frente.
        if let window = setupWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = SetupView { [weak self] in
            self?.closeSetupWindow()
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
}

// MARK: - Notifications

extension Notification.Name {
    /// Disparada pelo item "Configuração Inicial" do menu bar dropdown
    /// para reabrir a janela de setup manualmente.
    static let sixthSenseOpenSetup = Notification.Name("com.lucasstop.sixthsense.openSetup")
}

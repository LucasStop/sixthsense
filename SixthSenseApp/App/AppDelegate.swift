import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

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
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[SixthSense] Encerrando...")
    }
}

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

        // Check accessibility permissions on launch
        if !AXIsProcessTrusted() {
            print("[SixthSense] Accessibility not yet granted. Will prompt when needed.")
        } else {
            print("[SixthSense] Accessibility granted.")
        }

        print("[SixthSense] App launched successfully.")
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[SixthSense] Shutting down...")
    }
}

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Check accessibility permissions on launch
        if !AXIsProcessTrusted() {
            // Will prompt on first module activation that needs it
            print("[SixthSense] Accessibility not yet granted. Will prompt when needed.")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[SixthSense] Shutting down...")
    }
}

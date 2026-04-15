import Foundation
import ApplicationServices
import AppKit
import CoreGraphics

// MARK: - Accessibility Diagnostics

/// Reports the real-time state of the app's Accessibility permission and
/// helps the user diagnose the common "permission granted but doesn't work"
/// problem that happens on SPM-based Xcode builds: each rebuild writes a
/// new binary path under DerivedData, and the old TCC entry is orphaned.
///
/// Everything here is live — every call hits the actual macOS APIs so it
/// reflects the current process, not a cached value.
@MainActor
public enum AccessibilityDiagnostics {

    // MARK: - Permission

    /// Whether the current PROCESS is actually trusted by the Accessibility
    /// API. This is the only source of truth — ignore what System Settings
    /// appears to show, because an entry there can be orphaned (granted for
    /// a stale binary path that no longer exists).
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility permission, opening the
    /// System Settings pane if it's not already open. Safe to call any
    /// number of times — it's a no-op once granted.
    public static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeRetainedValue() as CFString
        let options: CFDictionary = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Process identity

    /// Absolute path of the running executable. This is the path that the
    /// Accessibility TCC database needs to match — if the user's existing
    /// System Settings entry doesn't point here, the permission is stale.
    public static var executablePath: String {
        Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments.first ?? "desconhecido"
    }

    /// Absolute path of the running .app bundle when running as a proper
    /// app (e.g. installed in ~/Applications/SixthSense.app), or `nil`
    /// when the process is running as a raw SPM executable. This is what
    /// the user should drag into System Settings → Accessibility; macOS
    /// resolves the enclosed executable automatically and the permission
    /// follows the bundle ID, not the deep Contents/MacOS/ path.
    public static var bundlePath: String? {
        let path = Bundle.main.bundlePath
        // Bundle.main.bundlePath returns the enclosing directory for the
        // executable even when there's no .app — filter that out so we
        // only return "real" bundle paths.
        return path.hasSuffix(".app") ? path : nil
    }

    /// The path that should be shown to the user in the "adicione isto
    /// nos Ajustes" instructions — prefers the .app bundle when present
    /// (the common installed case) and falls back to the raw executable
    /// path otherwise (dev runs via swift run).
    public static var preferredInstallablePath: String {
        bundlePath ?? executablePath
    }

    /// Bundle identifier of the running app, or `nil` if not set. SPM
    /// executables often ship without a proper bundle ID, which is itself
    /// a source of permission problems.
    public static var bundleIdentifier: String? {
        Bundle.main.bundleIdentifier
    }

    /// The process ID — useful when checking with `tccutil`.
    public static var processId: Int32 {
        ProcessInfo.processInfo.processIdentifier
    }

    // MARK: - Live injection test

    /// Attempts a synthetic mouse-move event at the current cursor
    /// position. It's a no-op visually (cursor doesn't actually move) but
    /// it exercises the CGEvent.post pipeline that gestures use. Returns
    /// whether the CGEvent could be created and posted.
    ///
    /// If this returns `true` but gestures still feel dead, the problem is
    /// elsewhere (classifier, camera feed, etc.). If it returns `false`,
    /// the Accessibility entry in System Settings doesn't cover the
    /// current binary.
    public static func performInjectionProbe() -> InjectionProbeResult {
        guard isTrusted else {
            return .deniedByTCC
        }

        let current = NSEvent.mouseLocation
        // NSEvent gives us screen coordinates with a bottom-left origin;
        // CGEvent wants top-left, so flip Y against the main screen height.
        let height = NSScreen.main?.frame.height ?? 0
        let point = CGPoint(x: current.x, y: height - current.y)

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .mouseMoved,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else {
            return .failedToCreateEvent
        }

        event.post(tap: .cghidEventTap)
        return .succeeded
    }

    public enum InjectionProbeResult: Equatable, Sendable {
        /// AXIsProcessTrusted() returned false — the user needs to re-add
        /// the current binary in System Settings.
        case deniedByTCC

        /// CGEvent couldn't even build the event — very unusual, usually a
        /// signal that the process is somehow sandboxed.
        case failedToCreateEvent

        /// CGEvent was created and posted to the HID event tap. If the user
        /// still doesn't see gestures working, the problem is upstream of
        /// this layer (classifier, camera, hand detection).
        case succeeded

        public var label: String {
            switch self {
            case .deniedByTCC:
                return "Permissão negada"
            case .failedToCreateEvent:
                return "Falha ao criar evento"
            case .succeeded:
                return "Injeção bem-sucedida"
            }
        }

        public var isSuccess: Bool {
            self == .succeeded
        }
    }

    // MARK: - Helpers

    /// Copy the executable path to the pasteboard so the user can paste it
    /// into a Finder "Go to folder" field or a terminal to re-authorize
    /// the current binary.
    public static func copyExecutablePathToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(executablePath, forType: .string)
    }

    /// Copy the preferred installable path to the pasteboard (the .app
    /// bundle when available, the raw executable otherwise). This is the
    /// path the user will paste into Finder's "Go to folder" before
    /// dragging the selected item into Ajustes → Acessibilidade.
    public static func copyPreferredPathToPasteboard() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(preferredInstallablePath, forType: .string)
    }

    /// Open the Accessibility pane directly so the user can re-add the
    /// current binary.
    public static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}

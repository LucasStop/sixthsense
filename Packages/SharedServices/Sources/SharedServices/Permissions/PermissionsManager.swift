import AVFoundation
import ApplicationServices
import AppKit
import SixthSenseCore

// MARK: - Permissions Manager

/// Centralized permission state tracker for all system permissions.
/// Modules declare their requirements; this manager tracks aggregate state.
@MainActor
@Observable
public final class PermissionsManager {

    public private(set) var cameraGranted = false
    public private(set) var accessibilityGranted = false
    public private(set) var screenRecordingGranted = false

    public init() {
        refreshAll()
    }

    /// Refresh all permission states.
    public func refreshAll() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        accessibilityGranted = AXIsProcessTrusted()
        // Screen recording is checked indirectly (no public API to query)
        screenRecordingGranted = checkScreenRecordingPermission()
    }

    /// Check which required permissions are missing.
    public func checkMissing(_ requirements: [PermissionRequirement]) -> [PermissionRequirement] {
        refreshAll()
        return requirements.filter { req in
            switch req.type {
            case .camera: return !cameraGranted
            case .accessibility: return !accessibilityGranted
            case .screenRecording: return !screenRecordingGranted
            case .localNetwork: return false // Cannot check programmatically
            case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) != .authorized
            }
        }
    }

    /// Request camera permission.
    public func requestCamera() async -> Bool {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraGranted = granted
        return granted
    }

    /// Prompt for accessibility permission (opens System Settings).
    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Open Screen Recording settings.
    public func openScreenRecordingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    /// Open Accessibility settings.
    public func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Check if a specific permission type is granted.
    public func isGranted(_ type: PermissionType) -> Bool {
        switch type {
        case .camera: return cameraGranted
        case .accessibility: return accessibilityGranted
        case .screenRecording: return screenRecordingGranted
        case .localNetwork: return true // Assumed granted if app is running
        case .microphone: return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    // MARK: - Private

    private func checkScreenRecordingPermission() -> Bool {
        // Indirect check: try to get window list with names
        // If screen recording is not granted, window names will be nil
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        // If we can read at least one window name, permission is granted
        return windowList.contains { ($0[kCGWindowName as String] as? String) != nil }
    }
}

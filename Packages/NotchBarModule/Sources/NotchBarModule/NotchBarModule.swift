import SwiftUI
import Combine
import SixthSenseCore
import SharedServices

// MARK: - NotchBar Module

/// Transforms the MacBook notch area into an interactive status bar by
/// placing a transparent overlay window directly over the notch region.
@MainActor
@Observable
public final class NotchBarModule: SixthSenseModule {

    // MARK: - Descriptor

    public static let descriptor = ModuleDescriptor(
        id: "notch-bar",
        name: "NotchBar",
        tagline: "Notch Alive",
        systemImage: "menubar.rectangle",
        category: .interface
    )

    // MARK: - State

    public var state: ModuleState = .disabled

    public var requiredPermissions: [PermissionRequirement] {
        [
            PermissionRequirement(
                type: .microphone,
                reason: "Optional: enables audio visualisation inside the notch area",
                isRequired: false
            ),
        ]
    }

    // MARK: - Settings

    /// Whether the notch bar should auto-hide when no content is displayed.
    public var autoHide: Bool = false

    // MARK: - Settings View

    public var settingsView: some View {
        Form {
            Section("NotchBar") {
                Toggle("Auto-hide when idle", isOn: Binding(
                    get: { self.autoHide },
                    set: { self.autoHide = $0 }
                ))
                Text("Transforms the MacBook notch into an interactive control center.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Dependencies

    private let overlayManager: OverlayWindowManager

    // MARK: - Init

    public init(overlay: OverlayWindowManager) {
        self.overlayManager = overlay
    }

    // MARK: - Lifecycle

    public func start() async throws {
        state = .starting

        guard let notchFrame = Self.detectNotchFrame() else {
            // No notch detected (external display or pre-notch Mac); use a
            // sensible default at the top-center of the screen.
            state = .running
            createOverlay(frame: Self.fallbackFrame())
            return
        }

        createOverlay(frame: notchFrame)
        state = .running
    }

    public func stop() async {
        state = .stopping
        overlayManager.removeOverlay(id: Self.descriptor.id)
        state = .disabled
    }

    // MARK: - Overlay

    private func createOverlay(frame: NSRect) {
        let config = OverlayWindowConfig.interactive(frame: frame, level: .statusBar)

        overlayManager.createOverlay(id: Self.descriptor.id, config: config) {
            NotchBarContentView()
        }
    }

    // MARK: - Notch Detection

    /// Attempts to compute the rectangle covering the notch region on the
    /// built-in display.  Returns `nil` if no notch is detected.
    private static func detectNotchFrame() -> NSRect? {
        guard let screen = NSScreen.builtin else { return nil }

        // On notch MacBooks the safe-area insets carve out the notch.
        guard let topInset = screen.notchTopInset else { return nil }

        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame

        // The notch is centered at the top of the screen.
        let notchWidth: CGFloat = 300
        let notchHeight: CGFloat = topInset
        let notchX = screenFrame.midX - notchWidth / 2
        let notchY = screenFrame.maxY - notchHeight

        return NSRect(x: notchX, y: notchY, width: notchWidth, height: notchHeight)
    }

    /// Fallback frame used when no notch is detected.
    private static func fallbackFrame() -> NSRect {
        guard let screen = NSScreen.main else {
            return NSRect(x: 0, y: 0, width: 300, height: 32)
        }
        let x = screen.frame.midX - 150
        let y = screen.frame.maxY - 32
        return NSRect(x: x, y: y, width: 300, height: 32)
    }
}

// MARK: - NSScreen Extension

private extension NSScreen {
    /// Returns the built-in display, if any.
    static var builtin: NSScreen? {
        screens.first { screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            return CGDisplayIsBuiltin(id) != 0
        }
    }

    /// Safe-area top inset — non-zero on notch MacBooks.
    var notchTopInset: CGFloat? {
        if #available(macOS 12.0, *) {
            let insets = self.safeAreaInsets
            return insets.top > 0 ? insets.top : nil
        }
        return nil
    }
}

// MARK: - Notch Bar Content View

/// Placeholder SwiftUI content displayed inside the notch overlay.
private struct NotchBarContentView: View {
    var body: some View {
        HStack(spacing: 12) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.6))
            Text("SixthSense")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Image(systemName: "circle.fill")
                .font(.system(size: 5))
                .foregroundStyle(.green)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
    }
}

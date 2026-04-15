import AppKit
import SwiftUI

// MARK: - Overlay Window Configuration

public struct OverlayWindowConfig {
    public let frame: NSRect
    public let level: NSWindow.Level
    public let clickThrough: Bool
    public let opacity: CGFloat

    public init(
        frame: NSRect = NSScreen.main?.frame ?? .zero,
        level: NSWindow.Level = .floating,
        clickThrough: Bool = true,
        opacity: CGFloat = 1.0
    ) {
        self.frame = frame
        self.level = level
        self.clickThrough = clickThrough
        self.opacity = opacity
    }

    /// Full-screen click-through overlay (for hand skeleton, gaze HUD, etc.)
    public static var fullScreenPassthrough: OverlayWindowConfig {
        OverlayWindowConfig(
            frame: NSScreen.main?.frame ?? .zero,
            level: .floating,
            clickThrough: true
        )
    }

    /// Fixed-position interactive overlay for fixed-frame UI.
    public static func interactive(frame: NSRect, level: NSWindow.Level = .statusBar) -> OverlayWindowConfig {
        OverlayWindowConfig(frame: frame, level: level, clickThrough: false)
    }
}

// MARK: - Overlay Window Manager

/// Creates and manages transparent NSWindows for module overlays.
/// Multiple modules can have simultaneous overlays (e.g., hand skeleton + gaze HUD).
@MainActor
public final class OverlayWindowManager {
    private var windows: [String: NSWindow] = [:]

    public init() {}

    /// Create a transparent overlay window with SwiftUI content.
    @discardableResult
    public func createOverlay<Content: View>(
        id: String,
        config: OverlayWindowConfig = .fullScreenPassthrough,
        @ViewBuilder content: () -> Content
    ) -> NSWindow {
        // Remove existing overlay with same ID
        removeOverlay(id: id)

        let window = NSWindow(
            contentRect: config.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = config.level
        window.ignoresMouseEvents = config.clickThrough
        window.alphaValue = config.opacity
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let hostingView = NSHostingView(rootView: content())
        hostingView.frame = config.frame
        window.contentView = hostingView

        windows[id] = window
        window.orderFront(nil)

        return window
    }

    /// Remove an overlay by ID.
    public func removeOverlay(id: String) {
        windows[id]?.close()
        windows.removeValue(forKey: id)
    }

    /// Remove all overlays.
    public func removeAllOverlays() {
        for (_, window) in windows {
            window.close()
        }
        windows.removeAll()
    }

    /// Check if an overlay exists.
    public func hasOverlay(id: String) -> Bool {
        windows[id] != nil
    }

    /// Get the number of active overlays.
    public var activeOverlayCount: Int {
        windows.count
    }
}

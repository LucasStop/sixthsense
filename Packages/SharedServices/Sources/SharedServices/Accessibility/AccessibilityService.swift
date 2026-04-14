import ApplicationServices
import CoreGraphics
import AppKit
import Foundation

// MARK: - Window Info

/// Represents a macOS window with its metadata and AXUIElement reference.
public struct WindowInfo: Identifiable, Sendable {
    public let id: CGWindowID
    public let pid: pid_t
    public let title: String
    public let appName: String
    public let frame: CGRect
    public let isOnScreen: Bool
    public let layer: Int

    public init(id: CGWindowID, pid: pid_t, title: String, appName: String, frame: CGRect, isOnScreen: Bool, layer: Int) {
        self.id = id
        self.pid = pid
        self.title = title
        self.appName = appName
        self.frame = frame
        self.isOnScreen = isOnScreen
        self.layer = layer
    }
}

// MARK: - Accessibility Service

/// Wraps macOS Accessibility API (AXUIElement) for window querying and manipulation.
/// Used by HandCommand (grab/move/resize windows) and GazeShift (focus/dim windows).
@MainActor
public final class AccessibilityService {

    public init() {}

    /// Check if accessibility permissions are granted.
    public var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompt the user to grant accessibility permissions.
    public func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Get all visible windows on screen.
    public func allWindows() -> [WindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { dict -> WindowInfo? in
            guard let windowID = dict[kCGWindowNumber as String] as? CGWindowID,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let x = boundsDict["X"] as? CGFloat,
                  let y = boundsDict["Y"] as? CGFloat,
                  let width = boundsDict["Width"] as? CGFloat,
                  let height = boundsDict["Height"] as? CGFloat,
                  let layer = dict[kCGWindowLayer as String] as? Int,
                  layer == 0  // Normal window layer
            else { return nil }

            let title = dict[kCGWindowName as String] as? String ?? ""
            let appName = dict[kCGWindowOwnerName as String] as? String ?? ""
            let isOnScreen = dict[kCGWindowIsOnscreen as String] as? Bool ?? false
            let frame = CGRect(x: x, y: y, width: width, height: height)

            return WindowInfo(
                id: windowID,
                pid: pid,
                title: title,
                appName: appName,
                frame: frame,
                isOnScreen: isOnScreen,
                layer: layer
            )
        }
    }

    /// Find the topmost window at a given screen coordinate.
    public func windowAtPoint(_ point: CGPoint) -> WindowInfo? {
        allWindows().first { $0.frame.contains(point) }
    }

    /// Focus a window (bring to front) using the Accessibility API.
    public func focusWindow(_ window: WindowInfo) {
        let appRef = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)

        guard let windows = windowsRef as? [AXUIElement] else { return }

        for axWindow in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            if let axTitle = titleRef as? String, axTitle == window.title {
                AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, true as CFTypeRef)
                AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)

                // Also activate the app
                let app = NSRunningApplication(processIdentifier: window.pid)
                app?.activate()
                break
            }
        }
    }

    /// Move a window to a new origin.
    public func moveWindow(_ window: WindowInfo, to origin: CGPoint) {
        guard let axWindow = findAXWindow(for: window) else { return }
        var point = origin
        let pointRef = AXValueCreate(.cgPoint, &point)!
        AXUIElementSetAttributeValue(axWindow, kAXPositionAttribute as CFString, pointRef)
    }

    /// Resize a window.
    public func resizeWindow(_ window: WindowInfo, to size: CGSize) {
        guard let axWindow = findAXWindow(for: window) else { return }
        var newSize = size
        let sizeRef = AXValueCreate(.cgSize, &newSize)!
        AXUIElementSetAttributeValue(axWindow, kAXSizeAttribute as CFString, sizeRef)
    }

    // MARK: - Private

    private func findAXWindow(for window: WindowInfo) -> AXUIElement? {
        let appRef = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        AXUIElementCopyAttributeValue(appRef, kAXWindowsAttribute as CFString, &windowsRef)

        guard let windows = windowsRef as? [AXUIElement] else { return nil }

        for axWindow in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(axWindow, kAXTitleAttribute as CFString, &titleRef)
            if let axTitle = titleRef as? String, axTitle == window.title {
                return axWindow
            }
        }
        return nil
    }
}

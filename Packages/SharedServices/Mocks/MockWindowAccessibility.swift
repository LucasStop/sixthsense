import Foundation
import CoreGraphics
import SharedServices

/// In-memory accessibility service used for tests. Lets you configure a
/// fake window list and assert which windows were focused.
@MainActor
public final class MockWindowAccessibility: WindowAccessibility {
    public var windows: [WindowInfo] = []
    public var isAccessibilityGranted: Bool = true
    public private(set) var focusCalls: [WindowInfo] = []

    public init(windows: [WindowInfo] = [], granted: Bool = true) {
        self.windows = windows
        self.isAccessibilityGranted = granted
    }

    public func allWindows() -> [WindowInfo] {
        windows
    }

    public func windowAtPoint(_ point: CGPoint) -> WindowInfo? {
        windows.first { $0.frame.contains(point) }
    }

    public func focusWindow(_ window: WindowInfo) {
        focusCalls.append(window)
    }
}

import CoreGraphics
import Foundation

// MARK: - Cursor Controller

/// Injects synthetic mouse events (movement, clicks, scrolling) via CGEvent.
/// Shared by HandCommand (gesture-driven) and AirCursor (gyro-driven).
public final class CursorController: @unchecked Sendable {

    public init() {}

    /// Get the current cursor position.
    public var currentPosition: CGPoint {
        NSEvent.mouseLocation
    }

    /// Move the cursor to an absolute screen position.
    public func moveTo(_ point: CGPoint) {
        // CGWarpMouseCursorPosition uses top-left origin
        CGWarpMouseCursorPosition(point)

        // Also post a mouseMoved event so apps notice the cursor change
        if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                               mouseCursorPosition: point, mouseButton: .left) {
            event.post(tap: .cghidEventTap)
        }
    }

    /// Move the cursor by a relative delta from its current position.
    public func moveBy(dx: CGFloat, dy: CGFloat) {
        let current = CGEvent(source: nil)?.location ?? .zero
        let newPoint = CGPoint(x: current.x + dx, y: current.y + dy)
        moveTo(newPoint)
    }

    /// Perform a left click at the given position.
    public func leftClick(at point: CGPoint) {
        postMouseEvent(.leftMouseDown, at: point, button: .left)
        postMouseEvent(.leftMouseUp, at: point, button: .left)
    }

    /// Perform a right click at the given position.
    public func rightClick(at point: CGPoint) {
        postMouseEvent(.rightMouseDown, at: point, button: .right)
        postMouseEvent(.rightMouseUp, at: point, button: .right)
    }

    /// Perform a left mouse down (for drag operations).
    public func leftMouseDown(at point: CGPoint) {
        postMouseEvent(.leftMouseDown, at: point, button: .left)
    }

    /// Perform a left mouse up (end drag).
    public func leftMouseUp(at point: CGPoint) {
        postMouseEvent(.leftMouseUp, at: point, button: .left)
    }

    /// Post a mouse drag event.
    public func leftMouseDragged(to point: CGPoint) {
        postMouseEvent(.leftMouseDragged, at: point, button: .left)
    }

    /// Scroll the mouse wheel.
    public func scroll(deltaY: Int32, deltaX: Int32 = 0) {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel,
                                  wheelCount: 3, wheel1: deltaY, wheel2: deltaX, wheel3: 0) else { return }
        event.post(tap: .cgSessionEventTap)
    }

    // MARK: - Private

    private func postMouseEvent(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) {
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type,
                                  mouseCursorPosition: point, mouseButton: button) else { return }
        event.post(tap: .cghidEventTap)
    }
}

// Make NSEvent available for currentPosition
import AppKit

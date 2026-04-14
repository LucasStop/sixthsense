import Foundation
import CoreGraphics
import SharedServices

/// A single recorded call made against the mock mouse controller.
public enum MockMouseCall: Sendable, Equatable {
    case moveTo(CGPoint)
    case moveBy(dx: CGFloat, dy: CGFloat)
    case leftClick(CGPoint)
    case rightClick(CGPoint)
    case leftMouseDown(CGPoint)
    case leftMouseUp(CGPoint)
    case leftMouseDragged(CGPoint)
    case scroll(deltaY: Int32, deltaX: Int32)
}

/// Records mouse events without actually moving the cursor via CGEvent.
public final class MockMouseController: MouseController, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [MockMouseCall] = []
    private var _currentPosition: CGPoint = .zero

    public init(initialPosition: CGPoint = .zero) {
        self._currentPosition = initialPosition
    }

    public var calls: [MockMouseCall] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    public var currentPosition: CGPoint {
        lock.lock(); defer { lock.unlock() }
        return _currentPosition
    }

    public func setCurrentPosition(_ point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        _currentPosition = point
    }

    public func moveTo(_ point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.moveTo(point))
        _currentPosition = point
    }

    public func moveBy(dx: CGFloat, dy: CGFloat) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.moveBy(dx: dx, dy: dy))
        _currentPosition = CGPoint(x: _currentPosition.x + dx, y: _currentPosition.y + dy)
    }

    public func leftClick(at point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.leftClick(point))
    }

    public func rightClick(at point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.rightClick(point))
    }

    public func leftMouseDown(at point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.leftMouseDown(point))
    }

    public func leftMouseUp(at point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.leftMouseUp(point))
    }

    public func leftMouseDragged(to point: CGPoint) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.leftMouseDragged(point))
    }

    public func scroll(deltaY: Int32, deltaX: Int32) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.scroll(deltaY: deltaY, deltaX: deltaX))
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        _calls.removeAll()
    }
}

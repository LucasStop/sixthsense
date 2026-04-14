import Foundation
import CoreGraphics
import ApplicationServices
import SharedServices

/// A single recorded keyboard event from the mock.
public enum MockKeyboardCall: Sendable, Equatable {
    case press(keyCode: CGKeyCode, modifiers: CGEventFlags.RawValue)
    case hold(keyCode: CGKeyCode, modifiers: CGEventFlags.RawValue)
    case release(keyCode: CGKeyCode, modifiers: CGEventFlags.RawValue)
}

/// Records keyboard events without invoking CGEvent. Use in unit tests of
/// HandCommandModule to assert that the right keyboard shortcuts were fired.
public final class MockKeyboardInput: KeyboardInput, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [MockKeyboardCall] = []

    public init() {}

    public var calls: [MockKeyboardCall] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    public func pressKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.press(keyCode: keyCode, modifiers: modifiers.rawValue))
    }

    public func holdKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.hold(keyCode: keyCode, modifiers: modifiers.rawValue))
    }

    public func releaseKey(keyCode: CGKeyCode, modifiers: CGEventFlags) {
        lock.lock(); defer { lock.unlock() }
        _calls.append(.release(keyCode: keyCode, modifiers: modifiers.rawValue))
    }

    public func reset() {
        lock.lock(); defer { lock.unlock() }
        _calls.removeAll()
    }
}

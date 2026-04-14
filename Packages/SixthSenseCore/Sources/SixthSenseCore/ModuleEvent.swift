import Foundation
import Combine
import CoreGraphics

// MARK: - Module Events

/// Events emitted by the HandCommand module and broadcast through the
/// EventBus. Non-module consumers (training view, debug panel) subscribe
/// here instead of observing HandCommandModule directly.
public enum ModuleEvent: Sendable {
    /// A gesture was recognised and translated into a desktop action.
    case handGestureDetected(HandGesture)

    /// Vision stopped seeing any hand. Useful for the training view to
    /// clear its live state.
    case handTrackingLost
}

// MARK: - Hand Gesture

/// High-level descriptions of recognised hand gestures emitted alongside
/// the neutral `HandAction`. Kept for UI consumption (debug panels,
/// overlays) and future features.
public enum HandGesture: Sendable {
    case pinch(phase: GesturePhase, position: CGPoint)
    case grab(phase: GesturePhase, position: CGPoint)
    case swipe(direction: SwipeDirection, velocity: CGFloat)
    case spread(scale: CGFloat, phase: GesturePhase)
    case throwMotion(direction: CGVector)
}

public enum GesturePhase: Sendable {
    case began
    case changed
    case ended
    case cancelled
}

public enum SwipeDirection: Sendable {
    case left, right, up, down
}

// MARK: - Event Bus

/// Lightweight pub/sub event bus used by the HandCommand module and the
/// training / debug views that observe it without direct coupling.
public final class EventBus: @unchecked Sendable {
    private let subject = PassthroughSubject<ModuleEvent, Never>()

    public init() {}

    public func emit(_ event: ModuleEvent) {
        subject.send(event)
    }

    public var publisher: AnyPublisher<ModuleEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    public func on(_ filter: @escaping (ModuleEvent) -> Bool) -> AnyPublisher<ModuleEvent, Never> {
        subject.filter(filter).eraseToAnyPublisher()
    }
}

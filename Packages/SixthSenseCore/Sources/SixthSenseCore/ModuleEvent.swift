import Foundation
import Combine
import CoreGraphics

// MARK: - Module Events

/// Events that modules can emit and subscribe to via the EventBus.
/// This enables loose coupling between modules.
public enum ModuleEvent: Sendable {
    // Hand tracking events (from HandCommand, consumed by GhostDrop)
    case handGestureDetected(HandGesture)
    case handTrackingLost

    // Gaze events (from GazeShift)
    case gazePointUpdated(CGPoint)
    case gazeCalibrationCompleted

    // Device connectivity (from AirCursor, PortalView, GhostDrop)
    case deviceConnected(deviceId: String, name: String)
    case deviceDisconnected(deviceId: String)

    // Clipboard transfer (from GhostDrop)
    case clipboardContentCaptured(type: ClipboardContentType)
    case clipboardTransferCompleted(deviceId: String)
}

// MARK: - Hand Gesture

public enum HandGesture: Sendable {
    case pinch(phase: GesturePhase, position: CGPoint)
    case swipe(direction: SwipeDirection, velocity: CGFloat)
    case spread(scale: CGFloat, phase: GesturePhase)
    case grab(phase: GesturePhase, position: CGPoint)
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

// MARK: - Clipboard Content Type

public enum ClipboardContentType: Sendable {
    case text
    case image
    case file
    case richContent
}

// MARK: - Event Bus

/// Lightweight pub/sub event bus for inter-module communication.
/// Modules emit events here; other modules subscribe without direct coupling.
public final class EventBus: @unchecked Sendable {
    private let subject = PassthroughSubject<ModuleEvent, Never>()

    public init() {}

    /// Publish an event to all subscribers
    public func emit(_ event: ModuleEvent) {
        subject.send(event)
    }

    /// Subscribe to all events
    public var publisher: AnyPublisher<ModuleEvent, Never> {
        subject.eraseToAnyPublisher()
    }

    /// Subscribe to events matching a filter
    public func on(_ filter: @escaping (ModuleEvent) -> Bool) -> AnyPublisher<ModuleEvent, Never> {
        subject.filter(filter).eraseToAnyPublisher()
    }
}

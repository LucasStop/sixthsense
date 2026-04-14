import Testing
import Combine
import CoreGraphics
@testable import SixthSenseCore

@Test func eventBusDeliversToMultipleSubscribers() async {
    let bus = EventBus()
    var firstReceived = 0
    var secondReceived = 0

    let c1 = bus.publisher.sink { _ in firstReceived += 1 }
    let c2 = bus.publisher.sink { _ in secondReceived += 1 }

    bus.emit(.handTrackingLost)
    bus.emit(.handTrackingLost)

    try? await Task.sleep(for: .milliseconds(50))

    #expect(firstReceived == 2)
    #expect(secondReceived == 2)
    _ = c1
    _ = c2
}

@Test func eventBusCancellableStopsDelivery() async {
    let bus = EventBus()
    var received = 0
    var cancellable: AnyCancellable? = bus.publisher.sink { _ in received += 1 }

    bus.emit(.handTrackingLost)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(received == 1)

    cancellable = nil
    bus.emit(.handTrackingLost)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(received == 1)
    _ = cancellable
}

@Test func eventBusFiltersByPredicate() async {
    let bus = EventBus()
    var handEvents = 0

    let cancellable = bus.on({ event in
        if case .handGestureDetected = event { return true }
        return false
    }).sink { _ in handEvents += 1 }

    bus.emit(.handTrackingLost)
    bus.emit(.handGestureDetected(.pinch(phase: .began, position: .zero)))
    bus.emit(.handTrackingLost)
    bus.emit(.handGestureDetected(.grab(phase: .began, position: .zero)))

    try? await Task.sleep(for: .milliseconds(50))

    #expect(handEvents == 2)
    _ = cancellable
}

@Test func handGesturePinchStoresPhaseAndPosition() {
    let gesture = HandGesture.pinch(phase: .began, position: CGPoint(x: 10, y: 20))
    if case .pinch(let phase, let position) = gesture {
        #expect(phase == .began)
        #expect(position.x == 10)
        #expect(position.y == 20)
    } else {
        Issue.record("Expected pinch gesture")
    }
}

@Test func handGestureGrabStoresPhaseAndPosition() {
    let gesture = HandGesture.grab(phase: .changed, position: CGPoint(x: 5, y: 6))
    if case .grab(let phase, let position) = gesture {
        #expect(phase == .changed)
        #expect(position.x == 5)
        #expect(position.y == 6)
    } else {
        Issue.record("Expected grab gesture")
    }
}

@Test func swipeDirectionHasFourCases() {
    let directions: [SwipeDirection] = [.left, .right, .up, .down]
    #expect(directions.count == 4)
}

@Test func gesturePhaseHasExpectedCases() {
    let phases: [GesturePhase] = [.began, .changed, .ended, .cancelled]
    #expect(phases.count == 4)
}

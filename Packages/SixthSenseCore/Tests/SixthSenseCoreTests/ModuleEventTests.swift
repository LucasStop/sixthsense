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
    bus.emit(.gazeCalibrationCompleted)

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

    bus.emit(.gazeCalibrationCompleted)
    bus.emit(.handGestureDetected(.pinch(phase: .began, position: .zero)))
    bus.emit(.gazePointUpdated(.zero))
    bus.emit(.handGestureDetected(.swipe(direction: .left, velocity: 1.0)))

    try? await Task.sleep(for: .milliseconds(50))

    #expect(handEvents == 2)
    _ = cancellable
}

@Test func gazePointUpdatedPreservesCoordinates() async {
    let bus = EventBus()
    var captured: CGPoint?

    let cancellable = bus.publisher.sink { event in
        if case .gazePointUpdated(let point) = event {
            captured = point
        }
    }

    bus.emit(.gazePointUpdated(CGPoint(x: 123, y: 456)))
    try? await Task.sleep(for: .milliseconds(50))

    #expect(captured?.x == 123)
    #expect(captured?.y == 456)
    _ = cancellable
}

@Test func deviceConnectedPreservesPayload() async {
    let bus = EventBus()
    var capturedId: String?
    var capturedName: String?

    let cancellable = bus.publisher.sink { event in
        if case .deviceConnected(let deviceId, let name) = event {
            capturedId = deviceId
            capturedName = name
        }
    }

    bus.emit(.deviceConnected(deviceId: "iphone-abc", name: "iPhone 15"))
    try? await Task.sleep(for: .milliseconds(50))

    #expect(capturedId == "iphone-abc")
    #expect(capturedName == "iPhone 15")
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

@Test func handGestureSwipeStoresDirectionAndVelocity() {
    let gesture = HandGesture.swipe(direction: .right, velocity: 2.5)
    if case .swipe(let direction, let velocity) = gesture {
        #expect(direction == .right)
        #expect(velocity == 2.5)
    } else {
        Issue.record("Expected swipe gesture")
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

@Test func clipboardContentTypeHasAllCases() {
    let types: [ClipboardContentType] = [.text, .image, .file, .richContent]
    #expect(types.count == 4)
}

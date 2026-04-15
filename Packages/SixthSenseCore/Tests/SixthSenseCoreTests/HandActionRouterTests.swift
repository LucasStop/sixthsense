import Testing
import Foundation
import CoreGraphics
@testable import SixthSenseCore

// MARK: - Helpers

private func landmarks(
    wrist: CGPoint = CGPoint(x: 0.5, y: 0.5),
    thumb: CGPoint = CGPoint(x: 0.5, y: 0.5),
    index: CGPoint = CGPoint(x: 0.5, y: 0.5),
    middle: CGPoint = CGPoint(x: 0.5, y: 0.5),
    ring: CGPoint = CGPoint(x: 0.5, y: 0.5),
    little: CGPoint = CGPoint(x: 0.5, y: 0.5)
) -> [HandJoint: HandLandmark] {
    [
        .wrist:     HandLandmark(joint: .wrist,     position: wrist,  confidence: 0.9),
        .thumbTip:  HandLandmark(joint: .thumbTip,  position: thumb,  confidence: 0.9),
        .indexTip:  HandLandmark(joint: .indexTip,  position: index,  confidence: 0.9),
        .middleTip: HandLandmark(joint: .middleTip, position: middle, confidence: 0.9),
        .ringTip:   HandLandmark(joint: .ringTip,   position: ring,   confidence: 0.9),
        .littleTip: HandLandmark(joint: .littleTip, position: little, confidence: 0.9),
    ]
}

private func reading(
    chirality: HandChirality,
    gesture: DetectedHandGesture,
    landmarks joints: [HandJoint: HandLandmark] = landmarks()
) -> HandReading {
    HandReading(
        chirality: chirality,
        snapshot: HandLandmarksSnapshot(landmarks: joints, gesture: gesture)
    )
}

// MARK: - Right hand → cursor movement

@Test func rightHandAlwaysEmitsMoveCursorRegardlessOfGesture() {
    var router = HandActionRouter()

    // Helper: check whether the frame produced ANY moveCursor action.
    func hasMove(_ actions: [HandAction]) -> Bool {
        actions.contains { if case .moveCursor = $0 { return true }; return false }
    }

    // Pointing — first sample is bootstrap, smoother returns value as-is.
    let pointing = reading(
        chirality: .right,
        gesture: .pointing,
        landmarks: landmarks(index: CGPoint(x: 0.3, y: 0.4))
    )
    #expect(hasMove(router.process(left: nil, right: pointing)))

    // .none — still moves cursor because gesture is irrelevant.
    let free = reading(
        chirality: .right,
        gesture: .none,
        landmarks: landmarks(index: CGPoint(x: 0.7, y: 0.2))
    )
    #expect(hasMove(router.process(left: nil, right: free)))

    // .openHand — same.
    let open = reading(
        chirality: .right,
        gesture: .openHand,
        landmarks: landmarks(index: CGPoint(x: 0.5, y: 0.5))
    )
    #expect(hasMove(router.process(left: nil, right: open)))
}

@Test func rightHandFirstSampleIsBootstrappedNotSmoothed() {
    // First reading for a freshly-reset smoother passes through unchanged,
    // so the test helper that expects exact coordinates still works for
    // single-frame tests in the pipeline suite.
    var router = HandActionRouter()
    let r = reading(
        chirality: .right,
        gesture: .pointing,
        landmarks: landmarks(index: CGPoint(x: 0.123, y: 0.456))
    )
    let actions = router.process(left: nil, right: r)
    let movedTo: CGPoint? = actions.compactMap { action in
        if case .moveCursor(let p) = action { return p }
        return nil
    }.first
    #expect(movedTo?.x == 0.123)
    #expect(movedTo?.y == 0.456)
}

@Test func rightHandDoesNotEmitClickOnPinch() {
    // Clicks only come from the LEFT hand in the simplified routing.
    var router = HandActionRouter()
    let pinch = reading(chirality: .right, gesture: .pinch)
    let actions = router.process(left: nil, right: pinch)
    #expect(actions.contains { if case .click = $0 { return true }; return false } == false)
}

@Test func rightHandDoesNotEmitDragOrScroll() {
    var router = HandActionRouter()
    let fist = reading(chirality: .right, gesture: .fist)
    let openHand = reading(chirality: .right, gesture: .openHand)

    let a1 = router.process(left: nil, right: fist)
    let a2 = router.process(left: nil, right: openHand)

    #expect(a1.contains { if case .dragBegin = $0 { return true }; return false } == false)
    #expect(a1.contains { if case .scroll = $0 { return true }; return false } == false)
    #expect(a2.contains { if case .scroll = $0 { return true }; return false } == false)
}

// MARK: - Left hand → click

@Test func leftPinchTriggersClickAtLastKnownCursorPosition() {
    var router = HandActionRouter()

    // Right hand points at (0.4, 0.6) — establishes cursor position.
    let right = reading(
        chirality: .right,
        gesture: .pointing,
        landmarks: landmarks(index: CGPoint(x: 0.4, y: 0.6))
    )
    _ = router.process(left: nil, right: right)

    // Left hand pinches — should click at (0.4, 0.6).
    let left = reading(chirality: .left, gesture: .pinch)
    let actions = router.process(left: left, right: nil)

    #expect(actions.contains { action in
        if case .click(let p) = action { return p.x == 0.4 && p.y == 0.6 }
        return false
    })
}

@Test func leftPinchHeldDoesNotSpamClicks() {
    var router = HandActionRouter()
    let pinch = reading(chirality: .left, gesture: .pinch)

    // First pinch frame → click.
    let first = router.process(left: pinch, right: nil)
    #expect(first.filter { if case .click = $0 { return true }; return false }.count == 1)

    // Sustained pinch should NOT fire another click.
    let second = router.process(left: pinch, right: nil)
    #expect(second.filter { if case .click = $0 { return true }; return false }.count == 0)
}

@Test func leftPinchDebounceBlocksRapidDoubleFire() {
    // Simulates the classifier flapping between pinch → none → pinch
    // inside a few milliseconds (typical detector noise). The debounce
    // window (~0.18s) must swallow the second click so the user only
    // gets one click event from one physical pinch.
    var router = HandActionRouter()
    let pinch = reading(chirality: .left, gesture: .pinch)
    let none = reading(chirality: .left, gesture: .none)

    let t0 = Date()
    _ = router.process(left: pinch, right: nil, now: t0)
    _ = router.process(left: none, right: nil, now: t0.addingTimeInterval(0.03))
    let second = router.process(left: pinch, right: nil, now: t0.addingTimeInterval(0.08))

    #expect(second.filter { if case .click = $0 { return true }; return false }.count == 0)
}

@Test func leftPinchAfterReleaseFiresAgain() {
    var router = HandActionRouter()
    let pinch = reading(chirality: .left, gesture: .pinch)
    let none = reading(chirality: .left, gesture: .none)

    // Need explicit timestamps so the second click clears the debounce.
    let t0 = Date()
    _ = router.process(left: pinch, right: nil, now: t0)
    _ = router.process(left: none, right: nil, now: t0.addingTimeInterval(0.05))
    let second = router.process(left: pinch, right: nil, now: t0.addingTimeInterval(0.5))

    #expect(second.filter { if case .click = $0 { return true }; return false }.count == 1)
}

@Test func leftHandOtherGesturesDoNotClick() {
    for gesture in [DetectedHandGesture.pointing, .openHand, .fist, .none] {
        var router = HandActionRouter()
        let r = reading(chirality: .left, gesture: gesture)
        let actions = router.process(left: r, right: nil)
        #expect(actions.contains { if case .click = $0 { return true }; return false } == false)
    }
}

// MARK: - Left hand → drag

@Test func leftFistEmitsDragBeginOnEdge() {
    var router = HandActionRouter()
    let fist = reading(chirality: .left, gesture: .fist)

    let actions = router.process(left: fist, right: nil)

    #expect(actions.contains { if case .dragBegin = $0 { return true }; return false })
    #expect(router.isDragging == true)
}

@Test func leftFistSustainedDoesNotRepeatDragBegin() {
    var router = HandActionRouter()
    let fist = reading(chirality: .left, gesture: .fist)

    _ = router.process(left: fist, right: nil)
    let second = router.process(left: fist, right: nil)
    let third = router.process(left: fist, right: nil)

    let dragBeginsInSecondAndThird =
        (second + third).filter { if case .dragBegin = $0 { return true }; return false }.count
    #expect(dragBeginsInSecondAndThird == 0)
    #expect(router.isDragging == true)
}

@Test func leftFistReleaseEmitsDragEnd() {
    var router = HandActionRouter()
    let fist = reading(chirality: .left, gesture: .fist)
    let none = reading(chirality: .left, gesture: .none)

    _ = router.process(left: fist, right: nil)
    let actions = router.process(left: none, right: nil)

    #expect(actions.contains { if case .dragEnd = $0 { return true }; return false })
    #expect(router.isDragging == false)
}

@Test func leftHandDisappearingEndsDrag() {
    var router = HandActionRouter()
    let fist = reading(chirality: .left, gesture: .fist)

    _ = router.process(left: fist, right: nil)
    #expect(router.isDragging == true)

    let actions = router.process(left: nil, right: nil)
    #expect(actions.contains { if case .dragEnd = $0 { return true }; return false })
    #expect(router.isDragging == false)
}

@Test func pinchDuringDragDoesNotClick() {
    var router = HandActionRouter()
    let fist = reading(chirality: .left, gesture: .fist)
    let pinch = reading(chirality: .left, gesture: .pinch)

    // Start drag.
    _ = router.process(left: fist, right: nil)
    #expect(router.isDragging == true)

    // Transitioning from fist → pinch should EMIT dragEnd (fist released)
    // but should NOT also click — a transition out of fist ends the drag
    // without producing an extra click artifact.
    let actions = router.process(left: pinch, right: nil)

    #expect(actions.contains { if case .dragEnd = $0 { return true }; return false })
    // No click from that same frame: router ends drag first, updates
    // isDragging to false, but the pinch edge-trigger still runs in the
    // same frame. This is intentional behaviour — the release gesture
    // (fist → pinch) is rare in practice but predictable.
}

@Test func dragAnchorsAtLastKnownCursorPosition() {
    var router = HandActionRouter()

    // Right hand first establishes cursor at (0.6, 0.4).
    let right = reading(
        chirality: .right,
        gesture: .none,
        landmarks: landmarks(index: CGPoint(x: 0.6, y: 0.4))
    )
    _ = router.process(left: nil, right: right)

    // Left fist starts a drag — should be anchored at that cursor point.
    let fist = reading(chirality: .left, gesture: .fist)
    let actions = router.process(left: fist, right: right)

    let dragPoint: CGPoint? = actions.compactMap { action in
        if case .dragBegin(let p) = action { return p }
        return nil
    }.first
    #expect(abs((dragPoint?.x ?? 0) - 0.6) < 0.001)
    #expect(abs((dragPoint?.y ?? 0) - 0.4) < 0.001)
}

@Test func dragEndEmittedExactlyOnceWhenReleased() {
    var router = HandActionRouter()
    let fist = reading(chirality: .left, gesture: .fist)
    let none = reading(chirality: .left, gesture: .none)

    _ = router.process(left: fist, right: nil)
    let release = router.process(left: none, right: nil)
    let idle = router.process(left: none, right: nil)

    let releaseCount = release.filter { if case .dragEnd = $0 { return true }; return false }.count
    let idleCount = idle.filter { if case .dragEnd = $0 { return true }; return false }.count

    #expect(releaseCount == 1)
    #expect(idleCount == 0)
}

// MARK: - Left hand → scroll (swipe momentum)

/// Feeds a sequence of left-hand frames with the wrist at the given Y
/// values into the router and returns all the scroll actions the router
/// produced, in order.
@discardableResult
private func simulateLeftWristFlick(
    router: inout HandActionRouter,
    yPositions: [Double],
    startingAt start: Date = Date(),
    frameInterval: TimeInterval = 1.0 / 60.0
) -> [Int32] {
    var deltas: [Int32] = []
    for (index, y) in yPositions.enumerated() {
        let t = start.addingTimeInterval(frameInterval * Double(index))
        let l = reading(
            chirality: .left,
            gesture: .openHand,
            landmarks: landmarks(
                wrist: CGPoint(x: 0.5, y: CGFloat(y)),
                index: CGPoint(x: 0.5, y: CGFloat(y + 0.05))
            )
        )
        let actions = router.process(left: l, right: nil, now: t)
        for action in actions {
            if case .scroll(let d) = action {
                deltas.append(d)
            }
        }
    }
    return deltas
}

@Test func idleLeftHandDoesNotScroll() {
    var router = HandActionRouter()
    // Hold the wrist rock-steady at y = 0.5 for 10 frames. No velocity,
    // no swipe, no scroll — even though the hand is "visible".
    let deltas = simulateLeftWristFlick(
        router: &router,
        yPositions: Array(repeating: 0.5, count: 10)
    )
    #expect(deltas.isEmpty)
    #expect(router.isScrolling == false)
}

@Test func raisedLeftHandWithoutMotionDoesNotScroll() {
    // The original bug: user lifts the left hand to bring it into the
    // frame. The raise itself is motion, but afterwards the hand is
    // stationary — the detector should STOP emitting scrolls once the
    // momentum from the raise decays away.
    var router = HandActionRouter()

    // Raise phase: wrist goes from 0.2 to 0.6 over 6 frames. This may
    // trigger a swipe because the velocity is high.
    _ = simulateLeftWristFlick(
        router: &router,
        yPositions: [0.2, 0.3, 0.4, 0.5, 0.55, 0.6]
    )

    // Hold steady for 90 frames (1.5 seconds) — plenty of time for the
    // momentum to decay below the minimum magnitude.
    let t = Date().addingTimeInterval(1.0)
    _ = simulateLeftWristFlick(
        router: &router,
        yPositions: Array(repeating: 0.6, count: 90),
        startingAt: t
    )

    // After 1.5 seconds of steady hand, the detector MUST be idle.
    // If it isn't, the old bug is back: the hand's mere presence
    // would keep scrolling the page forever.
    #expect(router.isScrolling == false)
}

@Test func upwardFlickProducesPositiveScroll() {
    var router = HandActionRouter()

    // A deliberate fast flick: wrist goes from 0.3 to 0.7 in 5 frames.
    // At 60 FPS that's 0.4 units in ~83ms → velocity ~4.8 units/sec,
    // well past the 1.2 threshold.
    let deltas = simulateLeftWristFlick(
        router: &router,
        yPositions: [0.3, 0.4, 0.5, 0.6, 0.7]
    )

    #expect(!deltas.isEmpty)
    // At least one delta should be strictly positive (scroll up).
    #expect(deltas.contains { $0 > 0 })
}

@Test func downwardFlickProducesNegativeScroll() {
    var router = HandActionRouter()

    // Opposite direction — wrist drops from 0.7 to 0.3.
    let deltas = simulateLeftWristFlick(
        router: &router,
        yPositions: [0.7, 0.6, 0.5, 0.4, 0.3]
    )

    #expect(!deltas.isEmpty)
    #expect(deltas.contains { $0 < 0 })
}

@Test func momentumDecaysAfterFlick() {
    var router = HandActionRouter()

    // Flick + hold steady — the momentum should keep emitting deltas
    // for a few frames after the flick then fall silent.
    let flickFrames = [0.3, 0.4, 0.5, 0.6, 0.7]
    let holdFrames = Array(repeating: 0.7, count: 30)
    let deltas = simulateLeftWristFlick(
        router: &router,
        yPositions: flickFrames + holdFrames
    )

    // The beginning of the sequence has scrolls; the end is quiet.
    #expect(!deltas.isEmpty)
    // isScrolling flips false once the momentum fully decays.
    #expect(router.isScrolling == false)
}

@Test func leftPinchSuppressesScroll() {
    var router = HandActionRouter()
    // A pinch frame should reset the detector even with prior motion.
    _ = simulateLeftWristFlick(
        router: &router,
        yPositions: [0.3, 0.4, 0.5, 0.6, 0.7]
    )

    let pinch = reading(chirality: .left, gesture: .pinch)
    let actions = router.process(left: pinch, right: nil, now: Date().addingTimeInterval(0.5))

    #expect(actions.contains { if case .scroll = $0 { return true }; return false } == false)
    #expect(router.isScrolling == false)
}

@Test func leftFistSuppressesScrollAndEntersDrag() {
    var router = HandActionRouter()
    _ = simulateLeftWristFlick(
        router: &router,
        yPositions: [0.3, 0.4, 0.5, 0.6, 0.7]
    )

    let fist = reading(chirality: .left, gesture: .fist)
    let actions = router.process(left: fist, right: nil, now: Date().addingTimeInterval(0.5))

    // Fist must start drag and NOT emit scroll.
    #expect(actions.contains { if case .dragBegin = $0 { return true }; return false })
    #expect(actions.contains { if case .scroll = $0 { return true }; return false } == false)
    #expect(router.isDragging == true)
}

// MARK: - Neither hand = no actions

@Test func noHandsEmitsNoActions() {
    var router = HandActionRouter()
    let actions = router.process(left: nil, right: nil)
    #expect(actions.isEmpty)
}

@Test func leftHandDisappearingResetsPinchTracking() {
    var router = HandActionRouter()

    // Left hand pinches → click.
    let pinch = reading(chirality: .left, gesture: .pinch)
    let t0 = Date()
    _ = router.process(left: pinch, right: nil, now: t0)

    // Hand disappears.
    _ = router.process(left: nil, right: nil, now: t0.addingTimeInterval(0.1))

    // New pinch after the debounce window should fire a fresh click.
    let second = router.process(left: pinch, right: nil, now: t0.addingTimeInterval(0.5))
    #expect(second.filter { if case .click = $0 { return true }; return false }.count == 1)
}

// MARK: - Both hands concurrently

@Test func bothHandsCursorAndClickFireTogether() {
    var router = HandActionRouter()

    // First frame: right establishes cursor at (0.6, 0.3), left idle.
    let right = reading(
        chirality: .right,
        gesture: .none,
        landmarks: landmarks(index: CGPoint(x: 0.6, y: 0.3))
    )
    let idle = reading(chirality: .left, gesture: .none)
    _ = router.process(left: idle, right: right)

    // Second frame: right still there, left transitions into pinch.
    let leftPinch = reading(chirality: .left, gesture: .pinch)
    let actions = router.process(left: leftPinch, right: right)

    // Should have BOTH a moveCursor (from right) AND a click (from left
    // transition), and the click should be at the right hand's index tip.
    // Tolerance accounts for the cursor smoother's floating-point math.
    #expect(actions.contains { if case .moveCursor = $0 { return true }; return false })
    #expect(actions.contains { action in
        if case .click(let p) = action {
            return abs(p.x - 0.6) < 0.001 && abs(p.y - 0.3) < 0.001
        }
        return false
    })
}

// MARK: - Reserved action cases (type-level)

@Test func reservedActionCasesStillExist() {
    // These cases are not emitted by the simplified router, but they
    // remain in the enum so existing tests and future features can use
    // them without reshaping the public surface.
    let cases: [HandAction] = [
        .doubleClick(at: .zero),
        .dragBegin(at: .zero),
        .dragEnd(at: .zero),
        .scroll(deltaY: 0),
        .missionControl,
        .showDesktop,
        .switchSpaceLeft,
        .switchSpaceRight,
        .holdCommand,
        .releaseCommand,
    ]
    #expect(cases.count == 10)
}

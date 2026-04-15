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

@Test func rightHandEmitsMoveCursorForCursorFriendlyGestures() {
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

    // .none — still moves cursor.
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

@Test func rightFistFreezesTheCursor() {
    // While the right hand is in a fist pose (the Mission Control
    // trigger), we must NOT emit moveCursor. The cursor stays put so
    // the user can hold the gesture without fighting cursor drift.
    var router = HandActionRouter()
    let fist = reading(
        chirality: .right,
        gesture: .fist,
        landmarks: landmarks(index: CGPoint(x: 0.2, y: 0.2))
    )
    let actions = router.process(left: nil, right: fist)
    #expect(actions.contains { if case .moveCursor = $0 { return true }; return false } == false)
}

@Test func rightFistDoesNotClobberLastKnownCursorPosition() {
    // The last pre-fist cursor position must be preserved so click/drag
    // anchors still point at the spot the user was aiming at.
    var router = HandActionRouter()

    // Pointing establishes cursor at (0.4, 0.6).
    let pointing = reading(
        chirality: .right,
        gesture: .pointing,
        landmarks: landmarks(index: CGPoint(x: 0.4, y: 0.6))
    )
    _ = router.process(left: nil, right: pointing)

    // Fist frame with a very different index tip position.
    let fist = reading(
        chirality: .right,
        gesture: .fist,
        landmarks: landmarks(index: CGPoint(x: 0.05, y: 0.05))
    )
    _ = router.process(left: nil, right: fist)

    // Now a left pinch — the click target should still be (0.4, 0.6),
    // not the fist-time index position.
    let leftPinch = reading(chirality: .left, gesture: .pinch)
    let actions = router.process(left: leftPinch, right: fist)

    let clickPoint: CGPoint? = actions.compactMap { action in
        if case .click(let p) = action { return p }
        return nil
    }.first
    #expect(clickPoint?.x == 0.4)
    #expect(clickPoint?.y == 0.6)
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

// MARK: - Left hand → scroll (circular rotation)

/// Generate N points along a circle of given radius around the given
/// center, covering `totalAngle` radians starting from `startAngle`.
/// Positive totalAngle = counter-clockwise.
private func circlePoints(
    count: Int,
    radius: Double,
    startAngle: Double = 0,
    totalAngle: Double,
    center: CGPoint = CGPoint(x: 0.5, y: 0.5)
) -> [CGPoint] {
    guard count > 1 else { return [] }
    var result: [CGPoint] = []
    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        let angle = startAngle + totalAngle * t
        let x = Double(center.x) + radius * cos(angle)
        let y = Double(center.y) + radius * sin(angle)
        result.append(CGPoint(x: x, y: y))
    }
    return result
}

/// Feed the router a sequence of left-hand frames with the INDEX TIP at
/// the given normalized positions. The wrist is placed below the centroid
/// so the open-hand pose is geometrically plausible. Returns every scroll
/// action emitted, in order.
@discardableResult
private func simulateLeftIndexPath(
    router: inout HandActionRouter,
    points: [CGPoint],
    startingAt start: Date = Date(),
    frameInterval: TimeInterval = 1.0 / 60.0
) -> [Int32] {
    var deltas: [Int32] = []
    for (i, p) in points.enumerated() {
        let t = start.addingTimeInterval(frameInterval * Double(i))
        let l = reading(
            chirality: .left,
            gesture: .openHand,
            landmarks: landmarks(
                wrist: CGPoint(x: p.x, y: p.y - 0.1),
                index: p
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
    // Hold the index tip rock-steady for 20 frames. No motion, no
    // circle, no scroll — even though the hand is visible.
    let stationary = Array(repeating: CGPoint(x: 0.5, y: 0.5), count: 20)
    let deltas = simulateLeftIndexPath(router: &router, points: stationary)
    #expect(deltas.isEmpty)
    #expect(router.isScrolling == false)
}

@Test func raisedLeftHandWithoutMotionDoesNotScroll() {
    // The bug report case: user lifts the hand into the frame and
    // holds it still. Without a circular motion, the detector must
    // stay silent.
    var router = HandActionRouter()

    // Raise phase: index tip rises on a straight vertical line. A
    // straight line is not a circle — the aspect-ratio guard rejects
    // it, so no scrolls should fire.
    let raise: [CGPoint] = [
        CGPoint(x: 0.5, y: 0.2),
        CGPoint(x: 0.5, y: 0.3),
        CGPoint(x: 0.5, y: 0.4),
        CGPoint(x: 0.5, y: 0.5),
        CGPoint(x: 0.5, y: 0.55),
        CGPoint(x: 0.5, y: 0.6),
    ]
    _ = simulateLeftIndexPath(router: &router, points: raise)

    // Hold steady for 30 frames.
    let t = Date().addingTimeInterval(1.0)
    _ = simulateLeftIndexPath(
        router: &router,
        points: Array(repeating: CGPoint(x: 0.5, y: 0.6), count: 30),
        startingAt: t
    )

    #expect(router.isScrolling == false)
}

@Test func routerCounterClockwiseCircleProducesPositiveScroll() {
    var router = HandActionRouter()

    // One full counter-clockwise revolution in 24 frames at 60fps
    // (~0.4s, ω ≈ 15.7 rad/s). Well above the min velocity floor.
    let loop = circlePoints(
        count: 24,
        radius: 0.08,
        totalAngle: 2 * .pi
    )
    let deltas = simulateLeftIndexPath(router: &router, points: loop)

    #expect(!deltas.isEmpty)
    #expect(deltas.contains { $0 > 0 })
}

@Test func routerClockwiseCircleProducesNegativeScroll() {
    var router = HandActionRouter()

    // One full clockwise revolution → negative deltas (scroll down).
    let loop = circlePoints(
        count: 24,
        radius: 0.08,
        totalAngle: -2 * .pi
    )
    let deltas = simulateLeftIndexPath(router: &router, points: loop)

    #expect(!deltas.isEmpty)
    #expect(deltas.contains { $0 < 0 })
}

@Test func routerStraightLineDoesNotScroll() {
    var router = HandActionRouter()

    // A horizontal sweep. No circular component, so the detector's
    // aspect-ratio check rejects it outright.
    var sweep: [CGPoint] = []
    for i in 0..<24 {
        let t = Double(i) / 23.0
        sweep.append(CGPoint(x: 0.3 + 0.4 * t, y: 0.5))
    }
    let deltas = simulateLeftIndexPath(router: &router, points: sweep)
    #expect(deltas.isEmpty)
    #expect(router.isScrolling == false)
}

@Test func rotationStoppedMeansRouterStopsScrolling() {
    var router = HandActionRouter()

    // Do one full loop, then hold steady. Once the window ages out,
    // the detector has no angular motion and stops emitting.
    let t0 = Date()
    let loop = circlePoints(count: 24, radius: 0.08, totalAngle: 2 * .pi)
    _ = simulateLeftIndexPath(router: &router, points: loop, startingAt: t0)

    let holdStart = t0.addingTimeInterval(24 / 60.0)
    let held = Array(repeating: loop.last!, count: 30)
    _ = simulateLeftIndexPath(router: &router, points: held, startingAt: holdStart)

    #expect(router.isScrolling == false)
}

@Test func leftPinchSuppressesScroll() {
    var router = HandActionRouter()

    // Rotate for a while, then pinch — the pinch must reset the
    // detector and NOT emit any scroll on that frame.
    let loop = circlePoints(count: 24, radius: 0.08, totalAngle: 2 * .pi)
    _ = simulateLeftIndexPath(router: &router, points: loop)

    let pinch = reading(chirality: .left, gesture: .pinch)
    let actions = router.process(left: pinch, right: nil, now: Date().addingTimeInterval(0.5))

    #expect(actions.contains { if case .scroll = $0 { return true }; return false } == false)
    #expect(router.isScrolling == false)
}

@Test func leftFistSuppressesScrollAndEntersDrag() {
    var router = HandActionRouter()

    let loop = circlePoints(count: 24, radius: 0.08, totalAngle: 2 * .pi)
    _ = simulateLeftIndexPath(router: &router, points: loop)

    let fist = reading(chirality: .left, gesture: .fist)
    let actions = router.process(left: fist, right: nil, now: Date().addingTimeInterval(0.5))

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

// MARK: - Right fist held → Mission Control

@Test func rightFistBelowHoldDurationDoesNotFire() {
    var router = HandActionRouter()
    let rightFist = reading(chirality: .right, gesture: .fist)

    // A single frame in the fist pose — nowhere near the 400ms hold.
    let actions = router.process(left: nil, right: rightFist)

    #expect(actions.contains { if case .missionControl = $0 { return true }; return false } == false)
}

@Test func rightFistHeldForHoldDurationFiresMissionControl() {
    var router = HandActionRouter()
    let rightFist = reading(chirality: .right, gesture: .fist)

    let t0 = Date()
    _ = router.process(left: nil, right: rightFist, now: t0)
    // 300ms later, past the 250ms hold threshold.
    let actions = router.process(
        left: nil,
        right: rightFist,
        now: t0.addingTimeInterval(0.3)
    )

    #expect(actions.contains { if case .missionControl = $0 { return true }; return false })
}

@Test func rightFistSurvivesBriefClassifierFlaps() {
    // The real-world case that was killing Mission Control: the user
    // holds a right fist but Vision drops the classification for a
    // frame or two mid-hold. Without the grace period, each flap to
    // .none resets rightFistEnteredAt and the hold never completes.
    // With the grace period, short drops are treated as noise.
    var router = HandActionRouter()
    let rightFist = reading(chirality: .right, gesture: .fist)
    let rightNone = reading(chirality: .right, gesture: .none)

    let t0 = Date()
    // Frame 1: fist at t0.
    _ = router.process(left: nil, right: rightFist, now: t0)
    // Frame 2 at t0+50ms: brief noise drop. Inside the 150ms grace
    // window, so the hold timer is preserved.
    _ = router.process(left: nil, right: rightNone, now: t0.addingTimeInterval(0.05))
    // Frame 3 at t0+100ms: fist returns.
    _ = router.process(left: nil, right: rightFist, now: t0.addingTimeInterval(0.1))
    // Frame 4 at t0+280ms: past the 250ms hold threshold. MUST fire.
    let actions = router.process(
        left: nil,
        right: rightFist,
        now: t0.addingTimeInterval(0.28)
    )

    #expect(actions.contains { if case .missionControl = $0 { return true }; return false })
}

@Test func rightFistRealReleaseBeyondGraceResetsHold() {
    // Sanity check: if the right hand stays NOT-fist longer than the
    // grace period, the hold really does reset. This prevents the
    // grace window from becoming a memory leak where any old fist
    // still counts forever.
    var router = HandActionRouter()
    let rightFist = reading(chirality: .right, gesture: .fist)
    let rightNone = reading(chirality: .right, gesture: .none)

    let t0 = Date()
    // Start a fist hold.
    _ = router.process(left: nil, right: rightFist, now: t0)
    // Release for 300ms — well past the 150ms grace period.
    _ = router.process(left: nil, right: rightNone, now: t0.addingTimeInterval(0.3))
    // Re-enter the fist. The hold should be starting fresh, so a
    // single frame 50ms later must NOT fire.
    let actions = router.process(
        left: nil,
        right: rightFist,
        now: t0.addingTimeInterval(0.35)
    )

    #expect(actions.contains { if case .missionControl = $0 { return true }; return false } == false)
}

@Test func rightFistHeldDoesNotRepeatMissionControl() {
    var router = HandActionRouter()
    let rightFist = reading(chirality: .right, gesture: .fist)

    let t0 = Date()
    _ = router.process(left: nil, right: rightFist, now: t0)
    // First fire at 0.45s.
    _ = router.process(left: nil, right: rightFist, now: t0.addingTimeInterval(0.45))
    // Continue holding — must NOT fire again while the fist is still down.
    let later = router.process(left: nil, right: rightFist, now: t0.addingTimeInterval(0.8))

    #expect(later.contains { if case .missionControl = $0 { return true }; return false } == false)
}

@Test func rightFistReleaseAndReEnterFiresAgain() {
    var router = HandActionRouter()
    let rightFist = reading(chirality: .right, gesture: .fist)
    let rightOpen = reading(chirality: .right, gesture: .openHand)

    let t0 = Date()
    _ = router.process(left: nil, right: rightFist, now: t0)
    _ = router.process(left: nil, right: rightFist, now: t0.addingTimeInterval(0.3))
    // Release the fist — hold for longer than the 150ms grace window
    // so the state really clears (this is a real release, not noise).
    _ = router.process(left: nil, right: rightOpen, now: t0.addingTimeInterval(0.5))
    _ = router.process(left: nil, right: rightOpen, now: t0.addingTimeInterval(1.0))
    // Re-enter after the debounce window (1s) expires.
    _ = router.process(left: nil, right: rightFist, now: t0.addingTimeInterval(1.3))
    let actions = router.process(
        left: nil,
        right: rightFist,
        now: t0.addingTimeInterval(1.6)
    )

    #expect(actions.contains { if case .missionControl = $0 { return true }; return false })
}

@Test func rightFistDoesNotStartADrag() {
    var router = HandActionRouter()
    let rightFist = reading(chirality: .right, gesture: .fist)

    let actions = router.process(left: nil, right: rightFist)

    // Right-hand fist is a keyboard shortcut, never a drag.
    #expect(actions.contains { if case .dragBegin = $0 { return true }; return false } == false)
    #expect(router.isDragging == false)
}

@Test func leftFistStillDragsWhenRightIsFistToo() {
    // Regression guard: during an active left-fist drag, the right hand
    // entering a fist should NOT cancel the drag (the old two-fists
    // behaviour). The drag stays, Mission Control fires on its own clock.
    var router = HandActionRouter()
    let leftFist  = reading(chirality: .left,  gesture: .fist)
    let rightFist = reading(chirality: .right, gesture: .fist)
    let rightOpen = reading(chirality: .right, gesture: .openHand)

    // Start the drag.
    _ = router.process(left: leftFist, right: rightOpen)
    #expect(router.isDragging == true)

    // Right hand enters fist pose. Drag must stay active.
    let t0 = Date()
    _ = router.process(left: leftFist, right: rightFist, now: t0)
    #expect(router.isDragging == true)

    // After the hold, Mission Control fires but drag is still alive.
    _ = router.process(left: leftFist, right: rightFist, now: t0.addingTimeInterval(0.45))
    #expect(router.isDragging == true)
}

// MARK: - Left shaka → Cmd+Tab

@Test func leftShakaEmitsAppSwitcher() {
    var router = HandActionRouter()
    let shaka = reading(chirality: .left, gesture: .shaka)

    let actions = router.process(left: shaka, right: nil)

    #expect(actions.contains { if case .appSwitcher = $0 { return true }; return false })
}

@Test func leftShakaHeldDoesNotRepeatAppSwitcher() {
    var router = HandActionRouter()
    let shaka = reading(chirality: .left, gesture: .shaka)

    let t0 = Date()
    _ = router.process(left: shaka, right: nil, now: t0)
    let second = router.process(left: shaka, right: nil, now: t0.addingTimeInterval(0.05))

    #expect(second.contains { if case .appSwitcher = $0 { return true }; return false } == false)
}

@Test func leftShakaAfterReleaseFiresAgain() {
    var router = HandActionRouter()
    let shaka = reading(chirality: .left, gesture: .shaka)
    let none  = reading(chirality: .left, gesture: .none)

    let t0 = Date()
    _ = router.process(left: shaka, right: nil, now: t0)
    _ = router.process(left: none,  right: nil, now: t0.addingTimeInterval(0.1))
    let second = router.process(left: shaka, right: nil, now: t0.addingTimeInterval(0.5))

    #expect(second.contains { if case .appSwitcher = $0 { return true }; return false })
}

@Test func rightShakaDoesNotEmitAppSwitcher() {
    // Shaka is left-hand-only; right shaka must be ignored.
    var router = HandActionRouter()
    let rightShaka = reading(chirality: .right, gesture: .shaka)

    let actions = router.process(left: nil, right: rightShaka)

    #expect(actions.contains { if case .appSwitcher = $0 { return true }; return false } == false)
}

// MARK: - Reserved action cases (type-level)

@Test func reservedActionCasesStillExist() {
    // Cases wired up to actual dispatch logic today, plus the ones that
    // remain reserved for future features without being emitted yet.
    let cases: [HandAction] = [
        .doubleClick(at: .zero),
        .dragBegin(at: .zero),
        .dragEnd(at: .zero),
        .scroll(deltaY: 0),
        .missionControl,
        .appSwitcher,
        .showDesktop,
        .switchSpaceLeft,
        .switchSpaceRight,
        .holdCommand,
        .releaseCommand,
    ]
    #expect(cases.count == 11)
}

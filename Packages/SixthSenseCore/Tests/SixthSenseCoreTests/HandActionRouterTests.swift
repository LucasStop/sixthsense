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
    var router = HandActionRouter()

    for gesture in [DetectedHandGesture.pointing, .openHand, .fist, .none] {
        var fresh = router
        let r = reading(chirality: .left, gesture: gesture)
        let actions = fresh.process(left: r, right: nil)
        #expect(actions.contains { if case .click = $0 { return true }; return false } == false)
    }
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
    #expect(actions.contains { if case .moveCursor = $0 { return true }; return false })
    #expect(actions.contains { action in
        if case .click(let p) = action { return p.x == 0.6 && p.y == 0.3 }
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

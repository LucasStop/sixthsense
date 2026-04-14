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

// MARK: - Right hand tests

@Test func rightHandPointingEmitsMoveCursor() {
    var router = HandActionRouter()
    let right = reading(
        chirality: .right,
        gesture: .pointing,
        landmarks: landmarks(index: CGPoint(x: 0.4, y: 0.6))
    )

    let actions = router.process(left: nil, right: right)

    #expect(actions.contains { action in
        if case .moveCursor(let p) = action { return p.x == 0.4 && p.y == 0.6 }
        return false
    })
}

@Test func rightHandPinchEmitsClickOnce() {
    var router = HandActionRouter()
    let pinchReading = reading(chirality: .right, gesture: .pinch)

    // First pinch frame → click
    let first = router.process(left: nil, right: pinchReading)
    #expect(first.contains { if case .click = $0 { return true }; return false })

    // Sustained pinch should NOT spam clicks
    let second = router.process(left: nil, right: pinchReading, now: Date().addingTimeInterval(0.01))
    #expect(second.contains { if case .click = $0 { return true }; return false } == false)
}

@Test func rightHandPinchTwiceInQuickSuccessionEmitsDoubleClick() {
    var router = HandActionRouter()
    let pinchReading = reading(chirality: .right, gesture: .pinch)
    let noneReading = reading(chirality: .right, gesture: .none)

    let t0 = Date()
    _ = router.process(left: nil, right: pinchReading, now: t0)
    _ = router.process(left: nil, right: noneReading, now: t0.addingTimeInterval(0.05))
    let second = router.process(left: nil, right: pinchReading, now: t0.addingTimeInterval(0.15))

    #expect(second.contains { if case .doubleClick = $0 { return true }; return false })
}

@Test func rightHandPinchAfterWindowIsFreshClick() {
    var router = HandActionRouter()
    let pinchReading = reading(chirality: .right, gesture: .pinch)
    let noneReading = reading(chirality: .right, gesture: .none)

    let t0 = Date()
    _ = router.process(left: nil, right: pinchReading, now: t0)
    _ = router.process(left: nil, right: noneReading, now: t0.addingTimeInterval(0.1))
    let second = router.process(left: nil, right: pinchReading, now: t0.addingTimeInterval(0.5))

    // Outside window → should be a single click, not a double
    #expect(second.contains { if case .click = $0 { return true }; return false })
    #expect(second.contains { if case .doubleClick = $0 { return true }; return false } == false)
}

@Test func rightHandFistEntersAndExitsDragMode() {
    var router = HandActionRouter()

    // Fist → drag begin
    let fist = reading(chirality: .right, gesture: .fist)
    let beginActions = router.process(left: nil, right: fist)
    #expect(beginActions.contains { if case .dragBegin = $0 { return true }; return false })
    #expect(router.isDragging == true)

    // Sustained fist → no new drag begin
    let stillFist = router.process(left: nil, right: fist)
    #expect(stillFist.contains { if case .dragBegin = $0 { return true }; return false } == false)

    // Release → drag end
    let none = reading(chirality: .right, gesture: .none)
    let endActions = router.process(left: nil, right: none)
    #expect(endActions.contains { if case .dragEnd = $0 { return true }; return false })
    #expect(router.isDragging == false)
}

@Test func rightHandOpenHandEmitsScroll() {
    var router = HandActionRouter()
    let openHand = reading(chirality: .right, gesture: .openHand)

    let actions = router.process(left: nil, right: openHand)

    #expect(actions.contains { if case .scroll = $0 { return true }; return false })
}

@Test func rightHandRemovalEndsDragSafely() {
    var router = HandActionRouter()
    _ = router.process(left: nil, right: reading(chirality: .right, gesture: .fist))
    #expect(router.isDragging == true)

    // Hand disappears
    let actions = router.process(left: nil, right: nil)
    #expect(actions.contains { if case .dragEnd = $0 { return true }; return false })
    #expect(router.isDragging == false)
}

// MARK: - Left hand tests

@Test func leftFistHoldsAndReleasesCommand() {
    var router = HandActionRouter()

    _ = router.process(
        left: reading(chirality: .left, gesture: .fist),
        right: nil
    )
    #expect(router.isCommandHeld == true)

    let releaseActions = router.process(
        left: reading(chirality: .left, gesture: .none),
        right: nil
    )
    #expect(releaseActions.contains(.releaseCommand))
    #expect(router.isCommandHeld == false)
}

@Test func leftPinchTriggersMissionControl() {
    var router = HandActionRouter()
    let pinch = reading(chirality: .left, gesture: .pinch)

    let actions = router.process(left: pinch, right: nil)

    #expect(actions.contains(.missionControl))
}

@Test func leftOpenHandTriggersShowDesktop() {
    var router = HandActionRouter()
    let openHand = reading(chirality: .left, gesture: .openHand)

    let actions = router.process(left: openHand, right: nil)

    #expect(actions.contains(.showDesktop))
}

@Test func leftPointingAtLeftEdgeSwitchesSpaceLeft() {
    var router = HandActionRouter()
    let left = reading(
        chirality: .left,
        gesture: .pointing,
        landmarks: landmarks(wrist: CGPoint(x: 0.1, y: 0.5))
    )

    let actions = router.process(left: left, right: nil)

    #expect(actions.contains(.switchSpaceLeft))
}

@Test func leftPointingAtRightEdgeSwitchesSpaceRight() {
    var router = HandActionRouter()
    let left = reading(
        chirality: .left,
        gesture: .pointing,
        landmarks: landmarks(wrist: CGPoint(x: 0.9, y: 0.5))
    )

    let actions = router.process(left: left, right: nil)

    #expect(actions.contains(.switchSpaceRight))
}

@Test func leftPointingInTheMiddleDoesNotSwitchSpace() {
    var router = HandActionRouter()
    let left = reading(
        chirality: .left,
        gesture: .pointing,
        landmarks: landmarks(wrist: CGPoint(x: 0.5, y: 0.5))
    )

    let actions = router.process(left: left, right: nil)

    #expect(actions.contains(.switchSpaceLeft) == false)
    #expect(actions.contains(.switchSpaceRight) == false)
}

@Test func leftHandRemovalReleasesCommand() {
    var router = HandActionRouter()
    _ = router.process(left: reading(chirality: .left, gesture: .fist), right: nil)
    #expect(router.isCommandHeld == true)

    // Hand disappears
    let actions = router.process(left: nil, right: nil)
    #expect(actions.contains(.releaseCommand))
    #expect(router.isCommandHeld == false)
}

// MARK: - Both hands concurrently

@Test func bothHandsCanActSimultaneously() {
    var router = HandActionRouter()
    let right = reading(
        chirality: .right,
        gesture: .pointing,
        landmarks: landmarks(index: CGPoint(x: 0.5, y: 0.5))
    )
    let left = reading(chirality: .left, gesture: .fist)

    let actions = router.process(left: left, right: right)

    #expect(actions.contains { if case .moveCursor = $0 { return true }; return false })
    #expect(actions.contains(.holdCommand))
}

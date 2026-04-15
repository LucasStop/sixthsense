import Testing
import Foundation
import CoreGraphics
import ApplicationServices
import SixthSenseCore
import SharedServices
import SharedServicesMocks
@testable import HandCommandModule

// MARK: - Fixtures
//
// End-to-end tests for the simplified HandCommand pipeline.
//
// Current gesture set (minimal MVP):
//   • Right hand — moves the cursor using the index tip, regardless of
//     which gesture is classified.
//   • Left hand  — clicks at the last known cursor position when it
//     transitions into `.pinch`.
//
// Every other gesture (drag, scroll, Mission Control, Space switching,
// Command hold) is intentionally disabled at the router level and therefore
// should produce NO cursor or keyboard calls.

@MainActor
private struct Harness {
    let module: HandCommandModule
    let cursor: MockMouseController
    let keyboard: MockKeyboardInput

    static func make() -> Harness {
        let camera = MockCameraPipeline()
        let overlay = MockOverlayPresenter()
        let accessibility = MockWindowAccessibility()
        let cursor = MockMouseController()
        let keyboard = MockKeyboardInput()
        let bus = EventBus()

        let module = HandCommandModule(
            cameraManager: camera,
            overlayManager: overlay,
            accessibilityService: accessibility,
            cursorController: cursor,
            keyboardInput: keyboard,
            eventBus: bus
        )

        return Harness(module: module, cursor: cursor, keyboard: keyboard)
    }
}

// MARK: - Snapshot builders

private func landmarks(
    wrist: CGPoint = CGPoint(x: 0.5, y: 0.3),
    thumb: CGFloat = 0.40,
    index: CGFloat = 0.42,
    middle: CGFloat = 0.45,
    ring: CGFloat = 0.40,
    little: CGFloat = 0.40,
    thumbIndexOverride: CGFloat? = nil
) -> [HandJoint: HandLandmark] {
    let indexPos = CGPoint(x: wrist.x, y: wrist.y + index)
    let thumbPos: CGPoint
    if let override = thumbIndexOverride {
        thumbPos = CGPoint(x: indexPos.x, y: indexPos.y - override)
    } else {
        let t = thumb / sqrt(2.0)
        thumbPos = CGPoint(x: wrist.x + t, y: wrist.y + t)
    }
    return [
        .wrist:     HandLandmark(joint: .wrist,     position: wrist,        confidence: 0.9),
        .thumbTip:  HandLandmark(joint: .thumbTip,  position: thumbPos,     confidence: 0.9),
        .indexTip:  HandLandmark(joint: .indexTip,  position: indexPos,     confidence: 0.9),
        .middleTip: HandLandmark(joint: .middleTip, position: CGPoint(x: wrist.x, y: wrist.y + middle), confidence: 0.9),
        .ringTip:   HandLandmark(joint: .ringTip,   position: CGPoint(x: wrist.x, y: wrist.y + ring),   confidence: 0.9),
        .littleTip: HandLandmark(joint: .littleTip, position: CGPoint(x: wrist.x, y: wrist.y + little), confidence: 0.9),
    ]
}

private func snapshot(for gesture: DetectedHandGesture, wrist: CGPoint = CGPoint(x: 0.5, y: 0.3)) -> HandLandmarksSnapshot {
    let joints: [HandJoint: HandLandmark]
    switch gesture {
    case .pinch:
        joints = landmarks(wrist: wrist, thumbIndexOverride: 0.05)
    case .pointing:
        joints = landmarks(
            wrist: wrist,
            thumb: 0.15, index: 0.40,
            middle: 0.22, ring: 0.20, little: 0.18
        )
    case .openHand:
        joints = landmarks(wrist: wrist)
    case .fist:
        joints = landmarks(
            wrist: wrist,
            thumb: 0.40, index: 0.25,
            middle: 0.24, ring: 0.24, little: 0.24
        )
    case .none:
        joints = landmarks(
            wrist: wrist,
            thumb: 0.02, index: 0.02,
            middle: 0.02, ring: 0.02, little: 0.02
        )
    }
    let pending = HandLandmarksSnapshot(landmarks: joints, gesture: .none)
    return HandLandmarksSnapshot(
        landmarks: joints,
        gesture: HandGestureClassifier.classify(pending)
    )
}

private func reading(_ chirality: HandChirality, _ gesture: DetectedHandGesture, wrist: CGPoint = CGPoint(x: 0.5, y: 0.3)) -> HandReading {
    HandReading(chirality: chirality, snapshot: snapshot(for: gesture, wrist: wrist))
}

// MARK: - Right hand — cursor movement

@Test @MainActor func pipelineRightHandAnyGestureMovesCursor() async throws {
    let h = Harness.make()
    try await h.module.start()

    // Pointing
    h.module.handleReadings([reading(.right, .pointing, wrist: CGPoint(x: 0.4, y: 0.3))])
    // Open hand
    h.module.handleReadings([reading(.right, .openHand, wrist: CGPoint(x: 0.5, y: 0.3))])
    // Fist
    h.module.handleReadings([reading(.right, .fist, wrist: CGPoint(x: 0.6, y: 0.3))])

    let moveCount = h.cursor.calls.filter { if case .moveTo = $0 { return true }; return false }.count
    #expect(moveCount == 3)
}

@Test @MainActor func pipelineRightHandDoesNotClickEvenOnPinch() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .pinch)])
    h.module.handleReadings([reading(.right, .none)])
    h.module.handleReadings([reading(.right, .pinch)])

    let clickCount = h.cursor.calls.filter { if case .leftClick = $0 { return true }; return false }.count
    #expect(clickCount == 0)
}

// MARK: - Left hand — click

@Test @MainActor func pipelineLeftPinchFiresClick() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .none)])
    h.module.handleReadings([reading(.left, .pinch)])

    let clicked = h.cursor.calls.contains { if case .leftClick = $0 { return true }; return false }
    #expect(clicked == true)
}

@Test @MainActor func pipelineLeftPinchHeldDoesNotSpamClicks() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .pinch)])
    h.module.handleReadings([reading(.left, .pinch)])
    h.module.handleReadings([reading(.left, .pinch)])

    let clickCount = h.cursor.calls.filter { if case .leftClick = $0 { return true }; return false }.count
    #expect(clickCount == 1)
}

@Test @MainActor func pipelineLeftPinchAfterReleaseFiresAgain() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .pinch)])
    h.module.handleReadings([reading(.left, .none)])

    // Wait past the click debounce window (~0.18s) before the second pinch.
    try await Task.sleep(for: .milliseconds(220))

    h.module.handleReadings([reading(.left, .pinch)])

    let clickCount = h.cursor.calls.filter { if case .leftClick = $0 { return true }; return false }.count
    #expect(clickCount == 2)
}

// MARK: - Both hands together

@Test @MainActor func pipelineBothHandsMoveAndClickTogether() async throws {
    let h = Harness.make()
    try await h.module.start()

    // First frame: right establishes cursor.
    h.module.handleReadings([
        reading(.right, .openHand, wrist: CGPoint(x: 0.5, y: 0.3)),
        reading(.left, .none),
    ])

    // Second frame: left transitions into pinch → click at the right hand's tip.
    h.module.handleReadings([
        reading(.right, .openHand, wrist: CGPoint(x: 0.5, y: 0.3)),
        reading(.left, .pinch),
    ])

    let moved = h.cursor.calls.contains { if case .moveTo = $0 { return true }; return false }
    let clicked = h.cursor.calls.contains { if case .leftClick = $0 { return true }; return false }
    #expect(moved == true)
    #expect(clicked == true)
}

// MARK: - Disabled gestures produce no keyboard / drag / scroll

@Test @MainActor func pipelineLeftOpenHandDoesNotTriggerKeyboard() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .openHand)])

    #expect(h.keyboard.calls.isEmpty)
}

@Test @MainActor func pipelineLeftFistDoesNotHoldCommand() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .fist)])
    h.module.handleReadings([reading(.left, .none)])

    #expect(h.keyboard.calls.isEmpty)
}

@Test @MainActor func pipelineLeftPointingDoesNotSwitchSpace() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .pointing, wrist: CGPoint(x: 0.1, y: 0.3))])
    h.module.handleReadings([reading(.left, .pointing, wrist: CGPoint(x: 0.9, y: 0.3))])

    #expect(h.keyboard.calls.isEmpty)
}

// MARK: - Left hand scroll pipeline (circular rotation)

/// Build a minimal left-hand reading with the INDEX tip at the given
/// point, in an open-hand pose so the router's scroll gate accepts it.
/// The other landmarks are dressed around the index so the snapshot
/// looks plausible to the classifier.
private func leftHandWithIndex(at tip: CGPoint) -> HandReading {
    let wrist = CGPoint(x: tip.x, y: tip.y - 0.1)
    let joints: [HandJoint: HandLandmark] = [
        .wrist:     HandLandmark(joint: .wrist,     position: wrist,                                 confidence: 0.9),
        .thumbTip:  HandLandmark(joint: .thumbTip,  position: CGPoint(x: wrist.x - 0.05, y: wrist.y + 0.06),  confidence: 0.9),
        .indexTip:  HandLandmark(joint: .indexTip,  position: tip,                                   confidence: 0.9),
        .middleTip: HandLandmark(joint: .middleTip, position: CGPoint(x: wrist.x + 0.01, y: wrist.y + 0.08),  confidence: 0.9),
        .ringTip:   HandLandmark(joint: .ringTip,   position: CGPoint(x: wrist.x + 0.03, y: wrist.y + 0.07),  confidence: 0.9),
        .littleTip: HandLandmark(joint: .littleTip, position: CGPoint(x: wrist.x + 0.05, y: wrist.y + 0.06),  confidence: 0.9),
    ]
    let snapshot = HandLandmarksSnapshot(landmarks: joints, gesture: .openHand)
    return HandReading(chirality: .left, snapshot: snapshot)
}

@Test @MainActor func pipelineCounterClockwiseCircleCallsScroll() async throws {
    let h = Harness.make()
    try await h.module.start()

    // Trace a counter-clockwise circle with the left index tip. We
    // sleep a real ~20ms between frames so the router's clock sees a
    // meaningful dt between samples — the CircularScrollDetector needs
    // actual elapsed time to compute angular velocity.
    let center = CGPoint(x: 0.5, y: 0.5)
    let radius = 0.08
    for i in 0..<24 {
        let angle = 2.0 * .pi * Double(i) / 23.0
        let tip = CGPoint(
            x: center.x + CGFloat(radius * cos(angle)),
            y: center.y + CGFloat(radius * sin(angle))
        )
        h.module.handleReadings([leftHandWithIndex(at: tip)])
        try await Task.sleep(for: .milliseconds(20))
    }

    let scrolls = h.cursor.calls.filter { if case .scroll = $0 { return true }; return false }
    #expect(!scrolls.isEmpty)

    // CCW rotation has positive angular velocity → positive deltaY.
    for call in scrolls {
        if case .scroll(let dy, _) = call, dy > 0 {
            return  // pass
        }
    }
    Issue.record("Expected at least one positive scroll delta during CCW rotation")
}

@Test @MainActor func pipelineStationaryLeftHandNeverScrolls() async throws {
    // The bug report case: user raises the left hand to bring it into
    // the frame and holds it still. With the circular detector there's
    // no rotation, so NO scroll calls should be emitted at all.
    let h = Harness.make()
    try await h.module.start()

    // 30 frames all at the same index position.
    for _ in 0..<30 {
        h.module.handleReadings([leftHandWithIndex(at: CGPoint(x: 0.5, y: 0.55))])
    }

    let scrolls = h.cursor.calls.filter { if case .scroll = $0 { return true }; return false }
    #expect(scrolls.isEmpty)
}

@Test @MainActor func pipelineStraightLineDoesNotScroll() async throws {
    // A straight vertical flick should NOT scroll — that's the whole
    // point of the circular detector. Only a real rotation counts.
    let h = Harness.make()
    try await h.module.start()

    for i in 0..<20 {
        let y = 0.3 + 0.02 * Double(i)
        h.module.handleReadings([leftHandWithIndex(at: CGPoint(x: 0.5, y: y))])
    }

    let scrolls = h.cursor.calls.filter { if case .scroll = $0 { return true }; return false }
    #expect(scrolls.isEmpty)
}

// MARK: - Left hand drag pipeline

@Test @MainActor func pipelineLeftFistCallsLeftMouseDown() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .fist)])

    let downCount = h.cursor.calls.filter { if case .leftMouseDown = $0 { return true }; return false }.count
    #expect(downCount == 1)
}

@Test @MainActor func pipelineLeftFistReleaseCallsLeftMouseUp() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .fist)])
    h.module.handleReadings([reading(.left, .none)])

    let upCount = h.cursor.calls.filter { if case .leftMouseUp = $0 { return true }; return false }.count
    #expect(upCount == 1)
}

@Test @MainActor func pipelineMoveDuringDragUsesLeftMouseDragged() async throws {
    let h = Harness.make()
    try await h.module.start()

    // First frame: right establishes cursor + left fist starts drag.
    h.module.handleReadings([
        reading(.right, .none, wrist: CGPoint(x: 0.5, y: 0.3)),
        reading(.left, .fist),
    ])

    // Second frame: right moves while left still fist → should dispatch
    // leftMouseDragged, not moveTo.
    h.module.handleReadings([
        reading(.right, .none, wrist: CGPoint(x: 0.6, y: 0.3)),
        reading(.left, .fist),
    ])

    let draggedCount = h.cursor.calls.filter { if case .leftMouseDragged = $0 { return true }; return false }.count
    #expect(draggedCount >= 1)
}

@Test @MainActor func pipelineLeftHandGoneEndsDragSafely() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .fist)])
    h.module.handleNoHands()

    let downCount = h.cursor.calls.filter { if case .leftMouseDown = $0 { return true }; return false }.count
    let upCount = h.cursor.calls.filter { if case .leftMouseUp = $0 { return true }; return false }.count
    #expect(downCount == 1)
    #expect(upCount == 1)
}

// MARK: - Right fist still does nothing

@Test @MainActor func pipelineRightFistDoesNotDrag() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .fist)])

    let downCount = h.cursor.calls.filter { if case .leftMouseDown = $0 { return true }; return false }.count
    #expect(downCount == 0)
}

@Test @MainActor func pipelineRightOpenHandDoesNotScroll() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .openHand)])

    let scrollCount = h.cursor.calls.filter { if case .scroll = $0 { return true }; return false }.count
    #expect(scrollCount == 0)
}

// MARK: - Hand disappearance

@Test @MainActor func pipelineHandsGoingAwayDoesNotEmitSpuriousActions() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .pointing)])
    h.module.handleReadings([reading(.left, .pinch)])
    let snapshot = h.cursor.calls.count

    h.module.handleNoHands()

    // handleNoHands should not add any new cursor or keyboard calls.
    #expect(h.cursor.calls.count == snapshot)
    #expect(h.keyboard.calls.isEmpty)
}

// MARK: - Debug log

@Test @MainActor func pipelineDebugLogRecordsMoveActions() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .pointing, wrist: CGPoint(x: 0.5, y: 0.3))])

    #expect(h.module.debugLines.isEmpty == false)
    let first = h.module.debugLines.first ?? ""
    #expect(first.contains("R:pointing"))
    #expect(first.contains("move"))
}

@Test @MainActor func pipelineDebugLogRecordsClickActions() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .pinch)])

    let hasClickLine = h.module.debugLines.contains { $0.contains("click") }
    #expect(hasClickLine == true)
}

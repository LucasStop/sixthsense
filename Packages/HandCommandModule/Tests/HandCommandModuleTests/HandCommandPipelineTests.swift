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
// End-to-end tests for the HandCommandModule pipeline. They build fake hand
// readings in Core's neutral types, feed them through `handleReadings(_:)`,
// and assert that the mock cursor and mock keyboard received the right calls.
//
// This validates that every supported gesture (per hand) produces the
// expected real-world action without depending on the camera, Vision, or
// CGEvent. The Vision → HandReading glue is covered separately by unit
// tests of `makeReading(from:)`.

@MainActor
private struct Harness {
    let module: HandCommandModule
    let cursor: MockMouseController
    let keyboard: MockKeyboardInput
    let camera: MockCameraPipeline

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

        return Harness(module: module, cursor: cursor, keyboard: keyboard, camera: camera)
    }
}

// MARK: - Snapshot builders

/// Build a snapshot with every fingertip at a controllable distance from
/// the wrist. Defaults to an "open hand" pose (all fingers extended).
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
        // Pinch = thumb and index touching.
        joints = landmarks(wrist: wrist, thumbIndexOverride: 0.05)
    case .pointing:
        // Only index extended, others curled.
        joints = landmarks(
            wrist: wrist,
            thumb: 0.15,
            index: 0.40,
            middle: 0.22,
            ring: 0.20,
            little: 0.18
        )
    case .openHand:
        // All fingers extended at roughly equal length.
        joints = landmarks(wrist: wrist)
    case .fist:
        // All fingers curled to ~60% of thumb.
        joints = landmarks(
            wrist: wrist,
            thumb: 0.40,
            index: 0.25,
            middle: 0.24,
            ring: 0.24,
            little: 0.24
        )
    case .none:
        // Tiny hand — too small for classifier to act on.
        joints = landmarks(
            wrist: wrist,
            thumb: 0.02,
            index: 0.02,
            middle: 0.02,
            ring: 0.02,
            little: 0.02
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

// MARK: - Right hand — cursor

@Test @MainActor func pipelineRightPointingMovesCursor() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .pointing, wrist: CGPoint(x: 0.5, y: 0.3))])

    let moved = h.cursor.calls.contains { if case .moveTo = $0 { return true }; return false }
    #expect(moved == true)
    #expect(h.module.latestRightSnapshot?.gesture == .pointing)
}

@Test @MainActor func pipelineRightPinchFiresClick() async throws {
    let h = Harness.make()
    try await h.module.start()

    // Transition from none → pinch to fire a click once.
    h.module.handleReadings([reading(.right, .none)])
    h.module.handleReadings([reading(.right, .pinch)])

    let clicked = h.cursor.calls.contains { if case .leftClick = $0 { return true }; return false }
    #expect(clicked == true)
}

@Test @MainActor func pipelineRightPinchHeldDoesNotSpamClicks() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .pinch)])
    h.module.handleReadings([reading(.right, .pinch)])
    h.module.handleReadings([reading(.right, .pinch)])

    let clickCount = h.cursor.calls.filter { if case .leftClick = $0 { return true }; return false }.count
    #expect(clickCount == 1)
}

@Test @MainActor func pipelineRightFistStartsAndEndsDrag() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .fist)])
    let downCount = h.cursor.calls.filter { if case .leftMouseDown = $0 { return true }; return false }.count
    #expect(downCount == 1)

    h.module.handleReadings([reading(.right, .none)])
    let upCount = h.cursor.calls.filter { if case .leftMouseUp = $0 { return true }; return false }.count
    #expect(upCount == 1)
}

@Test @MainActor func pipelineRightOpenHandEmitsScroll() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .openHand)])

    let scrolled = h.cursor.calls.contains { if case .scroll = $0 { return true }; return false }
    #expect(scrolled == true)
}

// MARK: - Left hand — keyboard shortcuts

@Test @MainActor func pipelineLeftPinchTriggersMissionControl() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .pinch)])

    // Mission Control is Control+Up (0x7E) with control modifier.
    let fired = h.keyboard.calls.contains { call in
        if case .press(let keyCode, let modifiers) = call,
           keyCode == CGKeyCode(0x7E),
           CGEventFlags(rawValue: modifiers).contains(.maskControl) {
            return true
        }
        return false
    }
    #expect(fired == true)
}

@Test @MainActor func pipelineLeftOpenHandTriggersShowDesktop() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .openHand)])

    // F11 is 0x67 with no modifiers.
    let fired = h.keyboard.calls.contains { call in
        if case .press(let keyCode, _) = call, keyCode == CGKeyCode(0x67) {
            return true
        }
        return false
    }
    #expect(fired == true)
}

@Test @MainActor func pipelineLeftFistHoldsAndReleasesCommand() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .fist)])
    let holdFired = h.keyboard.calls.contains { call in
        if case .hold(let keyCode, _) = call, keyCode == CGKeyCode(0x37) { return true }
        return false
    }
    #expect(holdFired == true)

    h.module.handleReadings([reading(.left, .none)])
    let releaseFired = h.keyboard.calls.contains { call in
        if case .release(let keyCode, _) = call, keyCode == CGKeyCode(0x37) { return true }
        return false
    }
    #expect(releaseFired == true)
}

@Test @MainActor func pipelineLeftPointingAtLeftEdgeSwitchesSpaceLeft() async throws {
    let h = Harness.make()
    try await h.module.start()

    // Wrist x = 0.1 → well within the left edge (default threshold 0.25).
    h.module.handleReadings([reading(.left, .pointing, wrist: CGPoint(x: 0.1, y: 0.3))])

    // Control+Left Arrow = 0x7B with control modifier
    let fired = h.keyboard.calls.contains { call in
        if case .press(let keyCode, let modifiers) = call,
           keyCode == CGKeyCode(0x7B),
           CGEventFlags(rawValue: modifiers).contains(.maskControl) {
            return true
        }
        return false
    }
    #expect(fired == true)
}

@Test @MainActor func pipelineLeftPointingAtRightEdgeSwitchesSpaceRight() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .pointing, wrist: CGPoint(x: 0.9, y: 0.3))])

    let fired = h.keyboard.calls.contains { call in
        if case .press(let keyCode, let modifiers) = call,
           keyCode == CGKeyCode(0x7C),
           CGEventFlags(rawValue: modifiers).contains(.maskControl) {
            return true
        }
        return false
    }
    #expect(fired == true)
}

// MARK: - Both hands at once

@Test @MainActor func pipelineBothHandsCursorAndCommandHold() async throws {
    let h = Harness.make()
    try await h.module.start()

    let left = reading(.left, .fist)
    let right = reading(.right, .pointing, wrist: CGPoint(x: 0.6, y: 0.4))

    h.module.handleReadings([left, right])

    // Cursor moved
    let moved = h.cursor.calls.contains { if case .moveTo = $0 { return true }; return false }
    #expect(moved == true)

    // Command held
    let held = h.keyboard.calls.contains { call in
        if case .hold(let keyCode, _) = call, keyCode == CGKeyCode(0x37) { return true }
        return false
    }
    #expect(held == true)
}

// MARK: - Hand disappearance releases state

@Test @MainActor func pipelineHandsGoingAwayReleasesCommand() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.left, .fist)])
    h.module.handleNoHands()

    let releases = h.keyboard.calls.filter { call in
        if case .release(let keyCode, _) = call, keyCode == CGKeyCode(0x37) { return true }
        return false
    }.count
    #expect(releases >= 1)
}

@Test @MainActor func pipelineHandsGoingAwayEndsDrag() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .fist)])
    h.module.handleNoHands()

    let upCount = h.cursor.calls.filter { if case .leftMouseUp = $0 { return true }; return false }.count
    #expect(upCount >= 1)
}

// MARK: - Debug log

@Test @MainActor func pipelineDebugLogRecordsGesturesAndActions() async throws {
    let h = Harness.make()
    try await h.module.start()

    h.module.handleReadings([reading(.right, .pointing, wrist: CGPoint(x: 0.5, y: 0.3))])

    #expect(h.module.debugLines.isEmpty == false)
    let first = h.module.debugLines.first ?? ""
    #expect(first.contains("R:pointing"))
    #expect(first.contains("move"))
}

@Test @MainActor func pipelineDebugLogDeduplicatesIdenticalFrames() async throws {
    let h = Harness.make()
    try await h.module.start()

    // Three identical pointing frames — should produce one log line.
    let r = reading(.right, .pointing, wrist: CGPoint(x: 0.5, y: 0.3))
    h.module.handleReadings([r])
    h.module.handleReadings([r])
    h.module.handleReadings([r])

    #expect(h.module.debugLines.count == 1)
}

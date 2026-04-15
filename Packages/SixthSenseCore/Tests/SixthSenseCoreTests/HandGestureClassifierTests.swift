import Testing
import CoreGraphics
@testable import SixthSenseCore

// MARK: - Helpers

private func landmark(_ joint: HandJoint, at position: CGPoint, confidence: Float = 0.9) -> HandLandmark {
    HandLandmark(joint: joint, position: position, confidence: confidence)
}

private func snapshot(_ landmarks: [HandJoint: HandLandmark]) -> HandLandmarksSnapshot {
    HandLandmarksSnapshot(landmarks: landmarks, gesture: .none)
}

/// Build a snapshot with the wrist at the origin and five fingertips at the
/// given distances from the wrist, along the positive Y axis so the numbers
/// are easy to reason about.
private func handSnapshot(
    wrist: CGPoint = CGPoint(x: 0, y: 0),
    thumb: CGFloat,
    index: CGFloat,
    middle: CGFloat,
    ring: CGFloat,
    little: CGFloat,
    thumbIndexOverride: CGFloat? = nil
) -> HandLandmarksSnapshot {
    let thumbPos: CGPoint
    let indexPos = CGPoint(x: wrist.x, y: wrist.y + index)
    if let override = thumbIndexOverride {
        // Place thumb tip `override` units from the index tip, on the Y axis
        // (so it's collinear with wrist–index). That lets us force a known
        // pinch distance without invalidating wrist→thumb distance.
        thumbPos = CGPoint(x: indexPos.x, y: indexPos.y - override)
    } else {
        // Default: thumb is out at angle 45° to the side, same magnitude.
        let t = thumb / sqrt(2.0)
        thumbPos = CGPoint(x: wrist.x + t, y: wrist.y + t)
    }
    return snapshot([
        .wrist:     landmark(.wrist,     at: wrist),
        .thumbTip:  landmark(.thumbTip,  at: thumbPos),
        .indexTip:  landmark(.indexTip,  at: indexPos),
        .middleTip: landmark(.middleTip, at: CGPoint(x: wrist.x, y: wrist.y + middle)),
        .ringTip:   landmark(.ringTip,   at: CGPoint(x: wrist.x, y: wrist.y + ring)),
        .littleTip: landmark(.littleTip, at: CGPoint(x: wrist.x, y: wrist.y + little)),
    ])
}

// MARK: - Guardrails

@Test func classifierReturnsNoneWhenMissingRequiredJoints() {
    let snap = snapshot([.wrist: landmark(.wrist, at: .zero)])
    #expect(HandGestureClassifier.classify(snap) == .none)
}

@Test func classifierReturnsNoneWhenConfidenceIsLow() {
    var landmarks: [HandJoint: HandLandmark] = [:]
    for joint in [HandJoint.wrist] + HandJoint.fingertips {
        landmarks[joint] = landmark(joint, at: CGPoint(x: 0, y: 0), confidence: 0.1)
    }
    #expect(HandGestureClassifier.classify(snapshot(landmarks)) == .none)
}

@Test func classifierReturnsNoneForTinyHand() {
    // Every finger less than 0.06 from wrist — too small to classify reliably.
    let snap = handSnapshot(thumb: 0.02, index: 0.03, middle: 0.03, ring: 0.02, little: 0.02)
    #expect(HandGestureClassifier.classify(snap) == .none)
}

// MARK: - Pinch

@Test func classifierDetectsPinchWhenThumbAndIndexTouch() {
    // Hand of size ~0.40, thumb/index distance = 0.05 (well below 0.35 * 0.40 = 0.14)
    let snap = handSnapshot(
        thumb: 0.40,
        index: 0.40,
        middle: 0.40,
        ring: 0.40,
        little: 0.40,
        thumbIndexOverride: 0.05
    )
    #expect(HandGestureClassifier.classify(snap) == .pinch)
}

@Test func classifierDoesNotFalsePinchWithOpenHand() {
    // All fingers extended, thumb naturally 45° away from index.
    let snap = handSnapshot(thumb: 0.40, index: 0.40, middle: 0.40, ring: 0.40, little: 0.40)
    #expect(HandGestureClassifier.classify(snap) != .pinch)
}

// MARK: - Pointing

@Test func classifierDetectsPointingWhenOnlyIndexExtended() {
    // Index is at full length, other fingers are curled at ~50% of the max.
    let snap = handSnapshot(
        thumb: 0.15,
        index: 0.40,
        middle: 0.22,
        ring: 0.20,
        little: 0.18
    )
    #expect(HandGestureClassifier.classify(snap) == .pointing)
}

@Test func classifierDoesNotPointingWhenMiddleAlsoExtended() {
    // Index and middle both extended → should NOT be pointing.
    let snap = handSnapshot(
        thumb: 0.15,
        index: 0.40,
        middle: 0.38,
        ring: 0.22,
        little: 0.20
    )
    #expect(HandGestureClassifier.classify(snap) != .pointing)
}

// MARK: - Open hand

@Test func classifierDetectsOpenHandWhenAllFingersExtended() {
    // All fingers within 15% of the max length, no tight thumb/index pinch.
    let snap = handSnapshot(
        thumb: 0.35,
        index: 0.40,
        middle: 0.42,
        ring: 0.38,
        little: 0.36
    )
    #expect(HandGestureClassifier.classify(snap) == .openHand)
}

// MARK: - Fist

@Test func classifierDetectsFistWhenAllFingersCurled() {
    // Thumb slightly long so the ratio base is thumb, and all fingertips
    // are under 72% of the longest.
    let snap = handSnapshot(
        thumb: 0.40,
        index: 0.25,
        middle: 0.24,
        ring: 0.24,
        little: 0.24
    )
    #expect(HandGestureClassifier.classify(snap) == .fist)
}

// MARK: - Distance helper

@Test func classifierDistanceCalculation() {
    let a = CGPoint(x: 0, y: 0)
    let b = CGPoint(x: 3, y: 4)
    #expect(HandGestureClassifier.distance(a, b) == 5.0)
}

@Test func classifierRatiosAreSane() {
    #expect(HandGestureClassifier.pinchRatio > 0)
    #expect(HandGestureClassifier.extendedRatio > HandGestureClassifier.curledRatio)
    #expect(HandGestureClassifier.extendedRatio <= 1.0)
    #expect(HandGestureClassifier.curledRatio > 0)
}

// MARK: - Scale invariance

@Test func classifierIsScaleInvariant() {
    // Same pose (proportional lengths) at two different distances from the
    // camera should give the same gesture. Ratios: all 4 non-thumb fingers
    // ≥ 0.85 of the longest → .openHand regardless of absolute size.
    let small = handSnapshot(
        thumb: 0.20,
        index: 0.21,
        middle: 0.225,
        ring: 0.20,
        little: 0.20
    )
    let large = handSnapshot(
        thumb: 0.40,
        index: 0.42,
        middle: 0.45,
        ring: 0.40,
        little: 0.40
    )

    #expect(HandGestureClassifier.classify(small) == HandGestureClassifier.classify(large))
    #expect(HandGestureClassifier.classify(small) == .openHand)
}

// MARK: - Shaka

@Test func classifierDetectsShakaWhenThumbAndPinkyAreExtended() {
    // Thumb and pinky extended; index/middle/ring curled inward. This
    // is the "hang loose" pose and triggers Cmd+Tab.
    let snap = handSnapshot(
        thumb: 0.42,
        index: 0.22,
        middle: 0.22,
        ring: 0.22,
        little: 0.42
    )
    #expect(HandGestureClassifier.classify(snap) == .shaka)
}

@Test func classifierRejectsShakaWhenIndexIsExtended() {
    // Thumb + pinky + INDEX extended = not shaka (too many fingers out).
    let snap = handSnapshot(
        thumb: 0.42,
        index: 0.42,
        middle: 0.22,
        ring: 0.22,
        little: 0.42
    )
    #expect(HandGestureClassifier.classify(snap) != .shaka)
}

@Test func classifierRejectsShakaWhenThumbIsCurled() {
    // Pinky extended but thumb curled = not shaka. Different pose;
    // neither of the other cases should match either (only pinky out).
    let snap = handSnapshot(
        thumb: 0.20,
        index: 0.22,
        middle: 0.22,
        ring: 0.22,
        little: 0.42
    )
    #expect(HandGestureClassifier.classify(snap) != .shaka)
}

@Test func classifierShakaIsScaleInvariant() {
    let small = handSnapshot(
        thumb: 0.22,
        index: 0.12,
        middle: 0.12,
        ring: 0.12,
        little: 0.22
    )
    let large = handSnapshot(
        thumb: 0.45,
        index: 0.24,
        middle: 0.24,
        ring: 0.24,
        little: 0.45
    )
    #expect(HandGestureClassifier.classify(small) == .shaka)
    #expect(HandGestureClassifier.classify(large) == .shaka)
}

@Test func classifierShakaDoesNotMatchFist() {
    // A fist (all four curled) must NOT classify as shaka. Safety
    // check since shaka is now evaluated before fist in the classifier.
    let snap = handSnapshot(
        thumb: 0.40,
        index: 0.25,
        middle: 0.24,
        ring: 0.24,
        little: 0.24
    )
    #expect(HandGestureClassifier.classify(snap) == .fist)
}

// MARK: - Occluded-fingertip fallback for closed fists

/// Helper that builds a snapshot with confident MCPs but missing or
/// low-confidence fingertips — the shape Vision returns when the user
/// makes a real closed fist and the tips vanish behind the palm.
private func closedFistSnapshot(
    wrist: CGPoint = .zero,
    mcpDistance: CGFloat = 0.15
) -> HandLandmarksSnapshot {
    let landmarks: [HandJoint: HandLandmark] = [
        .wrist:     landmark(.wrist,     at: wrist),
        .indexMCP:  landmark(.indexMCP,  at: CGPoint(x: wrist.x + mcpDistance * 0.4, y: wrist.y + mcpDistance)),
        .middleMCP: landmark(.middleMCP, at: CGPoint(x: wrist.x + mcpDistance * 0.1, y: wrist.y + mcpDistance)),
        .ringMCP:   landmark(.ringMCP,   at: CGPoint(x: wrist.x - mcpDistance * 0.1, y: wrist.y + mcpDistance)),
        .littleMCP: landmark(.littleMCP, at: CGPoint(x: wrist.x - mcpDistance * 0.4, y: wrist.y + mcpDistance)),
        // Fingertips present but at low confidence — the classifier
        // must treat them as missing and take the fallback branch.
        .thumbTip:  HandLandmark(joint: .thumbTip,  position: .zero, confidence: 0.05),
        .indexTip:  HandLandmark(joint: .indexTip,  position: .zero, confidence: 0.05),
        .middleTip: HandLandmark(joint: .middleTip, position: .zero, confidence: 0.05),
        .ringTip:   HandLandmark(joint: .ringTip,   position: .zero, confidence: 0.05),
        .littleTip: HandLandmark(joint: .littleTip, position: .zero, confidence: 0.05),
    ]
    return snapshot(landmarks)
}

@Test func classifierDetectsClosedFistWhenFingertipsAreOccluded() {
    // The real-world case: user closes their fist tight enough that
    // Vision loses confidence on the fingertips. Classifier sees wrist
    // + MCPs with high confidence and the tips missing — must resolve
    // to .fist, not .none, so Mission Control fires.
    let snap = closedFistSnapshot()
    #expect(HandGestureClassifier.classify(snap) == .fist)
}

@Test func classifierRejectsClosedFistWhenPalmTooSmall() {
    // If the MCP cluster is tiny (fragmentary detection at frame edge),
    // we must NOT classify as fist or fragments would spam commands.
    let snap = closedFistSnapshot(mcpDistance: 0.01)
    #expect(HandGestureClassifier.classify(snap) == .none)
}

@Test func classifierClosedFistFallbackRequiresThreeMcps() {
    // Only two MCPs present — not enough palm signal to commit.
    let snap = snapshot([
        .wrist:     landmark(.wrist,     at: .zero),
        .indexMCP:  landmark(.indexMCP,  at: CGPoint(x: 0.05, y: 0.15)),
        .middleMCP: landmark(.middleMCP, at: CGPoint(x: 0.0,  y: 0.15)),
        // ringMCP / littleMCP missing
        .thumbTip:  HandLandmark(joint: .thumbTip,  position: .zero, confidence: 0.05),
        .indexTip:  HandLandmark(joint: .indexTip,  position: .zero, confidence: 0.05),
        .middleTip: HandLandmark(joint: .middleTip, position: .zero, confidence: 0.05),
        .ringTip:   HandLandmark(joint: .ringTip,   position: .zero, confidence: 0.05),
        .littleTip: HandLandmark(joint: .littleTip, position: .zero, confidence: 0.05),
    ])
    #expect(HandGestureClassifier.classify(snap) == .none)
}

@Test func classifierClosedFistFallbackDoesNotFireWhenTipsAreConfident() {
    // MCPs present AND fingertips confident → normal classification
    // path runs. This frame describes an open hand; must classify as
    // openHand, not be hijacked by the fallback.
    let snap = snapshot([
        .wrist:     landmark(.wrist,     at: .zero),
        .indexMCP:  landmark(.indexMCP,  at: CGPoint(x: 0.02,  y: 0.15)),
        .middleMCP: landmark(.middleMCP, at: CGPoint(x: 0.0,   y: 0.15)),
        .ringMCP:   landmark(.ringMCP,   at: CGPoint(x: -0.02, y: 0.15)),
        .littleMCP: landmark(.littleMCP, at: CGPoint(x: -0.04, y: 0.15)),
        .thumbTip:  landmark(.thumbTip,  at: CGPoint(x: 0.3, y: 0.3)),
        .indexTip:  landmark(.indexTip,  at: CGPoint(x: 0.02,  y: 0.40)),
        .middleTip: landmark(.middleTip, at: CGPoint(x: 0.0,   y: 0.42)),
        .ringTip:   landmark(.ringTip,   at: CGPoint(x: -0.02, y: 0.40)),
        .littleTip: landmark(.littleTip, at: CGPoint(x: -0.04, y: 0.38)),
    ])
    #expect(HandGestureClassifier.classify(snap) == .openHand)
}

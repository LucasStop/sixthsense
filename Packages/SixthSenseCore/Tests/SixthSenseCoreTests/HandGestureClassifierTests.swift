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

// MARK: - Tests

@Test func classifierReturnsNoneWhenMissingRequiredJoints() {
    // Only a wrist — no fingertips
    let snap = snapshot([
        .wrist: landmark(.wrist, at: .zero)
    ])
    #expect(HandGestureClassifier.classify(snap) == .none)
}

@Test func classifierReturnsNoneWhenConfidenceIsLow() {
    var landmarks: [HandJoint: HandLandmark] = [:]
    landmarks[.wrist]      = landmark(.wrist,      at: CGPoint(x: 0.5, y: 0.5), confidence: 0.1)
    landmarks[.thumbTip]   = landmark(.thumbTip,   at: CGPoint(x: 0.5, y: 0.5), confidence: 0.1)
    landmarks[.indexTip]   = landmark(.indexTip,   at: CGPoint(x: 0.5, y: 0.5), confidence: 0.1)
    landmarks[.middleTip]  = landmark(.middleTip,  at: CGPoint(x: 0.5, y: 0.5), confidence: 0.1)
    landmarks[.ringTip]    = landmark(.ringTip,    at: CGPoint(x: 0.5, y: 0.5), confidence: 0.1)
    landmarks[.littleTip]  = landmark(.littleTip,  at: CGPoint(x: 0.5, y: 0.5), confidence: 0.1)

    #expect(HandGestureClassifier.classify(snapshot(landmarks)) == .none)
}

@Test func classifierDetectsPinchWhenThumbAndIndexTouchClose() {
    // Wrist at origin, thumb and index very close together, other fingertips anywhere
    let landmarks: [HandJoint: HandLandmark] = [
        .wrist:     landmark(.wrist,     at: CGPoint(x: 0.5, y: 0.5)),
        .thumbTip:  landmark(.thumbTip,  at: CGPoint(x: 0.50, y: 0.50)),
        .indexTip:  landmark(.indexTip,  at: CGPoint(x: 0.51, y: 0.51)),
        .middleTip: landmark(.middleTip, at: CGPoint(x: 0.55, y: 0.55)),
        .ringTip:   landmark(.ringTip,   at: CGPoint(x: 0.56, y: 0.56)),
        .littleTip: landmark(.littleTip, at: CGPoint(x: 0.57, y: 0.57)),
    ]

    #expect(HandGestureClassifier.classify(snapshot(landmarks)) == .pinch)
}

@Test func classifierDetectsPointingWhenOnlyIndexExtended() {
    // Wrist at origin, index tip far away, other fingertips curled close to wrist
    let landmarks: [HandJoint: HandLandmark] = [
        .wrist:     landmark(.wrist,     at: CGPoint(x: 0.0, y: 0.0)),
        .thumbTip:  landmark(.thumbTip,  at: CGPoint(x: 0.15, y: 0.0)),
        .indexTip:  landmark(.indexTip,  at: CGPoint(x: 0.0, y: 0.5)),  // far (0.5 > 0.30)
        .middleTip: landmark(.middleTip, at: CGPoint(x: 0.10, y: 0.10)),
        .ringTip:   landmark(.ringTip,   at: CGPoint(x: 0.10, y: 0.12)),
        .littleTip: landmark(.littleTip, at: CGPoint(x: 0.10, y: 0.10)),
    ]

    #expect(HandGestureClassifier.classify(snapshot(landmarks)) == .pointing)
}

@Test func classifierDetectsOpenHandWhenAllFingersExtended() {
    let landmarks: [HandJoint: HandLandmark] = [
        .wrist:     landmark(.wrist,     at: CGPoint(x: 0.0, y: 0.0)),
        .thumbTip:  landmark(.thumbTip,  at: CGPoint(x: 0.45, y: 0.45)),  // thumb far
        .indexTip:  landmark(.indexTip,  at: CGPoint(x: 0.40, y: 0.40)),  // 0.566 > 0.30
        .middleTip: landmark(.middleTip, at: CGPoint(x: 0.45, y: 0.45)),
        .ringTip:   landmark(.ringTip,   at: CGPoint(x: 0.40, y: 0.40)),
        .littleTip: landmark(.littleTip, at: CGPoint(x: 0.35, y: 0.35)),
    ]

    #expect(HandGestureClassifier.classify(snapshot(landmarks)) == .openHand)
}

@Test func classifierDetectsFistWhenAllFingersCurled() {
    // Wrist at origin, all fingertips very close to wrist, thumb far enough that it's not pinch
    let landmarks: [HandJoint: HandLandmark] = [
        .wrist:     landmark(.wrist,     at: CGPoint(x: 0.0, y: 0.0)),
        .thumbTip:  landmark(.thumbTip,  at: CGPoint(x: 0.20, y: 0.0)),  // far enough from index (0.2) so not pinch
        .indexTip:  landmark(.indexTip,  at: CGPoint(x: 0.0, y: 0.10)),  // 0.10 < 0.20
        .middleTip: landmark(.middleTip, at: CGPoint(x: 0.05, y: 0.10)),
        .ringTip:   landmark(.ringTip,   at: CGPoint(x: 0.05, y: 0.12)),
        .littleTip: landmark(.littleTip, at: CGPoint(x: 0.05, y: 0.10)),
    ]

    #expect(HandGestureClassifier.classify(snapshot(landmarks)) == .fist)
}

@Test func classifierDistanceCalculation() {
    let a = CGPoint(x: 0, y: 0)
    let b = CGPoint(x: 3, y: 4)
    #expect(HandGestureClassifier.distance(a, b) == 5.0)
}

@Test func classifierThresholdsAreReasonable() {
    #expect(HandGestureClassifier.pinchThreshold > 0)
    #expect(HandGestureClassifier.extendedThreshold > HandGestureClassifier.curledThreshold)
}

import Testing
import CoreGraphics
@testable import SixthSenseCore

@Test func handJointHasAllTwentyOneCases() {
    #expect(HandJoint.allCases.count == 21)
}

@Test func handJointFingertipsAreFive() {
    #expect(HandJoint.fingertips.count == 5)
    #expect(HandJoint.fingertips.contains(.thumbTip))
    #expect(HandJoint.fingertips.contains(.indexTip))
    #expect(HandJoint.fingertips.contains(.middleTip))
    #expect(HandJoint.fingertips.contains(.ringTip))
    #expect(HandJoint.fingertips.contains(.littleTip))
}

@Test func handJointFingerChainsAllStartAtWrist() {
    for chain in HandJoint.fingerChains {
        #expect(chain.first == .wrist)
    }
}

@Test func handJointFingerChainsHaveFiveEach() {
    let chains = HandJoint.fingerChains
    #expect(chains.count == 5)
    for chain in chains {
        #expect(chain.count == 5)
    }
}

@Test func handLandmarkIsConfidentAboveHalf() {
    let low = HandLandmark(joint: .indexTip, position: .zero, confidence: 0.4)
    let high = HandLandmark(joint: .indexTip, position: .zero, confidence: 0.8)

    #expect(low.isConfident == false)
    #expect(high.isConfident == true)
}

@Test func handLandmarksSnapshotExposesPosition() {
    let landmark = HandLandmark(joint: .indexTip, position: CGPoint(x: 0.5, y: 0.5), confidence: 0.9)
    let snapshot = HandLandmarksSnapshot(
        landmarks: [.indexTip: landmark],
        gesture: .pointing
    )

    #expect(snapshot.position(of: .indexTip)?.x == 0.5)
    #expect(snapshot.position(of: .thumbTip) == nil)
}

@Test func handLandmarksSnapshotConfidenceCheck() {
    let confident = HandLandmark(joint: .indexTip, position: .zero, confidence: 0.9)
    let unconfident = HandLandmark(joint: .thumbTip, position: .zero, confidence: 0.2)
    let snapshot = HandLandmarksSnapshot(
        landmarks: [.indexTip: confident, .thumbTip: unconfident],
        gesture: .none
    )

    #expect(snapshot.hasConfidentJoints([.indexTip]) == true)
    #expect(snapshot.hasConfidentJoints([.thumbTip]) == false)
    #expect(snapshot.hasConfidentJoints([.indexTip, .thumbTip]) == false)
    #expect(snapshot.hasConfidentJoints([.ringTip]) == false)
}

@Test func detectedHandGestureLabelsArePortuguese() {
    #expect(DetectedHandGesture.none.label == "Nenhum gesto detectado")
    #expect(DetectedHandGesture.pinch.label == "Pinça")
    #expect(DetectedHandGesture.pointing.label == "Apontando")
    #expect(DetectedHandGesture.openHand.label == "Mão Aberta")
    #expect(DetectedHandGesture.fist.label == "Punho Fechado")
}

@Test func detectedHandGestureHasSystemImage() {
    for gesture in DetectedHandGesture.allCases {
        #expect(gesture.systemImage.isEmpty == false)
    }
}

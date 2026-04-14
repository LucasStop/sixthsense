import Testing
import Foundation
import CoreGraphics
@testable import SixthSenseCore

// MARK: - FaceLockMode

@Test func faceLockModeHasAllCases() {
    #expect(FaceLockMode.allCases.count == 3)
    #expect(FaceLockMode.allCases.contains(.disabled))
    #expect(FaceLockMode.allCases.contains(.anyFace))
    #expect(FaceLockMode.allCases.contains(.enrolledFace))
}

@Test func faceLockModeLabelsArePortuguese() {
    #expect(FaceLockMode.disabled.label == "Desativado")
    #expect(FaceLockMode.anyFace.label == "Qualquer rosto")
    #expect(FaceLockMode.enrolledFace.label == "Apenas o rosto cadastrado")
}

@Test func faceLockModeIsCodable() throws {
    let encoded = try JSONEncoder().encode(FaceLockMode.enrolledFace)
    let decoded = try JSONDecoder().decode(FaceLockMode.self, from: encoded)
    #expect(decoded == .enrolledFace)
}

@Test func faceLockModeSystemImageIsNonEmpty() {
    for mode in FaceLockMode.allCases {
        #expect(mode.systemImage.isEmpty == false)
    }
}

// MARK: - FaceRecognitionState.canUseGestures

@Test func disabledModeAlwaysAllowsGestures() {
    let state = FaceRecognitionState(
        isFaceDetected: false,
        isLookingAtScreen: false,
        isRecognizedUser: false,
        mode: .disabled
    )
    #expect(state.canUseGestures == true)
}

@Test func anyFaceModeRequiresDetectionAndLooking() {
    // No face detected.
    let noFace = FaceRecognitionState(
        isFaceDetected: false,
        isLookingAtScreen: false,
        isRecognizedUser: true,
        mode: .anyFace
    )
    #expect(noFace.canUseGestures == false)

    // Face detected but looking away.
    let lookingAway = FaceRecognitionState(
        isFaceDetected: true,
        isLookingAtScreen: false,
        isRecognizedUser: true,
        mode: .anyFace
    )
    #expect(lookingAway.canUseGestures == false)

    // Face + looking = allowed.
    let allowed = FaceRecognitionState(
        isFaceDetected: true,
        isLookingAtScreen: true,
        isRecognizedUser: false,    // any face doesn't care about recognition
        mode: .anyFace
    )
    #expect(allowed.canUseGestures == true)
}

@Test func enrolledFaceModeRequiresEverything() {
    // Unrecognized even if everything else is fine.
    let unrecognized = FaceRecognitionState(
        isFaceDetected: true,
        isLookingAtScreen: true,
        isRecognizedUser: false,
        mode: .enrolledFace
    )
    #expect(unrecognized.canUseGestures == false)

    // Everything in order.
    let allowed = FaceRecognitionState(
        isFaceDetected: true,
        isLookingAtScreen: true,
        isRecognizedUser: true,
        mode: .enrolledFace
    )
    #expect(allowed.canUseGestures == true)
}

@Test func statusLabelTellsTheUserWhatsWrong() {
    let disabled = FaceRecognitionState(mode: .disabled)
    #expect(disabled.statusLabel == "Bloqueio desativado")

    let searching = FaceRecognitionState(
        isFaceDetected: false,
        isLookingAtScreen: false,
        mode: .anyFace
    )
    #expect(searching.statusLabel == "Nenhum rosto detectado")

    let lookAway = FaceRecognitionState(
        isFaceDetected: true,
        isLookingAtScreen: false,
        mode: .anyFace
    )
    #expect(lookAway.statusLabel == "Olhe para a tela")

    let strangerMode = FaceRecognitionState(
        isFaceDetected: true,
        isLookingAtScreen: true,
        isRecognizedUser: false,
        mode: .enrolledFace
    )
    #expect(strangerMode.statusLabel == "Rosto não reconhecido")

    let allowed = FaceRecognitionState(
        isFaceDetected: true,
        isLookingAtScreen: true,
        isRecognizedUser: true,
        mode: .enrolledFace
    )
    #expect(allowed.statusLabel == "Rosto reconhecido — gestos liberados")
}

@Test func faceStateStoresBoundingBox() {
    let box = CGRect(x: 0.3, y: 0.4, width: 0.2, height: 0.3)
    let state = FaceRecognitionState(
        isFaceDetected: true,
        isLookingAtScreen: true,
        isRecognizedUser: true,
        mode: .enrolledFace,
        faceBoundingBox: box
    )
    #expect(state.faceBoundingBox == box)
}

@Test func faceStateEquatable() {
    let a = FaceRecognitionState(mode: .anyFace)
    let b = FaceRecognitionState(mode: .anyFace)
    let c = FaceRecognitionState(mode: .enrolledFace)
    #expect(a == b)
    #expect(a != c)
}

// MARK: - FaceAngle

@Test func faceAngleDistanceIsEuclidean() {
    let a = FaceAngle(yaw: 0, pitch: 0)
    let b = FaceAngle(yaw: 3, pitch: 4)
    #expect(abs(a.distance(to: b) - 5.0) < 0.001)
}

@Test func faceAngleDistanceIsZeroForIdentical() {
    let a = FaceAngle(yaw: 12, pitch: -5)
    let b = FaceAngle(yaw: 12, pitch: -5)
    #expect(a.distance(to: b) == 0)
}

@Test func faceAngleNormalizedPositionCentersAtOrigin() {
    let center = FaceAngle.center.normalizedPosition()
    #expect(abs(center.x - 0.5) < 0.001)
    #expect(abs(center.y - 0.5) < 0.001)
}

@Test func faceAngleNormalizedPositionSaturatesAtExtremes() {
    // Anything past ±maxDegrees should clamp at 0 or 1.
    let rightEdge = FaceAngle(yaw: 50, pitch: 0).normalizedPosition(maxDegrees: 25)
    #expect(rightEdge.x == 1.0)
    #expect(abs(rightEdge.y - 0.5) < 0.001)

    let bottomEdge = FaceAngle(yaw: 0, pitch: 50).normalizedPosition(maxDegrees: 25)
    #expect(abs(bottomEdge.x - 0.5) < 0.001)
    #expect(bottomEdge.y == 1.0)
}

@Test func faceAngleNormalizedPositionMidway() {
    // +12.5° yaw with a 25° span should sit at 3/4 of the axis.
    let point = FaceAngle(yaw: 12.5, pitch: 0).normalizedPosition(maxDegrees: 25)
    #expect(abs(point.x - 0.75) < 0.001)
}

// MARK: - EnrollmentTarget

@Test func defaultEnrollmentRingHasNineTargets() {
    #expect(EnrollmentTarget.defaultRing.count == 9)
    #expect(EnrollmentTarget.defaultRing.first?.angle == .center)
}

@Test func defaultRingHasUniqueIds() {
    let ids = EnrollmentTarget.defaultRing.map(\.id)
    #expect(Set(ids).count == ids.count)
}

@Test func defaultRingAnglesAreWithinLookingThreshold() {
    // All default targets sit inside the 25° "looking at screen"
    // threshold so enrolling them doesn't require extreme head poses.
    for target in EnrollmentTarget.defaultRing {
        #expect(abs(target.angle.yaw) <= 25)
        #expect(abs(target.angle.pitch) <= 25)
    }
}

@Test func defaultRingCoversCompassDirections() {
    let angles = EnrollmentTarget.defaultRing.map(\.angle)

    // Should have a target with positive yaw (right side).
    #expect(angles.contains { $0.yaw > 0 })
    // Should have a target with negative yaw (left side).
    #expect(angles.contains { $0.yaw < 0 })
    // Should have a target with positive pitch (looking down).
    #expect(angles.contains { $0.pitch > 0 })
    // Should have a target with negative pitch (looking up).
    #expect(angles.contains { $0.pitch < 0 })
}

@Test func enrollmentTargetStoresLabel() {
    let target = EnrollmentTarget(
        id: 42,
        angle: FaceAngle(yaw: 5, pitch: -5),
        label: "Teste",
        systemImage: "star"
    )
    #expect(target.label == "Teste")
    #expect(target.id == 42)
    #expect(target.angle.yaw == 5)
}

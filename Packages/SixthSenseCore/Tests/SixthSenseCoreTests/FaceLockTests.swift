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

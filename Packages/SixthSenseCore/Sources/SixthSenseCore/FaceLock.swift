import Foundation
import CoreGraphics

// MARK: - Face Lock Mode

/// How the face recognition gate decides whether the user is allowed to
/// drive the cursor with HandCommand.
public enum FaceLockMode: String, Sendable, Hashable, CaseIterable, Codable {
    /// Face recognition is off — HandCommand works for anyone, no checks.
    case disabled

    /// Any detected face counts, as long as they're looking at the screen.
    /// Useful on shared Macs where multiple people might want to use the
    /// gestures without having to enroll each one.
    case anyFace

    /// Only the enrolled face — a specific person previously captured —
    /// can drive the cursor. Still requires looking at the screen.
    case enrolledFace

    public var label: String {
        switch self {
        case .disabled:      return "Desativado"
        case .anyFace:       return "Qualquer rosto"
        case .enrolledFace:  return "Apenas o rosto cadastrado"
        }
    }

    public var description: String {
        switch self {
        case .disabled:
            return "Os gestos funcionam sempre. Nenhum reconhecimento facial."
        case .anyFace:
            return "Qualquer pessoa pode usar os gestos, desde que esteja olhando para a tela."
        case .enrolledFace:
            return "Só o rosto cadastrado pode usar os gestos, e ainda precisa estar olhando para a tela."
        }
    }

    public var systemImage: String {
        switch self {
        case .disabled:     return "person.crop.circle.badge.xmark"
        case .anyFace:      return "person.crop.circle"
        case .enrolledFace: return "person.crop.circle.badge.checkmark"
        }
    }
}

// MARK: - Face Recognition State

/// Observable snapshot of the current face tracking state. Consumed by
/// HandCommand's dispatch gate and by the training view's status indicator.
public struct FaceRecognitionState: Sendable, Equatable {
    /// Whether Vision is currently detecting at least one face in the frame.
    public let isFaceDetected: Bool

    /// Whether the detected face is aimed approximately at the screen,
    /// based on pitch/yaw thresholds.
    public let isLookingAtScreen: Bool

    /// Whether the detected face matches the enrolled face, if any.
    /// `true` when no enrolled face exists (mode != .enrolledFace).
    public let isRecognizedUser: Bool

    /// Distance to the closest enrolled embedding — smaller is more similar.
    /// `nil` when no comparison was performed this frame.
    public let recognitionDistance: Float?

    /// Current mode selected by the user.
    public let mode: FaceLockMode

    /// Bounding box of the detected face in normalized Vision coords, or
    /// `nil` if none. Used by the training view's overlay.
    public let faceBoundingBox: CGRect?

    public init(
        isFaceDetected: Bool = false,
        isLookingAtScreen: Bool = false,
        isRecognizedUser: Bool = true,
        recognitionDistance: Float? = nil,
        mode: FaceLockMode = .disabled,
        faceBoundingBox: CGRect? = nil
    ) {
        self.isFaceDetected = isFaceDetected
        self.isLookingAtScreen = isLookingAtScreen
        self.isRecognizedUser = isRecognizedUser
        self.recognitionDistance = recognitionDistance
        self.mode = mode
        self.faceBoundingBox = faceBoundingBox
    }

    /// Whether gestures are allowed to fire based on this state.
    /// - `.disabled` → always allowed
    /// - `.anyFace` → requires detected + looking
    /// - `.enrolledFace` → requires detected + looking + recognized
    public var canUseGestures: Bool {
        switch mode {
        case .disabled:
            return true
        case .anyFace:
            return isFaceDetected && isLookingAtScreen
        case .enrolledFace:
            return isFaceDetected && isLookingAtScreen && isRecognizedUser
        }
    }

    /// User-facing one-line status. Useful in the training card.
    public var statusLabel: String {
        switch mode {
        case .disabled:
            return "Bloqueio desativado"
        case .anyFace:
            if !isFaceDetected { return "Nenhum rosto detectado" }
            if !isLookingAtScreen { return "Olhe para a tela" }
            return "Rosto detectado — gestos liberados"
        case .enrolledFace:
            if !isFaceDetected { return "Nenhum rosto detectado" }
            if !isLookingAtScreen { return "Olhe para a tela" }
            if !isRecognizedUser { return "Rosto não reconhecido" }
            return "Rosto reconhecido — gestos liberados"
        }
    }
}

// MARK: - Face Gate Protocol

/// Minimal surface that HandCommandModule uses to decide whether to emit
/// cursor actions. Implemented by FaceRecognitionManager in SharedServices.
/// Kept in Core so HandCommandModule doesn't have to depend on a service
/// container full of UI / Vision machinery.
@MainActor
public protocol FaceGate: AnyObject {
    /// Live recognition state. Updated by a background observer and read by
    /// HandCommand on every dispatch cycle.
    var state: FaceRecognitionState { get }

    /// Convenience passthrough — equivalent to `state.canUseGestures`.
    var canUseGestures: Bool { get }
}

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

// MARK: - Face Angle

/// A face orientation in degrees. Used by the Face ID-style guided
/// enrollment flow to describe target head poses and compare against
/// the live reading coming from Vision.
public struct FaceAngle: Sendable, Hashable {
    /// Horizontal rotation (negative = left, positive = right).
    public let yaw: Double

    /// Vertical rotation (negative = up, positive = down).
    public let pitch: Double

    public init(yaw: Double, pitch: Double) {
        self.yaw = yaw
        self.pitch = pitch
    }

    public static let center = FaceAngle(yaw: 0, pitch: 0)

    /// Euclidean distance in degree-space — used to decide whether the
    /// current pose is close enough to a target to count as "on it".
    public func distance(to other: FaceAngle) -> Double {
        let dy = yaw - other.yaw
        let dp = pitch - other.pitch
        return (dy * dy + dp * dp).squareRoot()
    }

    /// Normalized position in `[0, 1]` for rendering the live pose cursor
    /// inside the enrollment ring. The output is clamped and centered on
    /// `(0.5, 0.5)`, assuming the ring covers ±`maxDegrees` on each axis.
    ///
    /// Default is 14° because the default enrollment ring pushes targets
    /// out to ±12°, and we want them to land just inside the ring edge
    /// instead of clipping to it.
    public func normalizedPosition(maxDegrees: Double = 14.0) -> CGPoint {
        let nx = (yaw / maxDegrees).clamped(to: -1...1)
        let ny = (pitch / maxDegrees).clamped(to: -1...1)
        return CGPoint(x: 0.5 + nx * 0.5, y: 0.5 + ny * 0.5)
    }
}

// MARK: - Enrollment Target

/// A single pose the user must hit during guided enrollment. Rendered in
/// the UI as a segment of the circular progress ring, with a label that
/// guides the user to the right angle.
public struct EnrollmentTarget: Sendable, Identifiable, Hashable {
    public let id: Int
    public let angle: FaceAngle
    public let label: String
    public let systemImage: String

    public init(id: Int, angle: FaceAngle, label: String, systemImage: String) {
        self.id = id
        self.angle = angle
        self.label = label
        self.systemImage = systemImage
    }

    /// Nine-point ring used by the default enrollment flow. Center is the
    /// zero target and the remaining 8 cover the cardinal and diagonal
    /// compass directions at ±10°-12° from center.
    ///
    /// Why so gentle? Vision's `VNDetectFaceLandmarksRequest` starts
    /// losing the face past ~25° of yaw/pitch, and users naturally
    /// over-rotate when trying to hit a visible dot. Keeping the targets
    /// inside ±12° means Vision reliably tracks the pose all the way to
    /// the edge of the ring, and the user only needs a subtle head turn
    /// to capture each angle.
    public static let defaultRing: [EnrollmentTarget] = [
        EnrollmentTarget(
            id: 0,
            angle: FaceAngle(yaw: 0, pitch: 0),
            label: "Olhe reto para a câmera",
            systemImage: "face.smiling"
        ),
        EnrollmentTarget(
            id: 1,
            angle: FaceAngle(yaw: 0, pitch: -10),
            label: "Incline levemente a cabeça para cima",
            systemImage: "arrow.up.circle"
        ),
        EnrollmentTarget(
            id: 2,
            angle: FaceAngle(yaw: 9, pitch: -8),
            label: "Olhe para o canto superior direito",
            systemImage: "arrow.up.right.circle"
        ),
        EnrollmentTarget(
            id: 3,
            angle: FaceAngle(yaw: 12, pitch: 0),
            label: "Olhe levemente para a direita",
            systemImage: "arrow.right.circle"
        ),
        EnrollmentTarget(
            id: 4,
            angle: FaceAngle(yaw: 9, pitch: 8),
            label: "Olhe para o canto inferior direito",
            systemImage: "arrow.down.right.circle"
        ),
        EnrollmentTarget(
            id: 5,
            angle: FaceAngle(yaw: 0, pitch: 10),
            label: "Incline levemente a cabeça para baixo",
            systemImage: "arrow.down.circle"
        ),
        EnrollmentTarget(
            id: 6,
            angle: FaceAngle(yaw: -9, pitch: 8),
            label: "Olhe para o canto inferior esquerdo",
            systemImage: "arrow.down.left.circle"
        ),
        EnrollmentTarget(
            id: 7,
            angle: FaceAngle(yaw: -12, pitch: 0),
            label: "Olhe levemente para a esquerda",
            systemImage: "arrow.left.circle"
        ),
        EnrollmentTarget(
            id: 8,
            angle: FaceAngle(yaw: -9, pitch: -8),
            label: "Olhe para o canto superior esquerdo",
            systemImage: "arrow.up.left.circle"
        ),
    ]
}

// MARK: - Recognition Calibration

/// Calibration parameters derived at enrollment time and applied at
/// recognition time. Instead of a single hard-coded feature-print
/// distance threshold, we compute how "internally consistent" the user's
/// own captures are across angles, and set a per-user threshold above
/// that — so an intruder has to beat the user's intra-enrollment spread
/// to pass, which is much tighter than the one-size-fits-all default.
public struct FaceRecognitionCalibration: Sendable, Hashable, Codable {

    /// Mean pairwise distance between the user's own enrolled prints
    /// (cross-pose). A low number means the user's captures are very
    /// self-similar; a higher number means pose variation produces
    /// noticeable differences.
    public let meanIntraDistance: Float

    /// Standard deviation of those pairwise distances. Used to push the
    /// threshold above typical self-variation.
    public let stdDevIntraDistance: Float

    /// Maximum pairwise distance observed inside the enrollment set.
    /// Used as the hard floor on the recognition threshold.
    public let maxIntraDistance: Float

    public init(
        meanIntraDistance: Float,
        stdDevIntraDistance: Float,
        maxIntraDistance: Float
    ) {
        self.meanIntraDistance = meanIntraDistance
        self.stdDevIntraDistance = stdDevIntraDistance
        self.maxIntraDistance = maxIntraDistance
    }

    /// Suggested recognition threshold: mean + k * stddev, clamped into
    /// a sane range. `k = 2.0` rejects roughly the 97.5th percentile of
    /// a normal distribution — tight but not paranoid.
    public var suggestedThreshold: Float {
        let candidate = meanIntraDistance + 2.0 * stdDevIntraDistance
        let floor = max(maxIntraDistance * 1.05, 12.0)
        return min(max(candidate, floor), 26.0)
    }
}

// MARK: - Helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

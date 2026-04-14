import Foundation

// MARK: - Hand Chirality

/// Whether a detected hand is the user's left or right. Vision reports this
/// via `VNHumanHandPoseObservation.chirality` on macOS 13+.
public enum HandChirality: String, Sendable, Hashable, CaseIterable {
    case left
    case right
    case unknown

    public var label: String {
        switch self {
        case .left:    return "Esquerda"
        case .right:   return "Direita"
        case .unknown: return "Desconhecida"
        }
    }
}

// MARK: - Hand Reading

/// One frame's reading for a single hand, combining its landmarks with the
/// chirality so the router can dispatch the right behaviour.
public struct HandReading: Sendable {
    public let chirality: HandChirality
    public let snapshot: HandLandmarksSnapshot

    public init(chirality: HandChirality, snapshot: HandLandmarksSnapshot) {
        self.chirality = chirality
        self.snapshot = snapshot
    }

    /// Convenience: the current gesture from the underlying snapshot.
    public var gesture: DetectedHandGesture { snapshot.gesture }
}

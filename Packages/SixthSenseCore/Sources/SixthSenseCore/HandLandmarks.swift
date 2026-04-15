import Foundation
import CoreGraphics

// MARK: - Hand Joint

/// The 21 hand joints detected by Vision's VNHumanHandPoseObservation.
/// Names mirror Apple's own joint identifiers so they map 1:1.
public enum HandJoint: String, Sendable, CaseIterable, Hashable {
    case wrist

    case thumbCMC, thumbMP, thumbIP, thumbTip
    case indexMCP, indexPIP, indexDIP, indexTip
    case middleMCP, middlePIP, middleDIP, middleTip
    case ringMCP, ringPIP, ringDIP, ringTip
    case littleMCP, littlePIP, littleDIP, littleTip

    /// Joints that represent fingertips — used for gesture classification.
    public static var fingertips: [HandJoint] {
        [.thumbTip, .indexTip, .middleTip, .ringTip, .littleTip]
    }

    /// Ordered joints that make up the skeleton connection lines for a finger.
    public static let thumbChain: [HandJoint]  = [.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip]
    public static let indexChain: [HandJoint]  = [.wrist, .indexMCP, .indexPIP, .indexDIP, .indexTip]
    public static let middleChain: [HandJoint] = [.wrist, .middleMCP, .middlePIP, .middleDIP, .middleTip]
    public static let ringChain: [HandJoint]   = [.wrist, .ringMCP, .ringPIP, .ringDIP, .ringTip]
    public static let littleChain: [HandJoint] = [.wrist, .littleMCP, .littlePIP, .littleDIP, .littleTip]

    /// All five finger chains, in order.
    public static var fingerChains: [[HandJoint]] {
        [thumbChain, indexChain, middleChain, ringChain, littleChain]
    }
}

// MARK: - Hand Landmark

/// A single detected joint with normalized position [0, 1] and Vision confidence.
public struct HandLandmark: Sendable, Hashable {
    public let joint: HandJoint
    public let position: CGPoint
    public let confidence: Float

    public init(joint: HandJoint, position: CGPoint, confidence: Float) {
        self.joint = joint
        self.position = position
        self.confidence = confidence
    }

    /// Whether this landmark is confident enough to trust in gesture classification.
    /// Threshold is intentionally permissive — Vision often reports useful joint
    /// positions at 0.3-0.5 when the hand is partially turned or lit indirectly,
    /// and discarding those frames makes the classifier feel "stuck".
    public var isConfident: Bool {
        confidence >= 0.3
    }
}

// MARK: - Hand Landmarks Snapshot

/// A single frame's worth of hand-tracking data, with the detected gesture
/// already classified. Produced by HandCommandModule and consumed by the
/// training/visualizer view.
public struct HandLandmarksSnapshot: Sendable {
    public let landmarks: [HandJoint: HandLandmark]
    public let gesture: DetectedHandGesture
    public let timestamp: Date

    public init(
        landmarks: [HandJoint: HandLandmark],
        gesture: DetectedHandGesture,
        timestamp: Date = Date()
    ) {
        self.landmarks = landmarks
        self.gesture = gesture
        self.timestamp = timestamp
    }

    /// Convenience accessor.
    public func position(of joint: HandJoint) -> CGPoint? {
        landmarks[joint]?.position
    }

    /// True if the snapshot has at least the given joints at high confidence.
    public func hasConfidentJoints(_ joints: [HandJoint]) -> Bool {
        joints.allSatisfy { landmarks[$0]?.isConfident == true }
    }
}

// MARK: - Detected Hand Gesture

/// High-level classification of a hand pose, suitable for showing in a UI
/// label ("Pinça", "Apontando", etc.).
public enum DetectedHandGesture: String, Sendable, Hashable, CaseIterable {
    case none
    case pinch
    case pointing
    case openHand
    case fist
    case shaka

    /// User-facing label (Portuguese).
    public var label: String {
        switch self {
        case .none:     return "Nenhum gesto detectado"
        case .pinch:    return "Pinça"
        case .pointing: return "Apontando"
        case .openHand: return "Mão Aberta"
        case .fist:     return "Punho Fechado"
        case .shaka:    return "Shaka"
        }
    }

    /// SF Symbol that visually represents the gesture.
    public var systemImage: String {
        switch self {
        case .none:     return "hand.raised.slash"
        case .pinch:    return "hand.pinch"
        case .pointing: return "hand.point.up.left"
        case .openHand: return "hand.raised"
        case .fist:     return "hand.raised.fingers.spread"
        case .shaka:    return "hand.wave"
        }
    }
}

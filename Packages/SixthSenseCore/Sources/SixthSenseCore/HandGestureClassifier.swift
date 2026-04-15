import Foundation
import CoreGraphics

// MARK: - Hand Gesture Classifier

/// Classifies a HandLandmarksSnapshot into a high-level DetectedHandGesture.
///
/// This is pure, deterministic geometry — no Vision dependency, no camera, no
/// side effects — so it is trivially unit-testable.
///
/// The classifier is **scale-invariant**: instead of comparing absolute
/// distances to hardcoded thresholds, it normalizes every fingertip distance
/// by the longest one in the snapshot. That way the same gesture is
/// recognized whether the hand is close to the camera (large in frame) or
/// far away (small in frame).
public enum HandGestureClassifier {

    // MARK: - Tunable ratios

    /// Fraction of the longest fingertip distance at which thumb/index count
    /// as pinched. Lower = tighter pinch required.
    public static let pinchRatio: CGFloat = 0.35

    /// Fraction of the longest fingertip distance at which a finger is
    /// considered "extended". Anything above this is open.
    public static let extendedRatio: CGFloat = 0.85

    /// Fraction of the longest fingertip distance below which a finger is
    /// considered "curled" into the palm.
    public static let curledRatio: CGFloat = 0.72

    /// Minimum absolute hand "size" before we bother classifying.
    /// Protects against noise when only a tiny fragment of a hand is visible.
    public static let minHandSize: CGFloat = 0.06

    // MARK: - Classify

    public static func classify(_ snapshot: HandLandmarksSnapshot) -> DetectedHandGesture {
        // We need wrist + all five fingertips at reasonable confidence.
        let required: [HandJoint] = [.wrist] + HandJoint.fingertips
        guard snapshot.hasConfidentJoints(required) else {
            return .none
        }

        guard let wrist  = snapshot.position(of: .wrist),
              let thumb  = snapshot.position(of: .thumbTip),
              let index  = snapshot.position(of: .indexTip),
              let middle = snapshot.position(of: .middleTip),
              let ring   = snapshot.position(of: .ringTip),
              let little = snapshot.position(of: .littleTip) else {
            return .none
        }

        let thumbDist  = distance(wrist, thumb)
        let indexDist  = distance(wrist, index)
        let middleDist = distance(wrist, middle)
        let ringDist   = distance(wrist, ring)
        let littleDist = distance(wrist, little)

        let maxDist = max(thumbDist, indexDist, middleDist, ringDist, littleDist)
        guard maxDist > minHandSize else { return .none }

        // Pinch — check first because a tight thumb/index pinch overrides
        // any other interpretation of the hand pose.
        let thumbIndexDistance = distance(thumb, index)
        if thumbIndexDistance < pinchRatio * maxDist {
            return .pinch
        }

        // Ratios of each finger to the longest one in the hand.
        let relThumb  = thumbDist  / maxDist
        let relIndex  = indexDist  / maxDist
        let relMiddle = middleDist / maxDist
        let relRing   = ringDist   / maxDist
        let relLittle = littleDist / maxDist

        let nonThumbFingers = [relIndex, relMiddle, relRing, relLittle]
        let extendedCount = nonThumbFingers.filter { $0 >= extendedRatio }.count
        let curledCount   = nonThumbFingers.filter { $0 <= curledRatio }.count

        // Shaka (hang loose) — thumb and pinky extended, index/middle/ring
        // curled. Checked BEFORE pointing/fist because its signature
        // uniquely needs an extended pinky alongside an extended thumb,
        // which neither of the others require.
        if relThumb  >= extendedRatio &&
           relLittle >= extendedRatio &&
           relIndex  < curledRatio &&
           relMiddle < curledRatio &&
           relRing   < curledRatio {
            return .shaka
        }

        // Pointing — index clearly longer than the other three fingers.
        // We use a slightly looser test (>= curledRatio) to tolerate real
        // hands where middle/ring don't curl all the way.
        if relIndex >= extendedRatio &&
           relMiddle < extendedRatio &&
           relRing   < extendedRatio &&
           relLittle < extendedRatio &&
           relIndex > relMiddle + 0.05 {
            return .pointing
        }

        // Open hand — all four non-thumb fingers extended.
        if extendedCount == 4 {
            return .openHand
        }

        // Fist — all four non-thumb fingers curled.
        if curledCount == 4 {
            return .fist
        }

        return .none
    }

    /// Euclidean distance between two normalized points.
    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

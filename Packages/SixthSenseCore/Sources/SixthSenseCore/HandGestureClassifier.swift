import Foundation
import CoreGraphics

// MARK: - Hand Gesture Classifier

/// Classifies a HandLandmarksSnapshot into a high-level DetectedHandGesture.
///
/// This is pure, deterministic geometry — no Vision dependency, no camera, no
/// side effects — so it is trivially unit-testable. The real hand-tracking
/// pipeline feeds snapshots in, and the UI reads the resulting gesture label.
public enum HandGestureClassifier {

    /// Distance below which the thumb tip and index tip are considered pinched.
    public static let pinchThreshold: CGFloat = 0.06

    /// Distance above which a fingertip is considered "extended" away from the wrist.
    public static let extendedThreshold: CGFloat = 0.30

    /// Distance below which a fingertip is considered "curled" toward the palm.
    public static let curledThreshold: CGFloat = 0.20

    /// Classify a snapshot. Returns `.none` if the snapshot lacks enough confident
    /// joints to make any judgment.
    public static func classify(_ snapshot: HandLandmarksSnapshot) -> DetectedHandGesture {
        // Need the wrist and all five fingertips at high confidence.
        let required: [HandJoint] = [.wrist] + HandJoint.fingertips
        guard snapshot.hasConfidentJoints(required) else {
            return .none
        }

        guard let wrist = snapshot.position(of: .wrist),
              let thumb = snapshot.position(of: .thumbTip),
              let index = snapshot.position(of: .indexTip),
              let middle = snapshot.position(of: .middleTip),
              let ring = snapshot.position(of: .ringTip),
              let little = snapshot.position(of: .littleTip) else {
            return .none
        }

        // Pinch: thumb and index tips are very close together.
        let thumbIndexDistance = distance(thumb, index)
        if thumbIndexDistance < pinchThreshold {
            return .pinch
        }

        let indexDist  = distance(wrist, index)
        let middleDist = distance(wrist, middle)
        let ringDist   = distance(wrist, ring)
        let littleDist = distance(wrist, little)

        let extendedFingers = [indexDist, middleDist, ringDist, littleDist]
            .filter { $0 > extendedThreshold }
            .count
        let curledFingers = [indexDist, middleDist, ringDist, littleDist]
            .filter { $0 < curledThreshold }
            .count

        // Pointing: only the index is extended, the others are curled.
        if indexDist > extendedThreshold &&
           middleDist < curledThreshold &&
           ringDist < curledThreshold &&
           littleDist < curledThreshold {
            return .pointing
        }

        // Open hand: all four non-thumb fingers extended.
        if extendedFingers == 4 {
            return .openHand
        }

        // Fist: all four non-thumb fingers curled.
        if curledFingers == 4 {
            return .fist
        }

        return .none
    }

    /// Euclidean distance between two normalized points.
    public static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }
}

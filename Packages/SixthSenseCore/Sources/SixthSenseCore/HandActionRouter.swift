import Foundation
import CoreGraphics

// MARK: - Hand Action

/// High-level action produced by the HandActionRouter in response to one or
/// two HandReadings. Consumed by HandCommandModule, which translates each
/// case into CGEvent-based cursor / keyboard injection.
///
/// The enum intentionally keeps cases for gestures that are not currently
/// wired up (drag, scroll, Mission Control, Space switching, Command hold)
/// so they can be re-enabled in future iterations without reshaping the
/// public surface.
public enum HandAction: Sendable, Equatable {
    // Cursor (right hand)
    case moveCursor(normalized: CGPoint)
    case click(at: CGPoint)

    // Reserved for future use — not currently emitted by the router.
    case doubleClick(at: CGPoint)
    case dragBegin(at: CGPoint)
    case dragEnd(at: CGPoint)
    case scroll(deltaY: Int32)
    case missionControl
    case showDesktop
    case switchSpaceLeft
    case switchSpaceRight
    case holdCommand
    case releaseCommand
}

// MARK: - Hand Action Router

/// Pure state machine that maps hand readings to high-level actions.
///
/// Current rules (minimal MVP — no drag, scroll, shortcuts, modifiers):
///
///   • Right hand → always moves the cursor to the index tip position,
///     regardless of what gesture is classified. This way the cursor
///     tracks the finger smoothly even during brief classification drops.
///
///   • Left hand  → clicks at the last known cursor position the moment it
///     transitions into a `.pinch`. Sustained pinch does not spam clicks.
///
/// Any other gesture is ignored. When either hand disappears, its tracking
/// state resets so the next entry is a clean edge-trigger.
public struct HandActionRouter: Sendable {

    // MARK: - State

    /// The last known index-tip position of the right hand (normalized
    /// Vision coords). Used as the click target when the left hand pinches.
    private var lastRightIndexTip: CGPoint = CGPoint(x: 0.5, y: 0.5)

    /// Previous left-hand gesture — used to detect the edge transition into
    /// `.pinch` (so holding the pinch doesn't fire repeat clicks).
    private var lastLeftGesture: DetectedHandGesture = .none

    public init() {}

    // MARK: - Routing

    /// Process one frame. Pass `nil` for a hand that was not detected.
    /// Returns every HandAction that should fire this frame.
    public mutating func process(
        left: HandReading?,
        right: HandReading?,
        now: Date = Date()
    ) -> [HandAction] {
        var actions: [HandAction] = []

        // Right hand → cursor movement. Gesture-agnostic: as long as the
        // index tip is confident, we move there. This avoids the jitter of
        // "stop tracking when pointing isn't perfectly classified".
        if let right,
           let indexLandmark = right.snapshot.landmarks[.indexTip],
           indexLandmark.isConfident {
            let tip = indexLandmark.position
            actions.append(.moveCursor(normalized: tip))
            lastRightIndexTip = tip
        }

        // Left hand → click on the edge transition into pinch. Any other
        // gesture (including none) just updates the "last" state so the
        // next pinch edge-triggers cleanly.
        if let left {
            if left.gesture == .pinch && lastLeftGesture != .pinch {
                actions.append(.click(at: lastRightIndexTip))
            }
            lastLeftGesture = left.gesture
        } else {
            lastLeftGesture = .none
        }

        _ = now // reserved for future debounce-based rules
        return actions
    }
}

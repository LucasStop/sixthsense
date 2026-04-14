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
/// Current rules:
///
///   • Right hand → always moves the cursor to the smoothed index-tip
///     position, regardless of what gesture is classified. The smoothing
///     is done by a `CursorSmoother` (One Euro Filter) so the cursor
///     feels steady when the hand is still and responsive when it moves
///     fast.
///
///   • Left hand pinch  → clicks at the last known cursor position the
///     moment it transitions into a `.pinch`. Sustained pinch does not
///     spam clicks. A temporal debounce (`clickDebounce`) protects
///     against double-fires when the classifier oscillates between
///     `.pinch` and `.none`. Suppressed while a drag is active.
///
///   • Left hand fist   → starts a drag: emits `.dragBegin` on the
///     transition into `.fist` and `.dragEnd` when the fist is released.
///     The module reads `isDragging` to know whether to dispatch
///     `moveCursor` as `mouseMoved` or `leftMouseDragged`.
///
/// Any other gesture is ignored. When either hand disappears, its
/// tracking state resets so the next entry is a clean edge-trigger, and
/// any active drag is ended safely.
public struct HandActionRouter: Sendable {

    // MARK: - Tunables

    /// Minimum time between successive clicks. Shorter than this and the
    /// second pinch is treated as detector noise, not a fresh click.
    public var clickDebounce: TimeInterval = 0.18

    // MARK: - State

    /// The last smoothed index-tip position of the right hand (normalized
    /// Vision coords). Used as the click target when the left hand pinches
    /// and as the anchor for dragBegin / dragEnd.
    private var lastRightIndexTip: CGPoint = CGPoint(x: 0.5, y: 0.5)

    /// Previous left-hand gesture — used to detect edge transitions.
    private var lastLeftGesture: DetectedHandGesture = .none

    /// Timestamp of the last click emitted, for temporal debounce.
    private var lastClickTime: Date?

    /// Whether the user is currently holding the left fist (drag active).
    /// Exposed so HandCommandModule can decide whether moveCursor should
    /// be dispatched as a plain mouseMoved or as a leftMouseDragged.
    public private(set) var isDragging: Bool = false

    /// One Euro Filter for the cursor x/y — smooths hand jitter while
    /// keeping intentional movement responsive.
    private var smoother: CursorSmoother

    public init(
        minCutoff: Double = 1.5,
        beta: Double = 0.05,
        dCutoff: Double = 1.0
    ) {
        self.smoother = CursorSmoother(
            minCutoff: minCutoff,
            beta: beta,
            dCutoff: dCutoff
        )
    }

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
        // index tip is confident, we move there (after smoothing).
        if let right,
           let indexLandmark = right.snapshot.landmarks[.indexTip],
           indexLandmark.isConfident {
            let raw = indexLandmark.position
            let smoothed = smoother.smooth(raw, timestamp: now.timeIntervalSinceReferenceDate)
            actions.append(.moveCursor(normalized: smoothed))
            lastRightIndexTip = smoothed
        } else {
            // Right hand gone — forget the smoother's history so the next
            // fresh entry doesn't get dragged toward the stale position.
            smoother.reset()
        }

        // Left hand → drag (fist) + click (pinch).
        if let left {
            // Drag state machine runs FIRST so we know if a pinch in this
            // frame should be suppressed.
            if left.gesture == .fist {
                if !isDragging {
                    actions.append(.dragBegin(at: lastRightIndexTip))
                    isDragging = true
                }
                // Sustained fist → no additional event.
            } else if isDragging {
                actions.append(.dragEnd(at: lastRightIndexTip))
                isDragging = false
            }

            // Click only when NOT dragging (so a pinch at the end of a
            // drag gesture won't immediately click the drop target).
            if !isDragging &&
               left.gesture == .pinch &&
               lastLeftGesture != .pinch {
                let longEnoughSinceLastClick =
                    lastClickTime.map { now.timeIntervalSince($0) >= clickDebounce } ?? true
                if longEnoughSinceLastClick {
                    actions.append(.click(at: lastRightIndexTip))
                    lastClickTime = now
                }
            }

            lastLeftGesture = left.gesture
        } else {
            // Left hand disappeared — fail-safe end of drag so the user
            // isn't stuck with a held mouse button.
            if isDragging {
                actions.append(.dragEnd(at: lastRightIndexTip))
                isDragging = false
            }
            lastLeftGesture = .none
        }

        return actions
    }
}

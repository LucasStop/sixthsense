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

    /// Whether the user is currently holding the left hand in pointing
    /// mode (scrolling). Exposed so the training view can light up a
    /// "scrolling" badge in real time.
    public private(set) var isScrolling: Bool = false

    // MARK: - Scroll tuning

    /// Vertical distance (in normalized Vision coords) between the left
    /// wrist and the left index tip at which the scroll speed saturates.
    /// 0.20 means "about a hand length" — the full finger extension up
    /// or down from the wrist produces max speed.
    public var scrollSaturationDistance: Double = 0.20

    /// Minimum |index - wrist| along the vertical axis before we start
    /// scrolling at all. Below this the gesture is treated as "parked"
    /// to prevent jittery scroll near the wrist.
    public var scrollDeadzone: Double = 0.03

    /// Maximum scroll wheel delta (in pixels) to emit per frame when
    /// the gesture is saturated. Smaller values feel slower / more
    /// controlled. Apps interpret deltaY > 0 as "scroll up".
    public var scrollMaxDelta: Int32 = 18

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

        // Left hand → drag (fist) + click (pinch) + scroll (pointing).
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

            // Scroll — left hand pointing. Continuous as long as the
            // gesture holds. Suppressed while dragging so the user
            // can't accidentally emit scroll wheel events mid-drag.
            if !isDragging, left.gesture == .pointing {
                isScrolling = true
                if let delta = Self.scrollDelta(
                    for: left.snapshot,
                    deadzone: scrollDeadzone,
                    saturation: scrollSaturationDistance,
                    maxDelta: scrollMaxDelta
                ) {
                    actions.append(.scroll(deltaY: delta))
                }
            } else if isScrolling {
                isScrolling = false
            }

            // Click only when NOT dragging AND NOT scrolling (so a pinch
            // immediately after scrolling doesn't trigger a click at the
            // scroll position).
            if !isDragging && !isScrolling &&
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
            isScrolling = false
            lastLeftGesture = .none
        }

        return actions
    }

    // MARK: - Scroll math

    /// Computes the scroll wheel delta for a pointing hand. Returns
    /// `nil` when the index tip is inside the deadzone (no scroll) or
    /// when the required landmarks are missing.
    ///
    /// The algorithm is: measure the vertical distance from the wrist to
    /// the index tip. Because Vision uses bottom-left origin, a higher
    /// index Y means the finger is pointing UP from the wrist → scroll
    /// UP (positive deltaY). Beyond `saturation` the magnitude caps at
    /// `maxDelta`. Pure geometry — no side effects, fully testable.
    static func scrollDelta(
        for snapshot: HandLandmarksSnapshot,
        deadzone: Double,
        saturation: Double,
        maxDelta: Int32
    ) -> Int32? {
        guard let wrist = snapshot.landmarks[.wrist]?.position,
              let tip = snapshot.landmarks[.indexTip]?.position else {
            return nil
        }

        // Vision: y increases upward. Positive offset = finger above
        // wrist = scroll UP in macOS CGEvent terms (positive deltaY).
        let offset = Double(tip.y - wrist.y)
        if abs(offset) < deadzone { return nil }

        let sign: Double = offset >= 0 ? 1.0 : -1.0
        let magnitude = min((abs(offset) - deadzone) / max(saturation - deadzone, 0.001), 1.0)
        let delta = Int32((Double(maxDelta) * magnitude * sign).rounded())
        return delta == 0 ? nil : delta
    }
}

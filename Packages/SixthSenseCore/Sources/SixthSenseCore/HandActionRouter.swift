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

    // Drag (left fist)
    case dragBegin(at: CGPoint)
    case dragEnd(at: CGPoint)

    // Scroll (left circular motion)
    case scroll(deltaY: Int32)

    // System shortcuts (both-fists / left-shaka)
    case missionControl
    case appSwitcher

    // Reserved for future use — not currently emitted by the router.
    case doubleClick(at: CGPoint)
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

    /// Minimum time between successive Cmd+Tab triggers. Shorter than
    /// this and classifier flapping around the shaka pose would spam
    /// the keyboard. 0.35s lets the user cycle apps at ~3 Hz when they
    /// re-enter the pose, which matches typical Cmd+Tab usage.
    public var appSwitcherDebounce: TimeInterval = 0.35

    /// Minimum time between successive Mission Control triggers.
    public var missionControlDebounce: TimeInterval = 0.8

    // MARK: - State

    /// The last smoothed index-tip position of the right hand (normalized
    /// Vision coords). Used as the click target when the left hand pinches
    /// and as the anchor for dragBegin / dragEnd.
    private var lastRightIndexTip: CGPoint = CGPoint(x: 0.5, y: 0.5)

    /// Previous left-hand gesture — used to detect edge transitions.
    private var lastLeftGesture: DetectedHandGesture = .none

    /// Previous right-hand gesture — used to detect the "both fists"
    /// edge transition for Mission Control.
    private var lastRightGesture: DetectedHandGesture = .none

    /// Timestamp of the last click emitted, for temporal debounce.
    private var lastClickTime: Date?

    /// Timestamp of the last Cmd+Tab emitted.
    private var lastAppSwitcherTime: Date?

    /// Timestamp of the last Mission Control emitted.
    private var lastMissionControlTime: Date?

    /// Whether the user is currently holding the left fist (drag active).
    /// Exposed so HandCommandModule can decide whether moveCursor should
    /// be dispatched as a plain mouseMoved or as a leftMouseDragged.
    public private(set) var isDragging: Bool = false

    /// Whether the circular scroll detector is currently emitting
    /// pulses. Exposed so the training card can light up a "rolando"
    /// indicator while the user is rotating.
    public var isScrolling: Bool {
        scrollDetector.isScrolling
    }

    /// Circular scroll wheel: watches the left index tip trace a circle
    /// in the air and converts the rotation speed into scroll deltas.
    private var scrollDetector = CircularScrollDetector()

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

        // Two-fists → Mission Control. Checked BEFORE the drag state
        // machine so that entering the two-fists pose cancels an
        // in-progress drag (if any) instead of leaving it stuck.
        // Edge-triggered: fires once on the transition into the pose,
        // with a debounce so re-entering doesn't spam F3.
        let bothFists = (left?.gesture == .fist) && (right?.gesture == .fist)
        let wasBothFists = (lastLeftGesture == .fist) && (lastRightGesture == .fist)

        if bothFists && !wasBothFists {
            let longEnough = lastMissionControlTime
                .map { now.timeIntervalSince($0) >= missionControlDebounce } ?? true
            if longEnough {
                // If a drag was active (left fist alone), close it out
                // cleanly before firing the shortcut.
                if isDragging {
                    actions.append(.dragEnd(at: lastRightIndexTip))
                    isDragging = false
                }
                actions.append(.missionControl)
                lastMissionControlTime = now
                scrollDetector.reset()
            }
        }

        // Left hand → drag (fist) + click (pinch) + scroll (circle) +
        // shaka (app switcher).
        if let left {
            // Drag state machine. Only engage if the RIGHT hand isn't
            // also in a fist — that combination is Mission Control and
            // was handled above. Without this guard, the very first
            // frame of two-fists would fire Mission Control AND start
            // a drag on the same frame.
            if left.gesture == .fist && right?.gesture != .fist {
                if !isDragging {
                    actions.append(.dragBegin(at: lastRightIndexTip))
                    isDragging = true
                }
                // Sustained fist → no additional event.
            } else if isDragging {
                actions.append(.dragEnd(at: lastRightIndexTip))
                isDragging = false
            }

            // Scroll — circular motion. Feed the left index tip to the
            // detector whenever the hand is visible and NOT in a drag
            // or click/shaka pose. The detector watches for the tip
            // tracing a loop in the air and emits scroll pulses
            // proportional to the rotation speed. A stationary or
            // linear-motion hand does nothing — only a real circle
            // produces scroll.
            let scrollGestureAllowed =
                !isDragging &&
                left.gesture != .pinch &&
                left.gesture != .fist &&
                left.gesture != .shaka
            if scrollGestureAllowed,
               let tip = left.snapshot.landmarks[.indexTip]?.position {
                scrollDetector.observe(point: tip, at: now)
            } else {
                // Suppressed gestures reset the detector so a click or
                // drag can't leak into a stale rotation reading.
                scrollDetector.reset()
            }

            // Step the detector to pull out the scroll delta for this
            // frame (may be nil when the motion isn't circular enough).
            if let delta = scrollDetector.step(now: now) {
                actions.append(.scroll(deltaY: delta))
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

            // Shaka → Cmd+Tab. Edge-triggered with debounce so the user
            // can cycle apps by flapping the pose in and out, but
            // classifier noise doesn't spam the shortcut.
            if !isDragging && !isScrolling &&
               left.gesture == .shaka &&
               lastLeftGesture != .shaka {
                let longEnough = lastAppSwitcherTime
                    .map { now.timeIntervalSince($0) >= appSwitcherDebounce } ?? true
                if longEnough {
                    actions.append(.appSwitcher)
                    lastAppSwitcherTime = now
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
            // Reset scroll state so a hand briefly out of frame can't
            // leak an old rotation into the next session.
            scrollDetector.reset()
            lastLeftGesture = .none
        }

        // Track the right hand's gesture for the two-fists edge trigger
        // on the next frame. `.none` when the hand is missing so a
        // briefly-dropped frame doesn't fake a fresh edge transition.
        lastRightGesture = right?.gesture ?? .none

        return actions
    }
}

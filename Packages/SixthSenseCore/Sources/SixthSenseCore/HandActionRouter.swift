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

    /// How long the right hand must be held in a fist pose before
    /// Mission Control fires. Kept short so the user doesn't feel like
    /// they're holding forever — the noise immunity comes from the
    /// grace period below, not from a long hold.
    public var missionControlHoldDuration: TimeInterval = 0.25

    /// When the right hand flaps briefly out of `.fist` (single-frame
    /// misclassification), we treat the hold as still alive if the
    /// last fist observation was less than this long ago. Without this,
    /// Vision dropping confidence on one frame resets the whole hold
    /// and the user can never build up enough sustained time.
    public var rightFistGracePeriod: TimeInterval = 0.15

    /// Minimum time between successive Mission Control triggers. Blocks
    /// re-fires from the same continuous hold — the user has to
    /// release the fist and enter it again before the next one.
    public var missionControlDebounce: TimeInterval = 1.0

    // MARK: - State

    /// The last smoothed index-tip position of the right hand (normalized
    /// Vision coords). Used as the click target when the left hand pinches
    /// and as the anchor for dragBegin / dragEnd.
    private var lastRightIndexTip: CGPoint = CGPoint(x: 0.5, y: 0.5)

    /// Previous left-hand gesture — used to detect edge transitions.
    private var lastLeftGesture: DetectedHandGesture = .none

    /// Timestamp of the last click emitted, for temporal debounce.
    private var lastClickTime: Date?

    /// Timestamp of the last Cmd+Tab emitted.
    private var lastAppSwitcherTime: Date?

    /// Timestamp of the last Mission Control emitted.
    private var lastMissionControlTime: Date?

    /// Timestamp at which the right hand entered a fist pose, or `nil`
    /// when the right hand is not currently in a fist. Used to compute
    /// the hold duration before Mission Control fires.
    private var rightFistEnteredAt: Date?

    /// Timestamp of the most recent frame where the right hand was
    /// classified as a fist. We use the gap between this and `now` to
    /// decide whether a brief non-fist frame is classifier noise (keep
    /// the hold alive) or a real release (reset the hold).
    private var rightFistLastSeenAt: Date?

    /// Whether Mission Control has already fired for the current
    /// continuous fist hold. Clears when the right hand leaves the
    /// fist pose, so the next entry can fire again.
    private var rightFistFired: Bool = false

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

        // Right hand → cursor movement. Moves with the index tip when the
        // hand is in a cursor-friendly pose, but FREEZES during a right
        // fist so the user can hold the Mission Control trigger without
        // the cursor being yanked toward the curled finger's position.
        // The pause also gives the classifier a stable 400ms window to
        // confirm the fist without the user's hand having to fight the
        // cursor drift.
        if let right,
           right.gesture != .fist,
           let indexLandmark = right.snapshot.landmarks[.indexTip],
           indexLandmark.isConfident {
            let raw = indexLandmark.position
            let smoothed = smoother.smooth(raw, timestamp: now.timeIntervalSinceReferenceDate)
            actions.append(.moveCursor(normalized: smoothed))
            lastRightIndexTip = smoothed
        } else if right == nil {
            // Right hand gone — forget the smoother's history so the next
            // fresh entry doesn't get dragged toward the stale position.
            smoother.reset()
        }
        // Note: when right.gesture == .fist we intentionally skip the
        // move AND leave the smoother untouched. lastRightIndexTip stays
        // at the pre-fist location, so click/drag targets keep aiming
        // at the spot the user was pointing at before closing their fist.

        // Right fist held → Mission Control. The hold is robust against
        // brief classifier drops: if the right hand flaps to something
        // other than `.fist` for less than `rightFistGracePeriod`, we
        // keep the hold alive. Only a sustained release (≥ grace period
        // with no fist frame) clears the timer. This fixes the case
        // where Vision loses confidence on the fingertips mid-hold.
        let rightIsFist = right?.gesture == .fist
        if rightIsFist {
            if rightFistEnteredAt == nil {
                rightFistEnteredAt = now
            }
            rightFistLastSeenAt = now
        } else if let lastSeen = rightFistLastSeenAt,
                  now.timeIntervalSince(lastSeen) < rightFistGracePeriod {
            // Still inside the grace window — the non-fist frame is
            // treated as noise; keep the hold alive untouched.
        } else {
            // Real release (or never engaged). Reset everything.
            rightFistEnteredAt = nil
            rightFistLastSeenAt = nil
            rightFistFired = false
        }

        // After updating the timers, check whether we crossed the hold
        // threshold on this frame. This runs regardless of the current
        // frame's pose so a noise frame inside the grace window still
        // lets us fire as soon as the hold matures.
        if let start = rightFistEnteredAt,
           !rightFistFired,
           now.timeIntervalSince(start) >= missionControlHoldDuration {
            let longEnough = lastMissionControlTime
                .map { now.timeIntervalSince($0) >= missionControlDebounce } ?? true
            if longEnough {
                actions.append(.missionControl)
                lastMissionControlTime = now
                rightFistFired = true
            }
        }

        // Left hand → drag (fist) + click (pinch) + scroll (circle) +
        // shaka (app switcher).
        if let left {
            // Drag state machine. Left fist alone starts a drag.
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

        return actions
    }
}

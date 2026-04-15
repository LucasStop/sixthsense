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
/// Mental model: "direita clica, esquerda arrasta e rola."
///
/// The right hand is the primary "mouse": cursor + click + Mission
/// Control. The left hand handles the gestures that either need a free
/// cursor (scroll) or that need two hands (drag). Click is the one
/// action available on both hands, for convenience.
///
/// Rules:
///
///   • Cursor → ALWAYS the right hand's smoothed index tip, when right
///     is in a cursor-friendly pose (pointing, openHand, or none) with
///     a confident index-tip landmark. When right is in an action pose
///     (pinch, fist, shaka) or not visible, the cursor freezes at its
///     last smoothed position. The left hand never drives the cursor
///     — its only job during a right-hand action is to provide its
///     own independent gestures.
///
///   • Click (either hand `.pinch` edge) → click at the last known
///     cursor position. Edge-triggered so sustained pinches don't
///     spam. Each hand has its own debounce so alternating rapid
///     clicks work. Suppressed while dragging or scrolling.
///
///   • Drag (left hand `.fist`) → emits `.dragBegin` on the frame the
///     left hand enters `.fist`, and `.dragEnd` when it releases or
///     disappears. The right hand continues driving the cursor during
///     the drag, so the module dispatches moveCursor as
///     `leftMouseDragged`. Two-handed by design — you can't drag
///     across the screen with a single hand.
///
///   • Scroll (left hand circular motion) → scroll wheel pulses. Only
///     the left hand feeds the detector so the right hand (cursor)
///     stays free. Tracing a circle with the right would drag the
///     cursor in a circle across the screen, so it's intentionally
///     not supported.
///
///   • Mission Control (right `.shaka` edge) → `.missionControl`.
///   • App switcher ⌘+Tab (left `.shaka` edge) → `.appSwitcher`.
///
/// When either hand disappears, its per-hand state resets so the next
/// fresh entry is a clean edge trigger, and any active drag ends safely.
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

    /// Minimum time between successive Mission Control triggers. Blocks
    /// back-to-back swipes from firing twice when the wrist bounces at
    /// the peak of the upward motion.
    public var missionControlDebounce: TimeInterval = 1.0

    // MARK: - State

    /// Last smoothed cursor position (normalized Vision coords). Shared
    /// across hands so click/drag anchor to wherever the cursor is,
    /// regardless of which hand drove it there.
    private var lastIndexTip: CGPoint = CGPoint(x: 0.5, y: 0.5)

    /// Previous-frame gesture of each hand, used for edge detection
    /// (pinch → click, shaka → shortcut). Reset to `.none` when the
    /// hand disappears so the next entry is a clean edge trigger.
    private var lastLeftGesture: DetectedHandGesture = .none
    private var lastRightGesture: DetectedHandGesture = .none

    /// Per-hand click debounce — each hand has its own cooldown so a
    /// click with the left doesn't suppress a click with the right.
    private var lastLeftClickTime: Date?
    private var lastRightClickTime: Date?

    /// Timestamp of the last Cmd+Tab emitted.
    private var lastAppSwitcherTime: Date?

    /// Timestamp of the last Mission Control emitted.
    private var lastMissionControlTime: Date?

    /// Which hand currently owns an active drag, or `nil` when no drag
    /// is in progress. Only one drag can be active at a time — the
    /// first hand to enter `.fist` claims it, and only that hand's
    /// release or disappearance ends it.
    private var draggingHand: HandChirality?

    /// Whether a drag is currently active. Exposed so HandCommandModule
    /// can decide whether `moveCursor` should dispatch as a plain
    /// `mouseMoved` or as a `leftMouseDragged`.
    public var isDragging: Bool { draggingHand != nil }

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

        // ───────────────────────────────────────────────────────────
        // 1. CURSOR — right hand only. When right is in a cursor-
        //    friendly pose (pointing/openHand/none) with a confident
        //    index-tip landmark, move the cursor. When right is in
        //    an action pose or not visible, the cursor FREEZES at its
        //    last position. The left hand never drives the cursor.
        // ───────────────────────────────────────────────────────────
        if let right,
           isCursorFriendly(right),
           let indexLandmark = right.snapshot.landmarks[.indexTip],
           indexLandmark.isConfident {
            let raw = indexLandmark.position
            let smoothed = smoother.smooth(raw, timestamp: now.timeIntervalSinceReferenceDate)
            actions.append(.moveCursor(normalized: smoothed))
            lastIndexTip = smoothed
        } else if right == nil {
            // Right hand gone — forget the smoother's history so the
            // next fresh entry doesn't drag toward a stale position.
            smoother.reset()
        }

        // ───────────────────────────────────────────────────────────
        // 2. DRAG — left hand only. Emits dragBegin on the transition
        //    into `.fist`, dragEnd when the left releases or
        //    disappears. The right hand keeps driving the cursor so
        //    the drag can span the screen.
        // ───────────────────────────────────────────────────────────
        if let left {
            if left.gesture == .fist {
                if !isDragging {
                    actions.append(.dragBegin(at: lastIndexTip))
                    draggingHand = .left
                }
            } else if isDragging {
                actions.append(.dragEnd(at: lastIndexTip))
                draggingHand = nil
            }
        } else if isDragging {
            // Left hand vanished mid-drag — fail-safe release so the
            // user isn't stuck with a held mouse button.
            actions.append(.dragEnd(at: lastIndexTip))
            draggingHand = nil
        }

        // ───────────────────────────────────────────────────────────
        // 3. SHAKA — system shortcuts, edge-triggered per hand.
        //    Right shaka = Mission Control. Left shaka = ⌘+Tab.
        // ───────────────────────────────────────────────────────────
        if let right, right.gesture == .shaka && lastRightGesture != .shaka {
            let longEnough = lastMissionControlTime
                .map { now.timeIntervalSince($0) >= missionControlDebounce } ?? true
            if longEnough {
                actions.append(.missionControl)
                lastMissionControlTime = now
            }
        }
        if let left, left.gesture == .shaka && lastLeftGesture != .shaka {
            let longEnough = lastAppSwitcherTime
                .map { now.timeIntervalSince($0) >= appSwitcherDebounce } ?? true
            if longEnough {
                actions.append(.appSwitcher)
                lastAppSwitcherTime = now
            }
        }

        // ───────────────────────────────────────────────────────────
        // 4. SCROLL — left hand only. Feed the detector from the left
        //    index tip when the left hand is visible in a cursor-
        //    friendly pose and NOT dragging. Right-hand circular
        //    motion is intentionally not supported so tracing a
        //    circle never drags the cursor in circles across the
        //    screen.
        // ───────────────────────────────────────────────────────────
        if !isDragging,
           let left,
           isCursorFriendly(left),
           let tip = left.snapshot.landmarks[.indexTip]?.position {
            scrollDetector.observe(point: tip, at: now)
        } else {
            scrollDetector.reset()
        }
        if let delta = scrollDetector.step(now: now) {
            actions.append(.scroll(deltaY: delta))
        }

        // ───────────────────────────────────────────────────────────
        // 5. CLICK — pinch edge-trigger per hand, independent debounce.
        //    Both hands can click for convenience; the anchor is
        //    always the last known cursor position. Suppressed while
        //    dragging or scrolling.
        // ───────────────────────────────────────────────────────────
        if !isDragging && !isScrolling {
            if let right, right.gesture == .pinch && lastRightGesture != .pinch {
                let longEnough = lastRightClickTime
                    .map { now.timeIntervalSince($0) >= clickDebounce } ?? true
                if longEnough {
                    actions.append(.click(at: lastIndexTip))
                    lastRightClickTime = now
                }
            }
            if let left, left.gesture == .pinch && lastLeftGesture != .pinch {
                let longEnough = lastLeftClickTime
                    .map { now.timeIntervalSince($0) >= clickDebounce } ?? true
                if longEnough {
                    actions.append(.click(at: lastIndexTip))
                    lastLeftClickTime = now
                }
            }
        }

        // ───────────────────────────────────────────────────────────
        // 6. PER-HAND STATE — remember this frame's gesture so the
        //    next frame can detect edge transitions. Missing hand
        //    resets to .none so re-entry triggers cleanly.
        // ───────────────────────────────────────────────────────────
        lastRightGesture = right?.gesture ?? .none
        lastLeftGesture = left?.gesture ?? .none

        return actions
    }

    // MARK: - Helpers

    /// Returns `true` if the hand's pose is one where the index tip is
    /// a sensible cursor target. Action poses (fist, pinch, shaka)
    /// return `false`.
    private func isCursorFriendly(_ hand: HandReading) -> Bool {
        switch hand.gesture {
        case .pointing, .openHand, .none:
            return true
        case .fist, .pinch, .shaka:
            return false
        }
    }
}

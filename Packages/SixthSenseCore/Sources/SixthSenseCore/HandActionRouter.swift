import Foundation
import CoreGraphics

// MARK: - Hand Action

/// High-level action produced by the HandActionRouter in response to one or
/// two HandReadings. Consumed by HandCommandModule, which translates each
/// case into CGEvent-based cursor / keyboard injection.
public enum HandAction: Sendable, Equatable {
    // Cursor (right hand)
    case moveCursor(normalized: CGPoint)
    case click(at: CGPoint)
    case doubleClick(at: CGPoint)
    case dragBegin(at: CGPoint)
    case dragEnd(at: CGPoint)
    case scroll(deltaY: Int32)

    // Global shortcuts (left hand)
    case missionControl
    case showDesktop
    case switchSpaceLeft
    case switchSpaceRight
    case holdCommand
    case releaseCommand
}

// MARK: - Hand Action Router

/// Pure state machine that maps hand readings to high-level actions. Keeps
/// gesture history so it can detect click debouncing, drag begin/end, and
/// "held-down" modifier states. Has no side effects and depends on nothing
/// outside SixthSenseCore, so it is 100% unit-testable.
///
/// Usage: the HandCommand module creates one router and feeds every frame
/// through `process(left:right:)`. The returned actions get forwarded to a
/// cursor and keyboard controller.
public struct HandActionRouter: Sendable {

    // MARK: - Tunable parameters

    /// Time window within which a second pinch counts as a double-click.
    public var doubleClickWindow: TimeInterval = 0.35

    /// Left-edge x threshold for "pointing left" gesture.
    public var leftEdgeThreshold: CGFloat = 0.25

    /// Right-edge x threshold for "pointing right" gesture.
    public var rightEdgeThreshold: CGFloat = 0.75

    // MARK: - State

    private var lastRightGesture: DetectedHandGesture = .none
    private var lastLeftGesture: DetectedHandGesture = .none

    private var lastClickTime: Date?
    private var lastClickPosition: CGPoint = .zero

    public private(set) var isDragging: Bool = false
    public private(set) var isCommandHeld: Bool = false

    private var lastSwitchSpaceTime: Date?
    private var lastMissionControlTime: Date?
    private var lastShowDesktopTime: Date?

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

        if let right {
            actions.append(contentsOf: processRightHand(right, now: now))
        } else {
            // Right hand gone — end any in-progress drag safely.
            if isDragging {
                actions.append(.dragEnd(at: lastClickPosition))
                isDragging = false
            }
            lastRightGesture = .none
        }

        if let left {
            actions.append(contentsOf: processLeftHand(left, now: now))
        } else {
            // Left hand gone — release any held command modifier.
            if isCommandHeld {
                actions.append(.releaseCommand)
                isCommandHeld = false
            }
            lastLeftGesture = .none
        }

        return actions
    }

    // MARK: - Right hand

    private mutating func processRightHand(_ reading: HandReading, now: Date) -> [HandAction] {
        var actions: [HandAction] = []
        let gesture = reading.gesture

        // Cursor movement (pointing) — use index tip as the anchor.
        if gesture == .pointing, let indexTip = reading.snapshot.position(of: .indexTip) {
            actions.append(.moveCursor(normalized: indexTip))
            lastClickPosition = indexTip
        }

        // Pinch edge-trigger: only fire when transitioning INTO pinch, so
        // holding the pinch doesn't spam clicks.
        if gesture == .pinch && lastRightGesture != .pinch {
            let clickPoint = reading.snapshot.position(of: .indexTip) ?? lastClickPosition
            lastClickPosition = clickPoint

            if let last = lastClickTime, now.timeIntervalSince(last) < doubleClickWindow {
                actions.append(.doubleClick(at: clickPoint))
                lastClickTime = nil
            } else {
                actions.append(.click(at: clickPoint))
                lastClickTime = now
            }
        }

        // Fist = drag. Enter drag on transition INTO fist, exit on leaving.
        if gesture == .fist && !isDragging {
            let dragPoint = reading.snapshot.position(of: .wrist) ?? lastClickPosition
            actions.append(.dragBegin(at: dragPoint))
            isDragging = true
        } else if gesture != .fist && isDragging {
            actions.append(.dragEnd(at: lastClickPosition))
            isDragging = false
        }

        // Open hand = scroll. For now, produce a constant deltaY per frame
        // while the hand is open. A real implementation would integrate
        // wrist velocity, but this keeps the router trivially testable.
        if gesture == .openHand {
            actions.append(.scroll(deltaY: 5))
        }

        lastRightGesture = gesture
        return actions
    }

    // MARK: - Left hand

    private mutating func processLeftHand(_ reading: HandReading, now: Date) -> [HandAction] {
        var actions: [HandAction] = []
        let gesture = reading.gesture

        // Fist held = command key held. Toggle on transitions.
        if gesture == .fist && !isCommandHeld {
            actions.append(.holdCommand)
            isCommandHeld = true
        } else if gesture != .fist && isCommandHeld {
            actions.append(.releaseCommand)
            isCommandHeld = false
        }

        // Mission Control on pinch edge-trigger (with 1s debounce).
        if gesture == .pinch && lastLeftGesture != .pinch {
            if lastMissionControlTime.map({ now.timeIntervalSince($0) > 1.0 }) ?? true {
                actions.append(.missionControl)
                lastMissionControlTime = now
            }
        }

        // Show desktop on openHand edge-trigger.
        if gesture == .openHand && lastLeftGesture != .openHand {
            if lastShowDesktopTime.map({ now.timeIntervalSince($0) > 1.0 }) ?? true {
                actions.append(.showDesktop)
                lastShowDesktopTime = now
            }
        }

        // Pointing + hand position near the edge triggers Space switching.
        // Debounced per direction to avoid rapid-fire during sustained points.
        if gesture == .pointing, let wrist = reading.snapshot.position(of: .wrist) {
            if wrist.x < leftEdgeThreshold {
                if lastSwitchSpaceTime.map({ now.timeIntervalSince($0) > 0.8 }) ?? true {
                    actions.append(.switchSpaceLeft)
                    lastSwitchSpaceTime = now
                }
            } else if wrist.x > rightEdgeThreshold {
                if lastSwitchSpaceTime.map({ now.timeIntervalSince($0) > 0.8 }) ?? true {
                    actions.append(.switchSpaceRight)
                    lastSwitchSpaceTime = now
                }
            }
        }

        lastLeftGesture = gesture
        return actions
    }
}

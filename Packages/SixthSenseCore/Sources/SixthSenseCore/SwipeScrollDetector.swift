import Foundation
import CoreGraphics

// MARK: - Swipe Scroll Detector

/// Impulse-based scroll driver. Instead of comparing index-tip vs wrist
/// (which has a natural bias toward "index is above wrist" whenever the
/// user lifts their hand), this looks at the wrist's vertical VELOCITY
/// over a short trailing window. When the velocity spikes above a
/// threshold, we interpret it as a deliberate flick and emit a pulse of
/// scroll that decays over the next few frames — exactly like inertial
/// scrolling on a trackpad after you flick two fingers.
///
/// Everything is pure math and state, no Vision or CGEvent calls. Fed
/// samples via `observe(wristY:at:)`, produces deltas via `step(now:)`,
/// and resets on `reset()`.
public struct SwipeScrollDetector: Sendable {

    // MARK: - Tunables

    /// Window over which we measure velocity. Too short and jitter
    /// registers as swipes; too long and the detector feels sluggish.
    public var velocityWindow: TimeInterval = 0.18

    /// Minimum wrist speed (normalized units / second) before a motion
    /// counts as a swipe. A relaxed hand at rest hovers around 0.1-0.3
    /// units/s of measurement noise; a real flick hits 2-4 easily.
    public var swipeVelocityThreshold: Double = 1.2

    /// Once a swipe fires, we block further swipe detections until this
    /// much time has passed. Prevents a single physical flick from
    /// counting as multiple events as the hand decelerates.
    public var swipeCooldown: TimeInterval = 0.15

    /// Per-frame multiplier applied to the current momentum velocity.
    /// 0.88 means "keep 88% each frame" — at 30 FPS the momentum drops
    /// to ~30% of initial after about half a second.
    public var momentumDecay: Double = 0.88

    /// Below this momentum magnitude we snap to zero and stop emitting.
    public var momentumMinMagnitude: Double = 0.08

    /// Pixels of scroll wheel delta per 1.0 unit of momentum velocity.
    /// Higher values = faster scroll. Clamped by `maxDeltaPerFrame`.
    public var pixelsPerUnit: Double = 18

    /// Hard cap on the per-frame scroll delta. Keeps very fast flicks
    /// from overshooting by hundreds of pixels at once.
    public var maxDeltaPerFrame: Int32 = 42

    /// Maximum momentum velocity. Extra swipes beyond this saturate.
    public var maxMomentum: Double = 4.5

    // MARK: - State

    private var samples: [Sample] = []
    private var lastSwipeAt: Date?
    private var momentumVelocity: Double = 0  // signed: positive = scroll up

    /// Whether there's an active momentum pulse decaying right now.
    /// The HandActionRouter exposes this so the training card can light
    /// up a "rolando" indicator mid-flick.
    public var isScrolling: Bool {
        abs(momentumVelocity) > momentumMinMagnitude
    }

    public init() {}

    // MARK: - Sample intake

    /// Feed a fresh wrist Y reading (normalized Vision coordinates).
    /// The detector looks at the trailing window to decide whether this
    /// sample completes a swipe.
    public mutating func observe(wristY: Double, at time: Date) {
        samples.append(Sample(y: wristY, time: time))

        // Drop samples older than the velocity window so the buffer
        // stays bounded and fresh.
        let cutoff = time.addingTimeInterval(-velocityWindow)
        while let first = samples.first, first.time < cutoff {
            samples.removeFirst()
        }

        // Not enough data to compute a meaningful velocity yet.
        guard samples.count >= 3 else { return }

        let velocity = currentVelocity()

        // Cooldown: wait out the previous swipe before firing a new one.
        if let last = lastSwipeAt, time.timeIntervalSince(last) < swipeCooldown {
            return
        }

        if abs(velocity) >= swipeVelocityThreshold {
            // A positive velocity (wrist moving up in Vision coords =
            // visible upward motion in the mirrored camera feed) flicks
            // the page upward. Negative flicks it down.
            let direction: Double = velocity > 0 ? 1.0 : -1.0
            let magnitude = min(abs(velocity), maxMomentum)

            // If the new swipe is in the SAME direction as the current
            // momentum, add to it (stacking flicks). If it's opposite,
            // replace the momentum with the new signed value.
            if sign(momentumVelocity) == direction && abs(momentumVelocity) > 0 {
                momentumVelocity = clampMomentum(momentumVelocity + direction * magnitude * 0.6)
            } else {
                momentumVelocity = clampMomentum(direction * magnitude)
            }

            lastSwipeAt = time
        }
    }

    // MARK: - Momentum step

    /// Call this every frame AFTER observe(). Returns the scroll wheel
    /// delta (in pixels) that should be dispatched this frame, or `nil`
    /// when the momentum has faded below the minimum threshold.
    public mutating func step(now: Date = Date()) -> Int32? {
        guard abs(momentumVelocity) > momentumMinMagnitude else {
            momentumVelocity = 0
            return nil
        }

        let pixels = momentumVelocity * pixelsPerUnit
        let clamped = Int32(pixels.rounded().clampedToInt32(max: maxDeltaPerFrame))

        // Apply exponential decay for the next frame.
        momentumVelocity *= momentumDecay

        return clamped == 0 ? nil : clamped
    }

    /// Forget all state. Called when the left hand disappears or the
    /// user switches to a pose that suppresses scroll (pinch/fist).
    public mutating func reset() {
        samples.removeAll()
        lastSwipeAt = nil
        momentumVelocity = 0
    }

    // MARK: - Internals

    /// Linear regression slope of Y against time for the samples in the
    /// velocity window. Units: normalized-Y per second.
    private func currentVelocity() -> Double {
        guard samples.count >= 2,
              let first = samples.first,
              let last = samples.last else {
            return 0
        }
        let dt = last.time.timeIntervalSince(first.time)
        guard dt > 0 else { return 0 }
        return (last.y - first.y) / dt
    }

    private func clampMomentum(_ v: Double) -> Double {
        min(max(v, -maxMomentum), maxMomentum)
    }

    private func sign(_ v: Double) -> Double {
        v > 0 ? 1 : (v < 0 ? -1 : 0)
    }

    // MARK: - Sample type

    private struct Sample: Sendable {
        let y: Double
        let time: Date
    }
}

// MARK: - Helpers

private extension Double {
    func clampedToInt32(max: Int32) -> Double {
        let m = Double(max)
        return Swift.min(Swift.max(self, -m), m)
    }
}

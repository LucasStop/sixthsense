import Foundation
import CoreGraphics

// MARK: - Circular Scroll Detector

/// Treats the left hand's index tip like a physical scroll wheel: the user
/// traces a circle in the air with the finger, and the page scrolls
/// proportionally to the angular velocity.
///
/// Conventions (Vision uses bottom-left origin, so y increases upward):
///   • Counter-clockwise rotation → scroll UP (positive deltaY in CGEvent).
///   • Clockwise rotation         → scroll DOWN (negative deltaY).
///   • Stationary / linear motion → nothing.
///
/// The math:
///   1. Buffer a trailing window of (point, time) samples (~400ms).
///   2. Drop samples that are too old.
///   3. Compute the centroid of the window.
///   4. Compute `angle = atan2(y - cy, x - cx)` for each sample.
///   5. Unwrap the angle across the ±π boundary so one full loop is 2π.
///   6. Require a minimum radius (the trajectory must actually span the
///      plane, not just wiggle on a line) and a minimum angular span
///      (at least a quarter-turn visible in the buffer) before activating.
///   7. Emit scroll delta = (angular velocity × pixelsPerRadian) each
///      frame, clamped to `maxDeltaPerFrame` and snapped to 0 below
///      `minAngularVelocity`.
///
/// No Vision / CGEvent calls — pure state and math, fully testable.
public struct CircularScrollDetector: Sendable {

    // MARK: - Tunables

    /// Length of the trailing window used to compute the centroid and
    /// angular velocity. 0.45s at 30fps ≈ 13-14 samples, enough to resolve
    /// half a revolution of a moderately paced circle.
    public var window: TimeInterval = 0.45

    /// Minimum mean radius (normalized units) of the buffered points
    /// around the centroid. A hand wiggling on a straight line has a
    /// near-zero perpendicular spread and won't pass this. 0.025 is about
    /// 1/40th of the frame diagonal — small but not noise.
    public var minRadius: Double = 0.025

    /// Minimum angular span covered by the buffered samples before we
    /// consider the motion "circular enough". 0.9 radians ≈ 51° — a
    /// clear quarter-turn or so. Lower values activate faster but make
    /// the detector more sensitive to wiggle.
    public var minAngularSpan: Double = 0.9

    /// Below this angular velocity (rad/s) we consider the motion
    /// stopped and emit nothing. 1.2 rad/s ≈ one full revolution every
    /// ~5s — slower than that is almost certainly drift, not a scroll.
    public var minAngularVelocity: Double = 1.2

    /// Circularity score threshold: the ratio of the radial spread
    /// (how round the trajectory is) to the bounding-box diagonal. A
    /// perfect circle is ~0.35, a straight line is ~0. We require
    /// 0.18 — clearly curved, but forgiving of imperfect tracing.
    public var minCircularity: Double = 0.18

    /// Pixels of scroll wheel delta per 1.0 radian/second of angular
    /// velocity. Higher = faster scroll. At 30fps, a 2π rad/s rotation
    /// (one full revolution per second) at 36 px·s/rad = 226 px/s,
    /// capped to 42 px per frame (~126 px/s) — so the cap kicks in for
    /// fast spins, which matches the intent of the pixel clamp.
    public var pixelsPerRadianSecond: Double = 36

    /// Absolute cap on per-frame scroll delta. Prevents over-fast spins
    /// from teleporting the page hundreds of pixels in one frame.
    public var maxDeltaPerFrame: Int32 = 42

    // MARK: - State

    private var samples: [Sample] = []

    /// Running value of the last emitted angular velocity, so callers
    /// can light up a "scrolling" indicator mid-motion.
    private var lastAngularVelocity: Double = 0

    /// True while the detector is actively emitting scroll pulses.
    /// Mirrors the shape of the old swipe detector so router consumers
    /// don't have to change.
    public var isScrolling: Bool {
        abs(lastAngularVelocity) >= minAngularVelocity
    }

    public init() {}

    // MARK: - Sample intake

    /// Feed a fresh index-tip position (normalized Vision coords).
    /// The detector uses the trailing window to estimate rotation.
    public mutating func observe(point: CGPoint, at time: Date) {
        samples.append(Sample(x: Double(point.x), y: Double(point.y), time: time))

        // Drop samples older than the window so the buffer stays bounded.
        let cutoff = time.addingTimeInterval(-window)
        while let first = samples.first, first.time < cutoff {
            samples.removeFirst()
        }
    }

    // MARK: - Emit

    /// Call this every frame after `observe`. Returns the signed scroll
    /// delta in pixels, or `nil` when the motion isn't circular enough
    /// to emit a pulse this frame.
    public mutating func step(now: Date = Date()) -> Int32? {
        // Need enough samples and enough elapsed time to compute a
        // meaningful angular velocity.
        guard samples.count >= 5,
              let first = samples.first,
              let last = samples.last else {
            lastAngularVelocity = 0
            return nil
        }

        let dt = last.time.timeIntervalSince(first.time)
        guard dt > 0.05 else {
            lastAngularVelocity = 0
            return nil
        }

        // Compute centroid.
        let n = Double(samples.count)
        let cx = samples.map(\.x).reduce(0, +) / n
        let cy = samples.map(\.y).reduce(0, +) / n

        // Radii from centroid.
        let radii = samples.map { sample -> Double in
            let dx = sample.x - cx
            let dy = sample.y - cy
            return (dx * dx + dy * dy).squareRoot()
        }
        let meanRadius = radii.reduce(0, +) / n

        guard meanRadius >= minRadius else {
            lastAngularVelocity = 0
            return nil
        }

        // Compute unwrapped angle series.
        var angles: [Double] = []
        angles.reserveCapacity(samples.count)
        var previous: Double = 0
        for (i, sample) in samples.enumerated() {
            let raw = atan2(sample.y - cy, sample.x - cx)
            if i == 0 {
                angles.append(raw)
                previous = raw
                continue
            }
            var delta = raw - previous
            // Unwrap across ±π boundary.
            if delta >  .pi { delta -= 2 * .pi }
            if delta < -.pi { delta += 2 * .pi }
            let unwrapped = angles[i - 1] + delta
            angles.append(unwrapped)
            previous = raw
        }

        // Total angular span covered during the window (signed).
        let totalAngle = angles.last! - angles.first!
        let absSpan = abs(totalAngle)

        guard absSpan >= minAngularSpan else {
            lastAngularVelocity = 0
            return nil
        }

        // Circularity: compare the radial RMS against the bounding-box
        // diagonal. A straight line has near-zero radial variance along
        // the perpendicular direction — but since we're measuring radii
        // from a centroid on the line, the radii all roughly equal half
        // the line length, which would falsely look "circular". To
        // disambiguate, require the bounding box to have BOTH width and
        // height above a threshold, i.e. the trajectory actually uses
        // both axes of the plane.
        let xs = samples.map(\.x)
        let ys = samples.map(\.y)
        let xSpan = (xs.max() ?? 0) - (xs.min() ?? 0)
        let ySpan = (ys.max() ?? 0) - (ys.min() ?? 0)
        let minSide = min(xSpan, ySpan)
        let maxSide = max(xSpan, ySpan)
        guard maxSide > 0 else {
            lastAngularVelocity = 0
            return nil
        }
        let aspect = minSide / maxSide

        // Aspect ~0 means a thin line, ~1 means a roughly-circular loop.
        // minCircularity (0.18) rejects obvious lines without demanding
        // a perfect round shape.
        guard aspect >= minCircularity else {
            lastAngularVelocity = 0
            return nil
        }

        // Angular velocity in radians/second.
        let omega = totalAngle / dt
        lastAngularVelocity = omega

        guard abs(omega) >= minAngularVelocity else { return nil }

        // Sign convention: atan2 returns angles that INCREASE as the
        // point moves counter-clockwise (positive y is up in Vision,
        // which is already the standard math convention). So a positive
        // omega = counter-clockwise = scroll UP = positive CGEvent
        // deltaY. Perfect — no sign flip needed.
        let rawPixels = omega * pixelsPerRadianSecond
        let capped = max(min(rawPixels, Double(maxDeltaPerFrame)), -Double(maxDeltaPerFrame))
        let delta = Int32(capped.rounded())
        return delta == 0 ? nil : delta
    }

    /// Forget all state. Called when the left hand disappears or
    /// transitions into a pose that suppresses scroll.
    public mutating func reset() {
        samples.removeAll()
        lastAngularVelocity = 0
    }

    // MARK: - Sample type

    private struct Sample: Sendable {
        let x: Double
        let y: Double
        let time: Date
    }
}

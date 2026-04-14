import Foundation
import CoreGraphics

// MARK: - One Euro Filter

/// Adaptive low-pass filter optimized for noisy real-time input (hand
/// tracking, gaze tracking, etc.). When the signal is stationary, it
/// smooths aggressively to eliminate jitter. When the signal moves quickly,
/// it loosens the smoothing so the output stays responsive. The filter is
/// deterministic and pure (no global state), so it's trivial to unit-test.
///
/// Reference: Casiez, Roussel & Vogel (2012).
/// "1€ Filter: A Simple Speed-based Low-pass Filter for Noisy Input in
///  Interactive Systems."
///
/// Tuning heuristics for hand-tracking cursor control at ~30 FPS:
///   - minCutoff ~ 1.5 Hz → strong smoothing when the hand is still
///   - beta      ~ 0.05  → gives up smoothing on moderate motion so the
///                         cursor stays responsive. Higher than the 0.007
///                         used for mouse hardware because hand jitter is
///                         much larger than mouse noise.
///   - dCutoff   ~ 1.0 Hz → smoothing applied to the velocity estimate itself
public struct OneEuroFilter: Sendable {

    // MARK: - Tunables

    public var minCutoff: Double
    public var beta: Double
    public var dCutoff: Double

    // MARK: - Internal state

    private var xFilter: LowPass
    private var dxFilter: LowPass
    private var lastTime: TimeInterval?

    public init(minCutoff: Double = 1.5, beta: Double = 0.05, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
        self.xFilter = LowPass()
        self.dxFilter = LowPass()
    }

    /// Feed a new sample and get the smoothed output.
    ///
    /// - Parameters:
    ///   - value: raw noisy reading
    ///   - timestamp: monotonic time in seconds (any epoch — we only use deltas)
    public mutating func filter(_ value: Double, timestamp: TimeInterval) -> Double {
        // First sample — bootstrap the low-passes so we don't return 0.
        guard let last = lastTime else {
            lastTime = timestamp
            _ = xFilter.apply(value, alpha: 1.0)
            _ = dxFilter.apply(0.0, alpha: 1.0)
            return value
        }

        let dt = max(timestamp - last, 1e-6)
        lastTime = timestamp

        // Estimate the signal's velocity and smooth it too.
        let prev = xFilter.lastValue ?? value
        let dx = (value - prev) / dt
        let edx = dxFilter.apply(dx, alpha: alpha(dt: dt, cutoff: dCutoff))

        // Adaptive cutoff: fast motion → higher cutoff → less smoothing.
        let cutoff = minCutoff + beta * abs(edx)
        return xFilter.apply(value, alpha: alpha(dt: dt, cutoff: cutoff))
    }

    /// Forget all history. Use when the tracked entity disappears so the
    /// next fresh sample is not dragged toward the old position.
    public mutating func reset() {
        xFilter = LowPass()
        dxFilter = LowPass()
        lastTime = nil
    }

    // MARK: - Math

    private func alpha(dt: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    // MARK: - Low-pass helper

    private struct LowPass: Sendable {
        private(set) var lastValue: Double?

        mutating func apply(_ value: Double, alpha: Double) -> Double {
            let result: Double
            if let prev = lastValue {
                result = alpha * value + (1.0 - alpha) * prev
            } else {
                result = value
            }
            lastValue = result
            return result
        }
    }
}

// MARK: - Cursor Smoother (2D)

/// Convenience wrapper that applies a One Euro Filter independently to the
/// X and Y components of a CGPoint. Used by HandActionRouter to smooth the
/// right hand's index tip before emitting `.moveCursor` actions.
public struct CursorSmoother: Sendable {
    private var filterX: OneEuroFilter
    private var filterY: OneEuroFilter

    public init(minCutoff: Double = 1.5, beta: Double = 0.05, dCutoff: Double = 1.0) {
        self.filterX = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
        self.filterY = OneEuroFilter(minCutoff: minCutoff, beta: beta, dCutoff: dCutoff)
    }

    public mutating func smooth(_ point: CGPoint, timestamp: TimeInterval) -> CGPoint {
        let sx = filterX.filter(Double(point.x), timestamp: timestamp)
        let sy = filterY.filter(Double(point.y), timestamp: timestamp)
        return CGPoint(x: sx, y: sy)
    }

    public mutating func reset() {
        filterX.reset()
        filterY.reset()
    }
}

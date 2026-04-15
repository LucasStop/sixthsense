import Foundation

// MARK: - Upward Swipe Detector

/// Pure state machine that detects a deliberate upward swipe of a single
/// tracked point (normalized y in Vision coordinates, where 0 = bottom of
/// frame and 1 = top). Used by `HandActionRouter` to trigger Mission
/// Control from a fast right-hand wrist lift.
///
/// The detector keeps a rolling window of samples and computes the average
/// vertical velocity across the window. When the upward velocity crosses
/// `velocityThreshold`, `step()` returns `true` once and then consumes the
/// buffer so the same motion cannot fire twice. Debouncing between swipes
/// is the caller's responsibility.
///
/// The wrist is preferred over fingertip positions because Vision tracks
/// the wrist landmark with higher confidence across hand poses — the user
/// can be pointing, open-handed, or mid-pinch and the wrist y stays
/// reliable.
public struct UpwardSwipeDetector: Sendable {

    // MARK: - Tunables

    /// How far back in time to keep samples. Short enough to capture a
    /// single flick (~200-300ms), long enough to average out per-frame
    /// jitter from Vision.
    public var windowDuration: TimeInterval = 0.25

    /// Minimum upward velocity (normalized y units per second) required
    /// to register as a swipe. Casual cursor movements sit around 0.2-0.6
    /// u/s; a deliberate wrist lift easily clears 1.8-2.5 u/s.
    public var velocityThreshold: Double = 1.8

    /// Minimum sample count before a velocity measurement is trusted.
    /// Protects against single-frame spikes.
    public var minSamples: Int = 3

    /// Minimum elapsed time between the oldest and newest sample before a
    /// velocity measurement is trusted. Rejects measurements from samples
    /// that arrived in the same millisecond burst.
    public var minSpan: TimeInterval = 0.05

    // MARK: - State

    private var samples: [(y: Double, time: Date)] = []

    public init(
        windowDuration: TimeInterval = 0.25,
        velocityThreshold: Double = 1.8,
        minSamples: Int = 3,
        minSpan: TimeInterval = 0.05
    ) {
        self.windowDuration = windowDuration
        self.velocityThreshold = velocityThreshold
        self.minSamples = minSamples
        self.minSpan = minSpan
    }

    // MARK: - API

    /// Record a wrist y sample at the given time. Drops any samples that
    /// fell out of the rolling window.
    public mutating func observe(y: Double, at time: Date) {
        samples.append((y: y, time: time))
        while let oldest = samples.first,
              time.timeIntervalSince(oldest.time) > windowDuration {
            samples.removeFirst()
        }
    }

    /// Check whether the current buffer indicates an upward swipe. Returns
    /// `true` exactly once per swipe; subsequent calls with the same
    /// buffer return `false` because the buffer is consumed on a hit.
    public mutating func step() -> Bool {
        guard samples.count >= minSamples,
              let oldest = samples.first,
              let newest = samples.last else {
            return false
        }
        let dt = newest.time.timeIntervalSince(oldest.time)
        guard dt >= minSpan else { return false }

        let dy = newest.y - oldest.y
        let velocity = dy / dt

        if velocity >= velocityThreshold {
            samples.removeAll()
            return true
        }
        return false
    }

    /// Drop all samples. Call when the tracked hand disappears so the
    /// next entry doesn't inherit a stale trajectory.
    public mutating func reset() {
        samples.removeAll()
    }

    /// Exposed for diagnostics — how many samples are currently buffered.
    public var sampleCount: Int { samples.count }
}

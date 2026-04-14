import Testing
import Foundation
import CoreGraphics
@testable import SixthSenseCore

// MARK: - OneEuroFilter (1D)

@Test func oneEuroFirstSampleIsPassthrough() {
    var filter = OneEuroFilter()
    let out = filter.filter(0.42, timestamp: 0)
    #expect(out == 0.42)
}

@Test func oneEuroConstantInputConvergesToTheValue() {
    var filter = OneEuroFilter()
    var out: Double = 0

    // Feed the same value 30 frames apart at 30 FPS.
    for i in 0..<30 {
        out = filter.filter(1.0, timestamp: TimeInterval(i) / 30.0)
    }

    // After settling, the output should equal (or be extremely close to) 1.0.
    #expect(abs(out - 1.0) < 1e-6)
}

@Test func oneEuroDampensSmallHighFrequencyNoise() {
    // Build two 60-frame series: one is a clean signal at 0.5; the other
    // is 0.5 with ±0.02 jitter every frame. The filter's output range
    // should be visibly tighter than the raw jitter range.
    var filtered = OneEuroFilter()
    let dt = 1.0 / 60.0

    var outputs: [Double] = []
    for i in 0..<60 {
        let noisy = 0.5 + (i.isMultiple(of: 2) ? 0.02 : -0.02)
        outputs.append(filtered.filter(noisy, timestamp: TimeInterval(i) * dt))
    }

    // Skip the first few bootstrap samples; compare the steady-state spread.
    let steady = outputs.dropFirst(10)
    let minSteady = steady.min() ?? 0
    let maxSteady = steady.max() ?? 0
    let spread = maxSteady - minSteady

    // Raw spread is 0.04. Filtered spread should be meaningfully smaller.
    #expect(spread < 0.03)
}

@Test func oneEuroResetForgetsHistory() {
    var filter = OneEuroFilter()

    // Feed a series of high values, then reset, then feed a single low value.
    for i in 0..<10 {
        _ = filter.filter(1.0, timestamp: TimeInterval(i) * 0.033)
    }
    filter.reset()
    let out = filter.filter(0.0, timestamp: 0.5)

    // After reset, the first sample is passthrough again — no lingering bias.
    #expect(out == 0.0)
}

@Test func oneEuroRespectsExplicitCutoffParameters() {
    // minCutoff=0 means the filter should smooth hard when stationary.
    var strong = OneEuroFilter(minCutoff: 0.1, beta: 0.0)
    var weak = OneEuroFilter(minCutoff: 10.0, beta: 0.0)

    // Feed the same step change.
    _ = strong.filter(0.0, timestamp: 0)
    _ = weak.filter(0.0, timestamp: 0)

    let sOut = strong.filter(1.0, timestamp: 0.1)
    let wOut = weak.filter(1.0, timestamp: 0.1)

    // The strongly-smoothed filter should lag further behind the step.
    #expect(sOut < wOut)
}

// MARK: - CursorSmoother (2D)

@Test func cursorSmootherFirstPointPassesThrough() {
    var smoother = CursorSmoother()
    let out = smoother.smooth(CGPoint(x: 0.5, y: 0.3), timestamp: 0)
    #expect(out.x == 0.5)
    #expect(out.y == 0.3)
}

@Test func cursorSmootherResetDropsState() {
    var smoother = CursorSmoother()
    _ = smoother.smooth(CGPoint(x: 1.0, y: 1.0), timestamp: 0)
    _ = smoother.smooth(CGPoint(x: 1.0, y: 1.0), timestamp: 0.033)
    smoother.reset()
    let out = smoother.smooth(CGPoint(x: 0.0, y: 0.0), timestamp: 1.0)
    #expect(out.x == 0.0)
    #expect(out.y == 0.0)
}

@Test func cursorSmootherReducesJitterAroundStationaryPoint() {
    // Oscillate around (0.5, 0.5) with ±0.01 noise at 60 Hz for a second.
    var smoother = CursorSmoother()
    let dt = 1.0 / 60.0

    var xs: [CGFloat] = []
    var ys: [CGFloat] = []
    for i in 0..<60 {
        let nx = 0.5 + (i.isMultiple(of: 2) ? 0.01 : -0.01)
        let ny = 0.5 + (i.isMultiple(of: 3) ? 0.01 : -0.01)
        let out = smoother.smooth(CGPoint(x: nx, y: ny), timestamp: TimeInterval(i) * dt)
        xs.append(out.x)
        ys.append(out.y)
    }

    let xsSteady = xs.dropFirst(15)
    let ysSteady = ys.dropFirst(15)

    let xSpread = (xsSteady.max() ?? 0) - (xsSteady.min() ?? 0)
    let ySpread = (ysSteady.max() ?? 0) - (ysSteady.min() ?? 0)

    // Both axes should be meaningfully tighter than the raw 0.02 range.
    #expect(xSpread < 0.015)
    #expect(ySpread < 0.015)
}

@Test func cursorSmootherStaysResponsiveOnFastMotion() {
    // A signal that sweeps from 0 to 1 in 0.5 seconds (1 sample per 16.67ms)
    // should still reach close to 1 by the end — the smoother is not
    // allowed to clamp responsiveness to stationary levels forever.
    var smoother = CursorSmoother()
    let dt = 1.0 / 60.0

    var last = CGPoint.zero
    for i in 0..<30 {
        let t = TimeInterval(i) * dt
        let x = CGFloat(i) / 30.0
        last = smoother.smooth(CGPoint(x: x, y: x), timestamp: t)
    }

    // After the ramp, the output should have followed the input most of
    // the way. 0.7 is a generous lower bound.
    #expect(last.x > 0.7)
    #expect(last.y > 0.7)
}

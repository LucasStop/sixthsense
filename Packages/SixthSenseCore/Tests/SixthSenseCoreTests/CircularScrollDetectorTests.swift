import Testing
import Foundation
import CoreGraphics
@testable import SixthSenseCore

// MARK: - CircularScrollDetector

/// Pure-math tests for the circular scroll wheel detector. Each test
/// feeds a sequence of (point, time) samples and checks the emitted
/// deltas, exactly how the router uses it in production.

// MARK: - Helpers

/// Generate N points along a circle of radius `radius` around the
/// origin, covering `totalAngle` radians starting from `startAngle`.
/// Positive totalAngle = counter-clockwise (math convention).
private func circlePoints(
    count: Int,
    radius: Double,
    startAngle: Double = 0,
    totalAngle: Double,
    center: CGPoint = CGPoint(x: 0.5, y: 0.5)
) -> [CGPoint] {
    guard count > 1 else { return [] }
    var result: [CGPoint] = []
    for i in 0..<count {
        let t = Double(i) / Double(count - 1)
        let angle = startAngle + totalAngle * t
        let x = Double(center.x) + radius * cos(angle)
        let y = Double(center.y) + radius * sin(angle)
        result.append(CGPoint(x: x, y: y))
    }
    return result
}

/// Feed the detector a time series at a fixed frame interval, returning
/// all non-nil scroll deltas produced across the sequence.
@discardableResult
private func feed(
    _ detector: inout CircularScrollDetector,
    points: [CGPoint],
    startingAt start: Date = Date(),
    frameInterval: TimeInterval = 1.0 / 60.0
) -> [Int32] {
    var deltas: [Int32] = []
    for (i, p) in points.enumerated() {
        let t = start.addingTimeInterval(frameInterval * Double(i))
        detector.observe(point: p, at: t)
        if let d = detector.step(now: t) {
            deltas.append(d)
        }
    }
    return deltas
}

// MARK: - Baseline behaviour

@Test func newDetectorReportsNotScrolling() {
    let detector = CircularScrollDetector()
    #expect(detector.isScrolling == false)
}

@Test func stationarySamplesProduceNoScroll() {
    var detector = CircularScrollDetector()
    let stationary = Array(repeating: CGPoint(x: 0.5, y: 0.5), count: 30)
    let deltas = feed(&detector, points: stationary)
    #expect(deltas.isEmpty)
    #expect(detector.isScrolling == false)
}

@Test func straightLineProducesNoScroll() {
    // A straight horizontal flick — the trajectory has a clear direction
    // but zero perpendicular spread. The circularity check (bounding-box
    // aspect ratio) must reject it.
    var detector = CircularScrollDetector()
    var xs: [CGPoint] = []
    for i in 0..<24 {
        let t = Double(i) / 23.0
        xs.append(CGPoint(x: 0.3 + 0.4 * t, y: 0.5))
    }
    let deltas = feed(&detector, points: xs)
    #expect(deltas.isEmpty)
    #expect(detector.isScrolling == false)
}

@Test func verticalLineProducesNoScroll() {
    // Same idea but vertical. The old swipe detector fired on this;
    // the circular detector must not.
    var detector = CircularScrollDetector()
    var ys: [CGPoint] = []
    for i in 0..<24 {
        let t = Double(i) / 23.0
        ys.append(CGPoint(x: 0.5, y: 0.3 + 0.4 * t))
    }
    let deltas = feed(&detector, points: ys)
    #expect(deltas.isEmpty)
    #expect(detector.isScrolling == false)
}

// MARK: - Circular motion → scroll

@Test func counterClockwiseCircleProducesPositiveScroll() {
    // atan2 increases counter-clockwise (standard math convention). A
    // CCW loop generates positive angular velocity → positive deltaY →
    // scroll UP.
    var detector = CircularScrollDetector()
    let loop = circlePoints(
        count: 24,
        radius: 0.08,
        startAngle: 0,
        totalAngle: 2 * .pi  // one full counter-clockwise loop
    )
    let deltas = feed(&detector, points: loop)
    #expect(!deltas.isEmpty)
    #expect(deltas.contains { $0 > 0 })
    // No negative deltas in a monotonic CCW rotation.
    #expect(deltas.allSatisfy { $0 >= 0 })
}

@Test func clockwiseCircleProducesNegativeScroll() {
    // Clockwise loop = negative total angle = negative angular
    // velocity = scroll DOWN.
    var detector = CircularScrollDetector()
    let loop = circlePoints(
        count: 24,
        radius: 0.08,
        startAngle: 0,
        totalAngle: -2 * .pi  // one full clockwise loop
    )
    let deltas = feed(&detector, points: loop)
    #expect(!deltas.isEmpty)
    #expect(deltas.contains { $0 < 0 })
    #expect(deltas.allSatisfy { $0 <= 0 })
}

@Test func partialArcMustExceedMinimumAngularSpan() {
    // A tiny 30° arc (~0.52 rad) should NOT be enough to activate the
    // detector — it's below the 0.9 rad (~51°) threshold.
    var detector = CircularScrollDetector()
    let tinyArc = circlePoints(
        count: 24,
        radius: 0.08,
        totalAngle: Double.pi / 6  // 30 degrees
    )
    let deltas = feed(&detector, points: tinyArc)
    #expect(deltas.isEmpty)
}

@Test func tinyRadiusIsRejectedAsJitter() {
    // A circle too small to be a deliberate gesture — just hand tremor.
    // minRadius is 0.025, so radius 0.005 must be rejected.
    var detector = CircularScrollDetector()
    let tiny = circlePoints(
        count: 24,
        radius: 0.005,
        totalAngle: 2 * .pi
    )
    let deltas = feed(&detector, points: tiny)
    #expect(deltas.isEmpty)
}

@Test func slowRotationBelowMinVelocityEmitsNothing() {
    // Full loop spread over 2.5 seconds. Angular velocity = 2π/2.5 ≈
    // 2.51 rad/s — above 1.2 threshold so it DOES emit. To exercise the
    // velocity floor, make the full loop take 6 seconds: 2π/6 ≈ 1.04
    // rad/s, below 1.2. Should be silent.
    var detector = CircularScrollDetector()
    let slowLoop = circlePoints(
        count: 60,  // 60 frames
        radius: 0.08,
        totalAngle: 2 * .pi
    )
    // 60 frames × 100ms = 6 seconds.
    let deltas = feed(&detector, points: slowLoop, frameInterval: 0.1)
    #expect(deltas.isEmpty)
}

@Test func fastRotationProducesLargerDelta() {
    // A full revolution in 0.4s (ω ≈ 15.7 rad/s) should produce larger
    // deltas than one in 1.5s (ω ≈ 4.2 rad/s).
    var fast = CircularScrollDetector()
    var slow = CircularScrollDetector()

    let fastLoop = circlePoints(count: 24, radius: 0.08, totalAngle: 2 * .pi)
    let slowLoop = circlePoints(count: 24, radius: 0.08, totalAngle: 2 * .pi)

    let fastDeltas = feed(&fast, points: fastLoop, frameInterval: 0.4 / 24.0)
    let slowDeltas = feed(&slow, points: slowLoop, frameInterval: 1.5 / 24.0)

    let maxFast = fastDeltas.map { abs(Int($0)) }.max() ?? 0
    let maxSlow = slowDeltas.map { abs(Int($0)) }.max() ?? 0
    #expect(maxFast >= maxSlow)
}

@Test func deltaIsClampedByMaxDeltaPerFrame() {
    // An absurdly fast spin — full rev in 0.1 seconds, ω ≈ 62.8 rad/s.
    // At 36 px-s/rad, raw pixels ≈ 2260/frame. Must clamp to 42.
    var detector = CircularScrollDetector()
    let loop = circlePoints(count: 24, radius: 0.08, totalAngle: 2 * .pi)
    let deltas = feed(&detector, points: loop, frameInterval: 0.1 / 24.0)
    #expect(!deltas.isEmpty)
    #expect(deltas.allSatisfy { abs($0) <= 42 })
}

// MARK: - Reset

@Test func resetForgetsAllState() {
    var detector = CircularScrollDetector()
    let loop = circlePoints(count: 24, radius: 0.08, totalAngle: 2 * .pi)
    _ = feed(&detector, points: loop)

    detector.reset()
    #expect(detector.isScrolling == false)
    // Calling step on an empty buffer should produce nil.
    #expect(detector.step(now: Date()) == nil)
}

@Test func rotationStoppedMeansDetectorStopsScrolling() {
    var detector = CircularScrollDetector()
    let start = Date()
    let loop = circlePoints(count: 24, radius: 0.08, totalAngle: 2 * .pi)
    _ = feed(&detector, points: loop, startingAt: start)

    // Now hold the hand steady at the last position for 30 frames.
    let holdStart = start.addingTimeInterval(24 / 60.0)
    let held = Array(repeating: loop.last!, count: 30)
    _ = feed(&detector, points: held, startingAt: holdStart)

    #expect(detector.isScrolling == false)
}

@Test func reverseRotationFlipsSign() {
    // Start with CCW, then switch to CW. The first phase emits
    // positive deltas; after the direction flip and enough samples in
    // the new direction, the sign should be negative.
    var detector = CircularScrollDetector()

    let ccw = circlePoints(
        count: 24,
        radius: 0.08,
        startAngle: 0,
        totalAngle: 2 * .pi
    )
    let cw = circlePoints(
        count: 24,
        radius: 0.08,
        startAngle: 2 * .pi,
        totalAngle: -2 * .pi
    )

    let t0 = Date()
    let ccwDeltas = feed(&detector, points: ccw, startingAt: t0)
    #expect(ccwDeltas.contains { $0 > 0 })

    let t1 = t0.addingTimeInterval(24 / 60.0)
    let cwDeltas = feed(&detector, points: cw, startingAt: t1)
    #expect(cwDeltas.contains { $0 < 0 })
}

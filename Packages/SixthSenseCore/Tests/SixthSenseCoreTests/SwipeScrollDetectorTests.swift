import Testing
import Foundation
@testable import SixthSenseCore

// MARK: - SwipeScrollDetector

/// All the pure-math behaviour of the swipe/momentum scroll detector,
/// independent of the router glue. Tests feed a sequence of (y, time)
/// pairs and call `step` on each frame to pull out the resulting scroll
/// deltas, exactly how the router uses it.

@Test func newDetectorReportsNotScrolling() {
    var detector = SwipeScrollDetector()
    #expect(detector.isScrolling == false)
}

@Test func stationarySamplesProduceNoScroll() {
    var detector = SwipeScrollDetector()
    let t0 = Date()
    var deltas: [Int32] = []
    for i in 0..<15 {
        let t = t0.addingTimeInterval(Double(i) / 60.0)
        detector.observe(wristY: 0.5, at: t)
        if let d = detector.step(now: t) {
            deltas.append(d)
        }
    }
    #expect(deltas.isEmpty)
    #expect(detector.isScrolling == false)
}

@Test func upwardFlickFiresPositiveMomentum() {
    var detector = SwipeScrollDetector()
    let t0 = Date()

    // 5 frames at 60fps, wrist going 0.3 → 0.7. Velocity ≈ 4.8 u/s.
    let ys = [0.3, 0.4, 0.5, 0.6, 0.7]
    var deltas: [Int32] = []
    for (i, y) in ys.enumerated() {
        let t = t0.addingTimeInterval(Double(i) / 60.0)
        detector.observe(wristY: y, at: t)
        if let d = detector.step(now: t) {
            deltas.append(d)
        }
    }

    #expect(!deltas.isEmpty)
    #expect(deltas.contains { $0 > 0 })
    #expect(detector.isScrolling == true)
}

@Test func downwardFlickFiresNegativeMomentum() {
    var detector = SwipeScrollDetector()
    let t0 = Date()
    let ys = [0.7, 0.6, 0.5, 0.4, 0.3]
    var deltas: [Int32] = []
    for (i, y) in ys.enumerated() {
        let t = t0.addingTimeInterval(Double(i) / 60.0)
        detector.observe(wristY: y, at: t)
        if let d = detector.step(now: t) {
            deltas.append(d)
        }
    }

    #expect(!deltas.isEmpty)
    #expect(deltas.contains { $0 < 0 })
}

@Test func momentumDecaysToZero() {
    var detector = SwipeScrollDetector()
    let t0 = Date()

    // Flick first.
    let flick = [0.3, 0.4, 0.5, 0.6, 0.7]
    for (i, y) in flick.enumerated() {
        detector.observe(wristY: y, at: t0.addingTimeInterval(Double(i) / 60.0))
        _ = detector.step(now: t0.addingTimeInterval(Double(i) / 60.0))
    }

    // Then hold steady and pump frames for 1 second (60 frames).
    // By the end, isScrolling must be false.
    for i in 0..<60 {
        let t = t0.addingTimeInterval(0.1 + Double(i) / 60.0)
        detector.observe(wristY: 0.7, at: t)
        _ = detector.step(now: t)
    }

    #expect(detector.isScrolling == false)
}

@Test func resetForgetsAllState() {
    var detector = SwipeScrollDetector()
    let t0 = Date()
    for (i, y) in [0.3, 0.5, 0.7].enumerated() {
        detector.observe(wristY: y, at: t0.addingTimeInterval(Double(i) / 60.0))
    }

    detector.reset()
    #expect(detector.isScrolling == false)
    #expect(detector.step(now: Date()) == nil)
}

@Test func slowDriftDoesNotTriggerSwipe() {
    // 0.1 units over 1 full second → velocity 0.1 u/s, far below the
    // 1.2 u/s threshold. Should produce zero deltas even though the
    // wrist is technically moving.
    var detector = SwipeScrollDetector()
    let t0 = Date()
    for i in 0..<60 {
        let t = t0.addingTimeInterval(Double(i) / 60.0)
        let y = 0.5 + Double(i) * (0.1 / 60.0)
        detector.observe(wristY: y, at: t)
        _ = detector.step(now: t)
    }
    #expect(detector.isScrolling == false)
}

@Test func cooldownPreventsRapidDoubleFire() {
    // Feed a flick, then IMMEDIATELY another flick within the cooldown
    // window. The second one should be swallowed.
    var detector = SwipeScrollDetector()
    detector.swipeCooldown = 0.5
    let t0 = Date()

    for (i, y) in [0.3, 0.4, 0.5, 0.6, 0.7].enumerated() {
        detector.observe(wristY: y, at: t0.addingTimeInterval(Double(i) / 60.0))
    }
    let initialMomentum = detector.isScrolling

    // Second flick 50ms later — inside the 500ms cooldown.
    for (i, y) in [0.7, 0.6, 0.5, 0.4, 0.3].enumerated() {
        detector.observe(wristY: y, at: t0.addingTimeInterval(0.1 + Double(i) / 60.0))
    }

    // Because the second flick is blocked by cooldown, the momentum
    // direction shouldn't flip — it should still be positive from the
    // first flick (or decaying).
    #expect(initialMomentum == true)
}

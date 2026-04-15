import Foundation
import Testing
@testable import SixthSenseCore

// Pure tests for UpwardSwipeDetector. Every test constructs explicit
// timestamps so there's no real-clock dependency.

private func t(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: 1_000_000 + offset)
}

@Test func stationaryWristProducesNoSwipe() {
    var detector = UpwardSwipeDetector()
    for i in 0..<10 {
        detector.observe(y: 0.5, at: t(Double(i) * 0.03))
    }
    #expect(detector.step() == false)
}

@Test func singleSampleDoesNotTriggerSwipe() {
    var detector = UpwardSwipeDetector()
    detector.observe(y: 0.9, at: t(0))
    #expect(detector.step() == false)
}

@Test func slowUpwardDriftDoesNotTriggerSwipe() {
    // 0.2 units over 0.25s = 0.8 u/s, below default threshold of 1.8.
    var detector = UpwardSwipeDetector()
    detector.observe(y: 0.3, at: t(0.00))
    detector.observe(y: 0.35, at: t(0.08))
    detector.observe(y: 0.40, at: t(0.16))
    detector.observe(y: 0.50, at: t(0.25))
    #expect(detector.step() == false)
}

@Test func fastUpwardSwipeFires() {
    // 0.5 units over 0.20s = 2.5 u/s, clearly above threshold.
    var detector = UpwardSwipeDetector()
    detector.observe(y: 0.30, at: t(0.00))
    detector.observe(y: 0.45, at: t(0.07))
    detector.observe(y: 0.60, at: t(0.14))
    detector.observe(y: 0.80, at: t(0.20))
    #expect(detector.step() == true)
}

@Test func downwardSwipeDoesNotFire() {
    // Reverse motion — velocity is negative, never crosses the
    // upward threshold.
    var detector = UpwardSwipeDetector()
    detector.observe(y: 0.80, at: t(0.00))
    detector.observe(y: 0.60, at: t(0.07))
    detector.observe(y: 0.40, at: t(0.14))
    detector.observe(y: 0.20, at: t(0.20))
    #expect(detector.step() == false)
}

@Test func successiveStepsAfterHitReturnFalse() {
    // A successful swipe consumes the buffer — immediately calling
    // step() again with no fresh samples must not re-fire.
    var detector = UpwardSwipeDetector()
    detector.observe(y: 0.30, at: t(0.00))
    detector.observe(y: 0.50, at: t(0.07))
    detector.observe(y: 0.70, at: t(0.14))
    detector.observe(y: 0.90, at: t(0.20))
    #expect(detector.step() == true)
    #expect(detector.step() == false)
}

@Test func staleSamplesOutsideWindowAreDropped() {
    // Samples older than the window duration are dropped, so an old
    // upward motion doesn't bleed into a later stationary period.
    var detector = UpwardSwipeDetector()
    detector.observe(y: 0.30, at: t(0.00))
    detector.observe(y: 0.90, at: t(0.15))
    // Now wait past the window and re-observe stationary samples.
    detector.observe(y: 0.50, at: t(0.60))
    detector.observe(y: 0.50, at: t(0.65))
    detector.observe(y: 0.50, at: t(0.70))
    #expect(detector.step() == false)
}

@Test func resetClearsBufferCompletely() {
    var detector = UpwardSwipeDetector()
    detector.observe(y: 0.30, at: t(0.00))
    detector.observe(y: 0.50, at: t(0.07))
    detector.observe(y: 0.70, at: t(0.14))
    #expect(detector.sampleCount == 3)
    detector.reset()
    #expect(detector.sampleCount == 0)
}

@Test func swipeAfterResetStartsFresh() {
    // After reset, a new swipe must still fire cleanly.
    var detector = UpwardSwipeDetector()
    detector.observe(y: 0.30, at: t(0.00))
    detector.observe(y: 0.50, at: t(0.07))
    detector.observe(y: 0.70, at: t(0.14))
    detector.observe(y: 0.90, at: t(0.20))
    #expect(detector.step() == true)
    detector.reset()

    detector.observe(y: 0.25, at: t(1.00))
    detector.observe(y: 0.45, at: t(1.07))
    detector.observe(y: 0.65, at: t(1.14))
    detector.observe(y: 0.85, at: t(1.20))
    #expect(detector.step() == true)
}

@Test func velocityBelowCustomThresholdDoesNotFire() {
    // Raise the threshold high and confirm a medium swipe no longer fires.
    var detector = UpwardSwipeDetector(velocityThreshold: 5.0)
    detector.observe(y: 0.30, at: t(0.00))
    detector.observe(y: 0.50, at: t(0.07))
    detector.observe(y: 0.70, at: t(0.14))
    detector.observe(y: 0.90, at: t(0.20))
    #expect(detector.step() == false)
}

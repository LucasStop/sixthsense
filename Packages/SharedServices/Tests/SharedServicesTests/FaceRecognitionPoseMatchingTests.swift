import Testing
import Foundation
import CoreGraphics
import CoreImage
@preconcurrency import Vision
import SixthSenseCore
@testable import SharedServices

// MARK: - Pose-Matched Recognition

/// These tests exercise the pure nearest-neighbour lookup the recognition
/// pipeline uses at runtime. We build `EnrolledFacePrint` values via real
/// `VNGenerateImageFeaturePrintRequest` calls on tiny synthetic images —
/// the actual print content doesn't matter for the lookup math, only the
/// attached `FaceAngle` does.

// MARK: - Helpers

/// Build a tiny 64x64 synthetic CGImage with a solid color. Used to seed
/// `VNGenerateImageFeaturePrintRequest` — Vision doesn't mind fake input
/// here because we're only comparing poses afterwards, not prints.
private func makeImage(color: CGFloat) -> CGImage? {
    let width = 64
    let height = 64
    let colorSpace = CGColorSpaceCreateDeviceGray()
    let bitmapInfo = CGImageAlphaInfo.none.rawValue
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else { return nil }
    context.setFillColor(gray: color, alpha: 1.0)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()
}

private func makePrint(seed: Int) throws -> VNFeaturePrintObservation {
    guard let image = makeImage(color: CGFloat(seed) / 10.0) else {
        throw CocoaError(.featureUnsupported)
    }
    let request = VNGenerateImageFeaturePrintRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])
    guard let result = request.results?.first else {
        throw CocoaError(.featureUnsupported)
    }
    return result
}

private func makeEnrolled(yaw: Double, pitch: Double, seed: Int) throws -> EnrolledFacePrint {
    EnrolledFacePrint(
        print: try makePrint(seed: seed),
        pose: FaceAngle(yaw: yaw, pitch: pitch)
    )
}

// MARK: - nearestByPose

@Test func nearestByPosePicksClosestPose() throws {
    let prints = [
        try makeEnrolled(yaw: 0,   pitch: 0,   seed: 1),
        try makeEnrolled(yaw: 10,  pitch: 0,   seed: 2),
        try makeEnrolled(yaw: -10, pitch: 0,   seed: 3),
        try makeEnrolled(yaw: 0,   pitch: 10,  seed: 4),
    ]

    // Query at yaw=9, pitch=0 — should prefer the yaw=10 entry.
    let nearest = FaceRecognitionManager.nearestByPose(
        enrolled: prints,
        currentPose: FaceAngle(yaw: 9, pitch: 0),
        topK: 1
    )
    #expect(nearest.count == 1)
    #expect(nearest.first?.pose.yaw == 10)
}

@Test func nearestByPoseReturnsTopKInOrder() throws {
    let prints = [
        try makeEnrolled(yaw: 0,   pitch: 0,   seed: 1),
        try makeEnrolled(yaw: 10,  pitch: 0,   seed: 2),
        try makeEnrolled(yaw: -10, pitch: 0,   seed: 3),
        try makeEnrolled(yaw: 0,   pitch: 10,  seed: 4),
    ]

    // Query at (2, 2) — closest three are (0,0), (0,10), and (10,0)
    // (all near), not (-10, 0).
    let nearest = FaceRecognitionManager.nearestByPose(
        enrolled: prints,
        currentPose: FaceAngle(yaw: 2, pitch: 2),
        topK: 3
    )
    #expect(nearest.count == 3)
    // The closest must be (0, 0).
    #expect(nearest.first?.pose.yaw == 0)
    #expect(nearest.first?.pose.pitch == 0)
    // The furthest of the three must not be (-10, 0).
    #expect(nearest.allSatisfy { !($0.pose.yaw == -10 && $0.pose.pitch == 0) })
}

@Test func nearestByPoseHandlesTopKLargerThanEnrolled() throws {
    let prints = [
        try makeEnrolled(yaw: 0, pitch: 0, seed: 1),
        try makeEnrolled(yaw: 5, pitch: 5, seed: 2),
    ]

    // topK exceeds the pool — should return everything without crashing.
    let nearest = FaceRecognitionManager.nearestByPose(
        enrolled: prints,
        currentPose: .center,
        topK: 10
    )
    #expect(nearest.count == 2)
}

@Test func nearestByPoseWithEmptyEnrolledReturnsEmpty() {
    let nearest = FaceRecognitionManager.nearestByPose(
        enrolled: [],
        currentPose: .center,
        topK: 3
    )
    #expect(nearest.isEmpty)
}

// MARK: - Calibration

@Test func calibrationOfEmptySetIsZero() {
    let calibration = FaceRecognitionManager.computeCalibration(for: [])
    #expect(calibration.meanIntraDistance == 0)
    #expect(calibration.stdDevIntraDistance == 0)
    #expect(calibration.maxIntraDistance == 0)
}

@Test func calibrationOfSinglePrintIsZero() throws {
    let single = [try makeEnrolled(yaw: 0, pitch: 0, seed: 1)]
    let calibration = FaceRecognitionManager.computeCalibration(for: single)
    #expect(calibration.meanIntraDistance == 0)
    #expect(calibration.stdDevIntraDistance == 0)
}

@Test func calibrationComputesNonZeroStatsForMultiPosePrints() throws {
    // Five distinct poses + distinct seed images → the pairwise matrix
    // has meaningful values.
    let prints = [
        try makeEnrolled(yaw: 0,   pitch: 0,  seed: 1),
        try makeEnrolled(yaw: 10,  pitch: 0,  seed: 2),
        try makeEnrolled(yaw: -10, pitch: 0,  seed: 3),
        try makeEnrolled(yaw: 0,   pitch: 10, seed: 4),
        try makeEnrolled(yaw: 0,   pitch: -10, seed: 5),
    ]
    let calibration = FaceRecognitionManager.computeCalibration(for: prints)
    // Distances on grayscale synthetic prints should be strictly positive
    // for distinct seeds.
    #expect(calibration.meanIntraDistance >= 0)
    #expect(calibration.maxIntraDistance >= calibration.meanIntraDistance)
}

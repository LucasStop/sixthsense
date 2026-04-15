import Foundation
import AppKit
import CoreMedia
import CoreGraphics
@preconcurrency import Vision
import SixthSenseCore

// MARK: - Face Recognition Manager

/// Observes the shared camera pipeline to produce a live gating signal
/// for HandCommand. The goal is "only the enrolled person can use the
/// gestures" — not "someone is at the Mac" — so the recognition pipeline
/// is layered:
///
///   1. Every frame runs `VNDetectFaceLandmarksRequest` (cheap) to get
///      the face bounding box + pose (pitch/yaw/roll).
///   2. At most every `featurePrintInterval` seconds, we crop the face
///      and run `VNGenerateImageFeaturePrintRequest` (expensive).
///   3. The fresh print is compared ONLY against the stored prints whose
///      enrollment pose is closest to the current user pose — a real
///      enrolled user at angle X matches their own capture at angle X
///      tightly, but an intruder who happens to resemble the user at one
///      specific angle no longer slips through because they have to
///      match the current pose too.
///   4. The per-frame distance flows through a ring buffer; the gate
///      only flips to "recognized" after a majority of recent frames
///      agreed, and only flips back to "blocked" after a sustained run
///      of rejections.
///   5. The distance threshold is calibrated per user: at enrollment
///      time we measure how self-similar the user's own captures are
///      across angles, and set the threshold just above that spread.
@MainActor
@Observable
public final class FaceRecognitionManager: FaceGate {

    // MARK: - Tunables

    /// Max pitch/yaw (in degrees) that still counts as "looking at screen".
    public var lookingAtScreenThreshold: Double = 25.0

    /// How many of the pose-closest stored prints to compare against at
    /// recognition time. Comparing against the single closest one is
    /// tightest but flickers at pose boundaries; 3 is a good compromise.
    public var poseMatchTopK: Int = 3

    /// Fallback recognition threshold used when no per-user calibration
    /// has been stored yet (e.g. migrating from an older enrollment).
    public var defaultRecognitionThreshold: Float = 18.0

    /// Minimum interval between expensive feature-print computations.
    public var featurePrintInterval: TimeInterval = 0.2

    /// Recent recognition frames retained for the consensus window.
    public var consensusWindowSize: Int = 5

    /// How many of the last `consensusWindowSize` frames must be "match"
    /// before the gate opens.
    public var consensusMatchesRequired: Int = 3

    /// How many consecutive rejections are required to close the gate.
    public var consensusRejectionsRequired: Int = 5

    /// Grace period after the face temporarily leaves the frame.
    public var recognitionGraceWindow: TimeInterval = 1.5

    // MARK: - Public state

    public private(set) var state: FaceRecognitionState

    public var canUseGestures: Bool { state.canUseGestures }

    /// Exposes the store so views can query `hasEnrolledFace` / clearEnrollment.
    public let store: FaceEmbeddingStore

    // MARK: - Enrollment state (for FaceEnrollmentView)

    public private(set) var enrollmentTargets: [EnrollmentTarget] = []
    public private(set) var enrollmentCompletedIds: Set<Int> = []
    public private(set) var enrollmentCurrentTargetIndex: Int = 0

    public var enrollmentCurrentTarget: EnrollmentTarget? {
        guard enrollmentTargets.indices.contains(enrollmentCurrentTargetIndex) else {
            return nil
        }
        return enrollmentTargets[enrollmentCurrentTargetIndex]
    }

    public var enrollmentTotal: Int { enrollmentTargets.count }
    public var enrollmentProgress: Int { enrollmentCompletedIds.count }

    public private(set) var enrollmentCurrentPose: FaceAngle?
    public private(set) var enrollmentQuality: Float = 0
    public private(set) var isEnrolling: Bool = false
    public private(set) var enrollmentFaceBox: CGRect?

    public var isEnrollmentComplete: Bool {
        !enrollmentTargets.isEmpty &&
        enrollmentCompletedIds.count >= enrollmentTargets.count
    }

    /// Number of feature prints to capture per target during enrollment.
    /// Each target holds for `enrollmentHoldDuration * capturesPerTarget`
    /// so the user naturally maintains the pose while we sample. More
    /// samples per pose = more robust matching.
    public var enrollmentCapturesPerTarget: Int = 5

    // MARK: - Dependencies

    private let cameraManager: any CameraPipeline
    private let subscriberId = "face-recognition"

    /// Pose-tagged prints loaded from disk, keyed by pose for the
    /// nearest-neighbor lookup at recognition time.
    private var enrolledPrints: [EnrolledFacePrint] = []

    /// Per-user recognition threshold, or `nil` if we should fall back
    /// to `defaultRecognitionThreshold`.
    private var calibratedThreshold: Float?

    // MARK: - Internal tracking

    private var isSubscribed = false
    private var lastFeaturePrintAt: Date?
    private var lastRecognizedAt: Date?
    private var recognitionHistory: [RecognitionOutcome] = []
    private var consecutiveRejections: Int = 0
    private let visionQueue = DispatchQueue(
        label: "com.sixthsense.face.vision",
        qos: .userInitiated
    )
    private let faceRequest = VNDetectFaceLandmarksRequest()

    /// Per-frame recognition outcome pushed into the ring buffer.
    private struct RecognitionOutcome: Sendable {
        let timestamp: Date
        let distance: Float
        let isMatch: Bool
    }

    // MARK: - Init

    public init(
        cameraManager: any CameraPipeline,
        store: FaceEmbeddingStore = FaceEmbeddingStore()
    ) {
        self.cameraManager = cameraManager
        self.store = store
        self.state = FaceRecognitionState(mode: store.lockMode)
        if let loaded = store.load() {
            self.enrolledPrints = loaded.prints
            self.calibratedThreshold = loaded.calibration.suggestedThreshold
        }
    }

    // MARK: - Lifecycle

    public func start() {
        if isSubscribed { return }
        reloadFromStore()
        cameraManager.subscribe(id: subscriberId) { [weak self] sampleBuffer in
            Task { @MainActor in
                self?.processFrame(sampleBuffer)
            }
        }
        isSubscribed = true
    }

    public func stop() {
        if isSubscribed {
            cameraManager.unsubscribe(id: subscriberId)
            isSubscribed = false
        }
        recognitionHistory.removeAll()
        consecutiveRejections = 0
        state = FaceRecognitionState(mode: store.lockMode)
    }

    public func reloadFromStore() {
        let mode = store.lockMode
        if let loaded = store.load() {
            enrolledPrints = loaded.prints
            calibratedThreshold = loaded.calibration.suggestedThreshold
        } else {
            enrolledPrints = []
            calibratedThreshold = nil
        }
        recognitionHistory.removeAll()
        consecutiveRejections = 0
        state = FaceRecognitionState(mode: mode)
    }

    public func setLockMode(_ mode: FaceLockMode) {
        store.lockMode = mode
        state = FaceRecognitionState(
            isFaceDetected: state.isFaceDetected,
            isLookingAtScreen: state.isLookingAtScreen,
            isRecognizedUser: state.isRecognizedUser,
            recognitionDistance: state.recognitionDistance,
            mode: mode,
            faceBoundingBox: state.faceBoundingBox
        )
    }

    /// Save a freshly captured enrollment and optionally switch to the
    /// enrolled-face mode automatically. Computes the per-user
    /// calibration from the pairwise distances across `prints`.
    public func enroll(
        prints: [EnrolledFacePrint],
        activateMode: Bool
    ) throws {
        let calibration = Self.computeCalibration(for: prints)
        try store.save(prints: prints, calibration: calibration)
        self.enrolledPrints = prints
        self.calibratedThreshold = calibration.suggestedThreshold
        if activateMode {
            store.lockMode = .enrolledFace
        }
        recognitionHistory.removeAll()
        consecutiveRejections = 0
        state = FaceRecognitionState(mode: store.lockMode)
    }

    public func clearEnrollment() {
        store.clearEnrollment()
        enrolledPrints = []
        calibratedThreshold = nil
        recognitionHistory.removeAll()
        consecutiveRejections = 0
        state = FaceRecognitionState(mode: store.lockMode)
    }

    // MARK: - Guided enrollment flow

    /// Max angular distance (in degrees) the current pose can be from
    /// the target before we accept it.
    public var enrollmentHitRadius: Double = 10.0

    /// Minimum face capture quality accepted for enrollment, 0-1.
    public var enrollmentMinimumQuality: Float = 0.25

    /// Minimum hold duration between captures within the same target.
    /// A full target takes `enrollmentHoldDuration * capturesPerTarget`.
    public var enrollmentHoldDuration: TimeInterval = 0.06

    /// The "zero" pose captured when the first target (center) is hit.
    public private(set) var enrollmentBaselinePose: FaceAngle?

    public func beginGuidedEnrollment(
        targets: [EnrollmentTarget] = EnrollmentTarget.defaultRing
    ) {
        enrollmentTargets = targets
        enrollmentCompletedIds = []
        enrollmentCurrentTargetIndex = 0
        enrollmentCurrentPose = nil
        enrollmentQuality = 0
        enrollmentBuffer = []
        enrollmentFaceBox = nil
        enrollmentBaselinePose = nil
        capturesForCurrentTarget = 0
        lastCaptureAt = nil
        holdStartTime = nil
        isEnrolling = true

        if !isSubscribed {
            cameraManager.subscribe(id: subscriberId) { [weak self] sampleBuffer in
                Task { @MainActor in
                    self?.processFrame(sampleBuffer)
                }
            }
            isSubscribed = true
        }
    }

    public func cancelEnrollment() {
        isEnrolling = false
        enrollmentBuffer = []
        enrollmentCompletedIds = []
        enrollmentCurrentTargetIndex = 0
        enrollmentFaceBox = nil
        enrollmentCurrentPose = nil
        enrollmentQuality = 0
        enrollmentBaselinePose = nil
        capturesForCurrentTarget = 0
        lastCaptureAt = nil
        holdStartTime = nil
    }

    /// Returns the pose-tagged prints captured across all completed
    /// targets. Consumers hand this array to `enroll(prints:activateMode:)`.
    public func capturedEnrollmentPrints() -> [EnrolledFacePrint] {
        enrollmentBuffer
    }

    // MARK: - Internal enrollment state

    private var enrollmentBuffer: [EnrolledFacePrint] = []
    private var holdStartTime: Date?

    /// How many prints we've already captured for the target the user
    /// is currently on. Resets on target advance or cancellation.
    private var capturesForCurrentTarget: Int = 0

    /// Timestamp of the last capture committed for the current target,
    /// so captures within the same target stay spaced by
    /// `enrollmentHoldDuration`.
    private var lastCaptureAt: Date?

    // MARK: - Frame processing

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        if isEnrolling {
            processEnrollmentFrame(pixelBuffer: pixelBuffer)
            return
        }

        guard state.mode != .disabled else {
            if state != FaceRecognitionState(mode: .disabled) {
                state = FaceRecognitionState(mode: .disabled)
            }
            return
        }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .upMirrored,
            options: [:]
        )

        let mode = state.mode
        let shouldRunRecognition = mode == .enrolledFace &&
            shouldRunFeaturePrint(now: Date())

        // Capture a stable snapshot of the recognition config for the
        // background closure — the main-actor state may change before
        // the closure hops back.
        let enrolled = self.enrolledPrints
        let topK = self.poseMatchTopK

        visionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try handler.perform([self.faceRequest])
                guard let face = self.faceRequest.results?.first else {
                    Task { @MainActor in self.handleNoFace() }
                    return
                }

                let bbox = face.boundingBox
                let looking = Self.isLookingAtScreen(
                    face: face,
                    threshold: self.lookingAtScreenThreshold
                )

                if shouldRunRecognition {
                    let currentPose = Self.poseFromFace(face)
                    let distance = Self.computeRecognitionDistance(
                        face: face,
                        pixelBuffer: pixelBuffer,
                        enrolled: enrolled,
                        currentPose: currentPose,
                        topK: topK
                    )
                    Task { @MainActor in
                        self.handleFace(
                            bbox: bbox,
                            looking: looking,
                            distance: distance
                        )
                    }
                } else {
                    Task { @MainActor in
                        self.handleFace(
                            bbox: bbox,
                            looking: looking,
                            distance: nil
                        )
                    }
                }
            } catch {
                // Skip on Vision error.
            }
        }
    }

    private func processEnrollmentFrame(pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .upMirrored,
            options: [:]
        )

        let currentBaseline = enrollmentBaselinePose
        let currentTarget = enrollmentTargets.indices.contains(enrollmentCurrentTargetIndex)
            ? enrollmentTargets[enrollmentCurrentTargetIndex]
            : nil
        let isFirstTarget = (enrollmentCurrentTargetIndex == 0)
        let hitRadius = enrollmentHitRadius
        let minQuality = enrollmentMinimumQuality

        visionQueue.async { [weak self] in
            guard let self else { return }
            do {
                let qualityRequest = VNDetectFaceCaptureQualityRequest()
                try handler.perform([self.faceRequest, qualityRequest])

                guard let face = self.faceRequest.results?.first else {
                    Task { @MainActor in
                        self.enrollmentFaceBox = nil
                        self.enrollmentCurrentPose = nil
                        self.enrollmentQuality = 0
                    }
                    return
                }

                let rawPose = Self.poseFromFace(face)
                let quality: Float = (qualityRequest.results?.first as? VNFaceObservation)?
                    .faceCaptureQuality ?? 0

                let displayPose: FaceAngle
                if let baseline = currentBaseline {
                    displayPose = FaceAngle(
                        yaw: rawPose.yaw - baseline.yaw,
                        pitch: rawPose.pitch - baseline.pitch
                    )
                } else {
                    displayPose = rawPose
                }

                let onTarget: Bool
                if isFirstTarget {
                    onTarget = quality >= minQuality
                } else if let target = currentTarget {
                    onTarget = displayPose.distance(to: target.angle) <= hitRadius &&
                               quality >= minQuality
                } else {
                    onTarget = false
                }

                var capturedPrint: VNFeaturePrintObservation?
                if onTarget {
                    capturedPrint = Self.computeFeaturePrint(
                        face: face,
                        pixelBuffer: pixelBuffer
                    )
                }

                Task { @MainActor in
                    self.enrollmentFaceBox = face.boundingBox
                    self.enrollmentCurrentPose = displayPose
                    self.enrollmentQuality = quality
                    self.applyEnrollmentCapture(
                        onTarget: onTarget,
                        print: capturedPrint,
                        rawPose: rawPose,
                        displayPose: displayPose
                    )
                }
            } catch {
                // Skip on Vision error.
            }
        }
    }

    /// Main-actor side of the enrollment state machine. Captures up to
    /// `enrollmentCapturesPerTarget` prints per target, spacing them by
    /// `enrollmentHoldDuration`, then advances to the next target.
    private func applyEnrollmentCapture(
        onTarget: Bool,
        print capturedPrint: VNFeaturePrintObservation?,
        rawPose: FaceAngle,
        displayPose: FaceAngle
    ) {
        guard isEnrolling else { return }

        if !onTarget {
            holdStartTime = nil
            return
        }

        let now = Date()
        if let start = holdStartTime {
            let heldFor = now.timeIntervalSince(start)
            guard heldFor >= enrollmentHoldDuration else { return }
        } else {
            holdStartTime = now
            return
        }

        guard let capturedPrint else {
            holdStartTime = nil
            return
        }

        guard enrollmentTargets.indices.contains(enrollmentCurrentTargetIndex) else {
            return
        }
        let target = enrollmentTargets[enrollmentCurrentTargetIndex]
        if enrollmentCompletedIds.contains(target.id) {
            holdStartTime = nil
            return
        }

        // Space captures within a single target by the hold duration
        // so we get 5 distinct frames, not 5 frames from one burst.
        if let last = lastCaptureAt,
           now.timeIntervalSince(last) < enrollmentHoldDuration {
            return
        }

        // Snapshot the baseline on the very first committed capture.
        if enrollmentCurrentTargetIndex == 0 &&
           enrollmentBaselinePose == nil &&
           capturesForCurrentTarget == 0 {
            enrollmentBaselinePose = rawPose
        }

        enrollmentBuffer.append(
            EnrolledFacePrint(print: capturedPrint, pose: displayPose)
        )
        capturesForCurrentTarget += 1
        lastCaptureAt = now
        holdStartTime = nil

        // Target is done when we've collected enough prints.
        guard capturesForCurrentTarget >= enrollmentCapturesPerTarget else {
            return
        }

        enrollmentCompletedIds.insert(target.id)
        capturesForCurrentTarget = 0
        lastCaptureAt = nil

        let next = enrollmentCurrentTargetIndex + 1
        if next < enrollmentTargets.count {
            enrollmentCurrentTargetIndex = next
        } else {
            isEnrolling = false
        }
    }

    // MARK: - Feature print computation

    nonisolated static func computeFeaturePrint(
        face: VNFaceObservation,
        pixelBuffer: CVPixelBuffer
    ) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()

        let padded = face.boundingBox.insetBy(dx: -0.1, dy: -0.1)
        let clamped = CGRect(
            x: max(0, padded.origin.x),
            y: max(0, padded.origin.y),
            width: min(1 - max(0, padded.origin.x), padded.width),
            height: min(1 - max(0, padded.origin.y), padded.height)
        )
        request.regionOfInterest = clamped

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .upMirrored,
            options: [:]
        )
        do {
            try handler.perform([request])
            return request.results?.first
        } catch {
            return nil
        }
    }

    private func shouldRunFeaturePrint(now: Date) -> Bool {
        guard !enrolledPrints.isEmpty else { return false }
        guard let last = lastFeaturePrintAt else {
            lastFeaturePrintAt = now
            return true
        }
        if now.timeIntervalSince(last) >= featurePrintInterval {
            lastFeaturePrintAt = now
            return true
        }
        return false
    }

    // MARK: - State transitions

    private func handleNoFace() {
        let now = Date()
        let inGrace = lastRecognizedAt.map { now.timeIntervalSince($0) < recognitionGraceWindow } ?? false
        state = FaceRecognitionState(
            isFaceDetected: false,
            isLookingAtScreen: false,
            isRecognizedUser: inGrace,
            recognitionDistance: state.recognitionDistance,
            mode: state.mode,
            faceBoundingBox: nil
        )
    }

    private func handleFace(
        bbox: CGRect,
        looking: Bool,
        distance: Float?
    ) {
        var recognized = state.isRecognizedUser
        var recognitionDistance = state.recognitionDistance

        if state.mode == .enrolledFace, let distance {
            recognitionDistance = distance
            let threshold = calibratedThreshold ?? defaultRecognitionThreshold
            let frameMatch = distance <= threshold

            // Push outcome into the ring buffer.
            recognitionHistory.append(
                RecognitionOutcome(timestamp: Date(), distance: distance, isMatch: frameMatch)
            )
            while recognitionHistory.count > consensusWindowSize {
                recognitionHistory.removeFirst()
            }

            if frameMatch {
                consecutiveRejections = 0
            } else {
                consecutiveRejections += 1
            }

            // Count matches inside the window.
            let matches = recognitionHistory.filter(\.isMatch).count

            if matches >= consensusMatchesRequired {
                recognized = true
                lastRecognizedAt = Date()
            } else if consecutiveRejections >= consensusRejectionsRequired {
                recognized = false
            }
            // Otherwise keep the previous verdict — hysteresis.
        } else if state.mode == .anyFace {
            recognized = true
        } else if state.mode == .enrolledFace {
            let now = Date()
            if let last = lastRecognizedAt,
               now.timeIntervalSince(last) > recognitionGraceWindow {
                recognized = false
            }
        }

        state = FaceRecognitionState(
            isFaceDetected: true,
            isLookingAtScreen: looking,
            isRecognizedUser: recognized,
            recognitionDistance: recognitionDistance,
            mode: state.mode,
            faceBoundingBox: bbox
        )
    }

    // MARK: - Vision math

    nonisolated static func isLookingAtScreen(
        face: VNFaceObservation,
        threshold: Double
    ) -> Bool {
        let pitchDeg = abs(((face.pitch?.doubleValue) ?? 0) * 180.0 / .pi)
        let yawDeg = abs(((face.yaw?.doubleValue) ?? 0) * 180.0 / .pi)
        return pitchDeg < threshold && yawDeg < threshold
    }

    nonisolated static func poseFromFace(_ face: VNFaceObservation) -> FaceAngle {
        let yawRad = face.yaw?.doubleValue ?? 0
        let pitchRad = face.pitch?.doubleValue ?? 0
        return FaceAngle(
            yaw: yawRad * 180.0 / .pi,
            pitch: pitchRad * 180.0 / .pi
        )
    }

    /// Pose-matched recognition distance. Instead of checking against
    /// ALL enrolled prints (which lets an attacker pass by matching any
    /// one of nine angles), we pick the `topK` prints whose stored pose
    /// is closest to the current user's pose and take the minimum
    /// feature-print distance among those. An intruder now has to
    /// match the user at the SAME angle, not any angle.
    nonisolated static func computeRecognitionDistance(
        face: VNFaceObservation,
        pixelBuffer: CVPixelBuffer,
        enrolled: [EnrolledFacePrint],
        currentPose: FaceAngle,
        topK: Int
    ) -> Float {
        guard !enrolled.isEmpty else { return .infinity }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let padded = face.boundingBox.insetBy(dx: -0.1, dy: -0.1)
        let clamped = CGRect(
            x: max(0, padded.origin.x),
            y: max(0, padded.origin.y),
            width: min(1 - max(0, padded.origin.x), padded.width),
            height: min(1 - max(0, padded.origin.y), padded.height)
        )

        let region = CGRect(
            x: clamped.origin.x * CGFloat(width),
            y: clamped.origin.y * CGFloat(height),
            width: clamped.width * CGFloat(width),
            height: clamped.height * CGFloat(height)
        )

        let printRequest = VNGenerateImageFeaturePrintRequest()
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .upMirrored,
            options: [:]
        )
        printRequest.regionOfInterest = CGRect(
            x: region.origin.x / CGFloat(width),
            y: region.origin.y / CGFloat(height),
            width: region.width / CGFloat(width),
            height: region.height / CGFloat(height)
        )

        do {
            try handler.perform([printRequest])
            guard let observation = printRequest.results?.first else {
                return .infinity
            }

            let candidates = nearestByPose(
                enrolled: enrolled,
                currentPose: currentPose,
                topK: topK
            )

            var smallest: Float = .infinity
            for enrolled in candidates {
                var distance: Float = 0
                do {
                    try observation.computeDistance(&distance, to: enrolled.print)
                    if distance < smallest { smallest = distance }
                } catch {
                    continue
                }
            }
            return smallest
        } catch {
            return .infinity
        }
    }

    /// Pick the `topK` enrolled prints whose pose is closest to
    /// `currentPose` (in degree space). Ties and tiny K values resolve
    /// gracefully — never returns more than `enrolled.count`.
    nonisolated static func nearestByPose(
        enrolled: [EnrolledFacePrint],
        currentPose: FaceAngle,
        topK: Int
    ) -> [EnrolledFacePrint] {
        guard !enrolled.isEmpty else { return [] }
        let k = max(1, min(topK, enrolled.count))
        return enrolled
            .sorted { $0.pose.distance(to: currentPose) < $1.pose.distance(to: currentPose) }
            .prefix(k)
            .map { $0 }
    }

    /// Compute per-user recognition calibration from the pairwise
    /// distances across the enrollment set. We only compare prints at
    /// DIFFERENT poses (same pose yields near-zero, which would bias the
    /// mean downward and make the threshold too loose).
    nonisolated static func computeCalibration(
        for prints: [EnrolledFacePrint]
    ) -> FaceRecognitionCalibration {
        guard prints.count >= 2 else {
            return FaceRecognitionCalibration(
                meanIntraDistance: 0,
                stdDevIntraDistance: 0,
                maxIntraDistance: 0
            )
        }

        var distances: [Float] = []
        distances.reserveCapacity(prints.count * prints.count / 2)

        for i in 0..<prints.count {
            for j in (i + 1)..<prints.count {
                let a = prints[i]
                let b = prints[j]
                // Skip near-identical poses (same target, consecutive
                // captures) — those give inflated self-similarity.
                if a.pose.distance(to: b.pose) < 3.0 { continue }
                var d: Float = 0
                do {
                    try a.print.computeDistance(&d, to: b.print)
                    distances.append(d)
                } catch {
                    continue
                }
            }
        }

        guard !distances.isEmpty else {
            return FaceRecognitionCalibration(
                meanIntraDistance: 0,
                stdDevIntraDistance: 0,
                maxIntraDistance: 0
            )
        }

        let mean = distances.reduce(0, +) / Float(distances.count)
        let variance = distances.map { pow($0 - mean, 2) }.reduce(0, +) / Float(distances.count)
        let stddev = sqrt(variance)
        let maxD = distances.max() ?? 0

        return FaceRecognitionCalibration(
            meanIntraDistance: mean,
            stdDevIntraDistance: stddev,
            maxIntraDistance: maxD
        )
    }
}

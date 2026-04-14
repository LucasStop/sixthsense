import Foundation
import AppKit
import CoreMedia
import CoreGraphics
@preconcurrency import Vision
import SixthSenseCore

// MARK: - Face Recognition Manager

/// Observes the shared camera pipeline to provide a live gating signal
/// for HandCommand:
///
///   - Runs `VNDetectFaceLandmarksRequest` on every frame (cheap) to get
///     the face bounding box + pitch/yaw/roll for "is looking at screen".
///   - Runs `VNGenerateImageFeaturePrintRequest` at most every 500ms on
///     the cropped face region (expensive) to compute a feature print and
///     compare against the enrolled embeddings.
///
/// The computed state is published in `state` as a `FaceRecognitionState`.
/// HandCommand reads `canUseGestures` on every dispatch cycle and either
/// forwards or blocks the action.
@MainActor
@Observable
public final class FaceRecognitionManager: FaceGate {

    // MARK: - Tunables

    /// Max pitch/yaw (in degrees) that still counts as "looking at screen".
    /// Small enough to reject obvious side-glances, wide enough to tolerate
    /// normal head motion while the user is working.
    public var lookingAtScreenThreshold: Double = 25.0

    /// Minimum distance between a fresh feature print and any enrolled
    /// embedding for the face to count as recognized. Smaller = stricter.
    /// 18-22 works well empirically for VNFeaturePrintObservation.
    public var recognitionDistanceThreshold: Float = 20.0

    /// Minimum interval between expensive feature-print computations.
    public var featurePrintInterval: TimeInterval = 0.5

    /// How long to keep the last "recognized" verdict after the face
    /// temporarily leaves the frame, to avoid gestures flickering.
    public var recognitionGraceWindow: TimeInterval = 2.0

    // MARK: - Public state

    public private(set) var state: FaceRecognitionState

    public var canUseGestures: Bool { state.canUseGestures }

    /// Exposes the store so views can query `hasEnrolledFace` / clearEnrollment.
    public let store: FaceEmbeddingStore

    // MARK: - Enrollment state (for FaceEnrollmentView)

    /// All targets the user must hit during the current enrollment session.
    /// Empty when no enrollment is active.
    public private(set) var enrollmentTargets: [EnrollmentTarget] = []

    /// IDs of the targets already captured.
    public private(set) var enrollmentCompletedIds: Set<Int> = []

    /// Index into `enrollmentTargets` for the target the user is
    /// currently trying to hit.
    public private(set) var enrollmentCurrentTargetIndex: Int = 0

    /// Convenience: the target the user is trying to hit right now.
    public var enrollmentCurrentTarget: EnrollmentTarget? {
        guard enrollmentTargets.indices.contains(enrollmentCurrentTargetIndex) else {
            return nil
        }
        return enrollmentTargets[enrollmentCurrentTargetIndex]
    }

    /// Total number of targets to hit. Used by the view to compute
    /// percent-complete.
    public var enrollmentTotal: Int { enrollmentTargets.count }

    /// Number of targets already captured.
    public var enrollmentProgress: Int { enrollmentCompletedIds.count }

    /// The user's current face pose, sampled every frame during
    /// enrollment. `nil` when no face is visible. The view uses this to
    /// move a live cursor inside the enrollment ring.
    public private(set) var enrollmentCurrentPose: FaceAngle?

    /// Vision's face capture quality score for the current frame, 0-1.
    /// The view can surface this to the user ("melhore a iluminação" etc).
    public private(set) var enrollmentQuality: Float = 0

    /// Whether an enrollment session is currently running.
    public private(set) var isEnrolling: Bool = false

    /// Bounding box of the last face seen during enrollment, for the
    /// preview overlay. `nil` when no face is currently visible.
    public private(set) var enrollmentFaceBox: CGRect?

    /// True once every target has been captured. The view watches this
    /// to advance to the "choose your mode" phase automatically.
    public var isEnrollmentComplete: Bool {
        !enrollmentTargets.isEmpty &&
        enrollmentCompletedIds.count >= enrollmentTargets.count
    }

    // MARK: - Dependencies

    private let cameraManager: any CameraPipeline
    private let subscriberId = "face-recognition"
    private var enrolledEmbeddings: [VNFeaturePrintObservation] = []

    // MARK: - Internal tracking

    private var isSubscribed = false
    private var lastFeaturePrintAt: Date?
    private var lastRecognizedAt: Date?
    private let visionQueue = DispatchQueue(
        label: "com.sixthsense.face.vision",
        qos: .userInitiated
    )
    private let faceRequest = VNDetectFaceLandmarksRequest()

    // MARK: - Init

    public init(
        cameraManager: any CameraPipeline,
        store: FaceEmbeddingStore = FaceEmbeddingStore()
    ) {
        self.cameraManager = cameraManager
        self.store = store
        self.state = FaceRecognitionState(mode: store.lockMode)
        self.enrolledEmbeddings = store.loadEmbeddings() ?? []
    }

    // MARK: - Lifecycle

    /// Begins receiving camera frames and updating `state`. Safe to call
    /// multiple times — subscribes once.
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

    /// Stops receiving frames and resets the state.
    public func stop() {
        if isSubscribed {
            cameraManager.unsubscribe(id: subscriberId)
            isSubscribed = false
        }
        state = FaceRecognitionState(mode: store.lockMode)
    }

    /// Re-reads the lock mode and enrolled embeddings from disk. Called
    /// automatically at start and after enrollment completes.
    public func reloadFromStore() {
        let mode = store.lockMode
        enrolledEmbeddings = store.loadEmbeddings() ?? []
        state = FaceRecognitionState(mode: mode)
    }

    /// Update the active lock mode and persist it.
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
    /// enrolled-face mode automatically.
    public func enroll(
        embeddings: [VNFeaturePrintObservation],
        activateMode: Bool
    ) throws {
        try store.save(embeddings: embeddings)
        self.enrolledEmbeddings = embeddings
        if activateMode {
            store.lockMode = .enrolledFace
        }
        state = FaceRecognitionState(mode: store.lockMode)
    }

    /// Remove any enrolled face and reset the mode to `.disabled`.
    public func clearEnrollment() {
        store.clearEnrollment()
        enrolledEmbeddings = []
        state = FaceRecognitionState(mode: store.lockMode)
    }

    // MARK: - Guided enrollment flow

    /// Max angular distance (in degrees) the current pose can be from the
    /// target before we accept it. 9° is generous enough that the user
    /// doesn't have to land exactly on the target, while still tight
    /// enough that the captured embeddings cover meaningful angles.
    public var enrollmentHitRadius: Double = 9.0

    /// Minimum face capture quality accepted for enrollment, 0-1.
    /// Vision scores typically range 0.3-0.9 depending on lighting and
    /// pose; 0.35 accepts anything usable and filters out motion blur
    /// or strong side-lighting.
    public var enrollmentMinimumQuality: Float = 0.35

    /// Minimum hold duration in seconds after hitting a target before we
    /// commit the feature print. 100ms prevents drive-by captures but
    /// still feels snappy.
    public var enrollmentHoldDuration: TimeInterval = 0.10

    /// Start a guided enrollment session with the default 9-point ring.
    /// Replaces the old linear beginEnrollment.
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
        holdStartTime = nil
        isEnrolling = true

        // Make sure we're subscribed to the camera.
        if !isSubscribed {
            cameraManager.subscribe(id: subscriberId) { [weak self] sampleBuffer in
                Task { @MainActor in
                    self?.processFrame(sampleBuffer)
                }
            }
            isSubscribed = true
        }
    }

    /// Abort an in-progress enrollment without saving anything.
    public func cancelEnrollment() {
        isEnrolling = false
        enrollmentBuffer = []
        enrollmentCompletedIds = []
        enrollmentCurrentTargetIndex = 0
        enrollmentFaceBox = nil
        enrollmentCurrentPose = nil
        enrollmentQuality = 0
        holdStartTime = nil
    }

    /// Returns the feature prints captured across all completed targets.
    /// Consumers call this once `isEnrollmentComplete` is true and then
    /// hand the array to `enroll(embeddings:activateMode:)`.
    public func capturedEnrollmentEmbeddings() -> [VNFeaturePrintObservation] {
        enrollmentBuffer
    }

    // MARK: - Internal enrollment state

    private var enrollmentBuffer: [VNFeaturePrintObservation] = []
    private var holdStartTime: Date?

    // MARK: - Frame processing

    private func processFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Enrollment mode short-circuits the normal gating pipeline.
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
                    let distance = Self.computeRecognitionDistance(
                        face: face,
                        pixelBuffer: pixelBuffer,
                        enrolled: self.enrolledEmbeddings
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
                // Skip frame on Vision error.
            }
        }
    }

    private func processEnrollmentFrame(pixelBuffer: CVPixelBuffer) {
        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .upMirrored,
            options: [:]
        )

        visionQueue.async { [weak self] in
            guard let self else { return }
            do {
                // Run landmark + quality requests on the same frame so
                // the quality score aligns with the pose reading.
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

                let yawRad = face.yaw?.doubleValue ?? 0
                let pitchRad = face.pitch?.doubleValue ?? 0
                let pose = FaceAngle(
                    yaw: yawRad * 180.0 / .pi,
                    pitch: pitchRad * 180.0 / .pi
                )

                let quality: Float = (qualityRequest.results?.first as? VNFaceObservation)?
                    .faceCaptureQuality ?? 0

                // Compute feature print lazily — only when the user is
                // actually on target and stable, otherwise we burn CPU.
                let onTarget: Bool
                if let target = self.enrollmentTargets.indices.contains(self.enrollmentCurrentTargetIndex)
                    ? self.enrollmentTargets[self.enrollmentCurrentTargetIndex] : nil {
                    onTarget = pose.distance(to: target.angle) <= self.enrollmentHitRadius &&
                               quality >= self.enrollmentMinimumQuality
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
                    self.enrollmentCurrentPose = pose
                    self.enrollmentQuality = quality
                    self.applyEnrollmentCapture(onTarget: onTarget, print: capturedPrint)
                }
            } catch {
                // Skip on Vision error.
            }
        }
    }

    /// Main-actor side of the enrollment state machine. Decides whether
    /// the current target has been satisfied (requires a sustained hold
    /// before committing the capture) and advances to the next one.
    private func applyEnrollmentCapture(
        onTarget: Bool,
        print capturedPrint: VNFeaturePrintObservation?
    ) {
        guard isEnrolling else { return }

        if !onTarget {
            // Moved off target or quality dropped — reset the hold timer.
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

        // Hold completed — commit the capture if we managed to compute
        // a feature print for this frame. If the print is nil (rare),
        // we reset and let the next frame try again.
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

        enrollmentBuffer.append(capturedPrint)
        enrollmentCompletedIds.insert(target.id)
        holdStartTime = nil

        // Advance to the next target, or finish.
        let next = enrollmentCurrentTargetIndex + 1
        if next < enrollmentTargets.count {
            enrollmentCurrentTargetIndex = next
        } else {
            isEnrolling = false
        }
    }

    /// Compute the feature print for the cropped face region of the given
    /// pixel buffer. Returns `nil` if Vision fails to produce one.
    nonisolated static func computeFeaturePrint(
        face: VNFaceObservation,
        pixelBuffer: CVPixelBuffer
    ) -> VNFeaturePrintObservation? {
        let request = VNGenerateImageFeaturePrintRequest()

        // Pad the face bbox ~10% for context, then clamp to [0, 1].
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
        guard !enrolledEmbeddings.isEmpty else { return false }
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
            recognized = distance <= recognitionDistanceThreshold
            if recognized { lastRecognizedAt = Date() }
        } else if state.mode == .anyFace {
            recognized = true
        } else if state.mode == .enrolledFace {
            // No fresh distance computed this frame — keep previous verdict
            // but decay after grace window.
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

    /// Returns true if the face's pitch and yaw are within the threshold.
    /// Vision reports pitch/yaw as NSNumber on macOS 14+.
    nonisolated static func isLookingAtScreen(
        face: VNFaceObservation,
        threshold: Double
    ) -> Bool {
        let pitchDeg = abs(((face.pitch?.doubleValue) ?? 0) * 180.0 / .pi)
        let yawDeg = abs(((face.yaw?.doubleValue) ?? 0) * 180.0 / .pi)
        return pitchDeg < threshold && yawDeg < threshold
    }

    /// Computes the distance between the cropped face's feature print and
    /// every enrolled embedding, returning the smallest value. Returns
    /// `.infinity` if we can't produce a feature print for any reason.
    nonisolated static func computeRecognitionDistance(
        face: VNFaceObservation,
        pixelBuffer: CVPixelBuffer,
        enrolled: [VNFeaturePrintObservation]
    ) -> Float {
        guard !enrolled.isEmpty else { return .infinity }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Expand the face bbox ~20% so we include more context.
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
            guard let observation = printRequest.results?.first else { return .infinity }
            var smallest: Float = .infinity
            for enrolled in enrolled {
                var distance: Float = 0
                do {
                    try observation.computeDistance(&distance, to: enrolled)
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
}

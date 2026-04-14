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

    /// Number of feature prints captured so far during an active enrollment.
    public private(set) var enrollmentProgress: Int = 0

    /// Total feature prints to capture before finishing enrollment.
    public private(set) var enrollmentTarget: Int = 0

    /// Whether an enrollment session is currently running.
    public private(set) var isEnrolling: Bool = false

    /// Bounding box of the last face seen during enrollment, for the
    /// preview overlay. `nil` when no face is currently visible.
    public private(set) var enrollmentFaceBox: CGRect?

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

    // MARK: - Enrollment flow

    /// Called by FaceEnrollmentView to kick off a capture session. The
    /// manager already owns the camera subscription, so we just flip a
    /// flag and start recording feature prints as frames come in.
    public func beginEnrollment(target: Int = 10) {
        enrollmentTarget = target
        enrollmentProgress = 0
        enrollmentBuffer = []
        enrollmentFaceBox = nil
        lastEnrollmentCaptureAt = nil
        isEnrolling = true

        // Make sure we're subscribed to the camera. If HandCommand isn't
        // running, the camera won't be on, so we bring it up ourselves.
        if !isSubscribed {
            cameraManager.subscribe(id: subscriberId) { [weak self] sampleBuffer in
                Task { @MainActor in
                    self?.processFrame(sampleBuffer)
                }
            }
            isSubscribed = true
        }
    }

    /// Called when the user clicks "Cancelar" mid-enrollment.
    public func cancelEnrollment() {
        isEnrolling = false
        enrollmentBuffer = []
        enrollmentProgress = 0
        enrollmentFaceBox = nil
    }

    /// Return the embeddings captured during the current enrollment session.
    /// Consumers call this once progress == target and then decide whether
    /// to save them (via `enroll(embeddings:activateMode:)`) or discard.
    public func capturedEnrollmentEmbeddings() -> [VNFeaturePrintObservation] {
        enrollmentBuffer
    }

    // MARK: - Internal enrollment state

    private var enrollmentBuffer: [VNFeaturePrintObservation] = []
    private var lastEnrollmentCaptureAt: Date?
    private let enrollmentMinInterval: TimeInterval = 0.35

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
        // Pace the expensive feature-print calls so we don't melt CPU.
        let now = Date()
        if let last = lastEnrollmentCaptureAt,
           now.timeIntervalSince(last) < enrollmentMinInterval {
            return
        }

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .upMirrored,
            options: [:]
        )

        visionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try handler.perform([self.faceRequest])
                guard let face = self.faceRequest.results?.first else {
                    Task { @MainActor in self.enrollmentFaceBox = nil }
                    return
                }

                // Only capture when the user is reasonably facing the camera.
                let looking = Self.isLookingAtScreen(
                    face: face,
                    threshold: self.lookingAtScreenThreshold
                )
                guard looking else {
                    Task { @MainActor in self.enrollmentFaceBox = face.boundingBox }
                    return
                }

                let print = Self.computeFeaturePrint(
                    face: face,
                    pixelBuffer: pixelBuffer
                )

                Task { @MainActor in
                    self.enrollmentFaceBox = face.boundingBox
                    if let print {
                        self.enrollmentBuffer.append(print)
                        self.enrollmentProgress = self.enrollmentBuffer.count
                        self.lastEnrollmentCaptureAt = now

                        if self.enrollmentBuffer.count >= self.enrollmentTarget {
                            self.isEnrolling = false
                        }
                    }
                }
            } catch {
                // Skip on Vision error.
            }
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

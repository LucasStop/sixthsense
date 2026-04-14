import SwiftUI
@preconcurrency import Vision
import Combine
import CoreMedia
import SixthSenseCore
import SharedServices

// MARK: - HandCommand Module

/// Tracks the user's hand via the webcam and translates gestures into
/// desktop actions: cursor movement, pinch-to-click, grab-to-move windows, etc.
@MainActor
@Observable
public final class HandCommandModule: SixthSenseModule {

    // MARK: - Descriptor

    public static let descriptor = ModuleDescriptor(
        id: "hand-command",
        name: "HandCommand",
        tagline: "Minority Report Desktop",
        systemImage: "hand.raised",
        category: .input
    )

    // MARK: - State

    public var state: ModuleState = .disabled

    public var requiredPermissions: [PermissionRequirement] {
        [
            PermissionRequirement(
                type: .camera,
                reason: "O rastreamento de mãos requer a câmera frontal"
            ),
            PermissionRequirement(
                type: .accessibility,
                reason: "Necessário para controle do cursor e gerenciamento de janelas"
            ),
        ]
    }

    // MARK: - Settings

    /// Sensitivity multiplier for cursor movement (0.1 ... 3.0).
    public var sensitivity: Double = 1.0

    // MARK: - Live Snapshot

    /// The most recent hand-tracking snapshot (21 landmarks + classified gesture).
    /// Consumed by the training/visualizer view. `nil` when no hand is detected.
    public private(set) var latestSnapshot: HandLandmarksSnapshot?

    // MARK: - Dependencies

    private let cameraManager: any CameraPipeline
    private let overlayManager: any OverlayPresenter
    private let accessibilityService: any WindowAccessibility
    private let cursorController: any MouseController
    private let eventBus: EventBus

    private let handPoseQueue = DispatchQueue(label: "com.sixthsense.handcommand.vision", qos: .userInteractive)
    private let handPoseRequest = VNDetectHumanHandPoseRequest()

    // MARK: - Init

    public init(
        cameraManager: any CameraPipeline,
        overlayManager: any OverlayPresenter,
        accessibilityService: any WindowAccessibility,
        cursorController: any MouseController,
        eventBus: EventBus
    ) {
        self.cameraManager = cameraManager
        self.overlayManager = overlayManager
        self.accessibilityService = accessibilityService
        self.cursorController = cursorController
        self.eventBus = eventBus

        handPoseRequest.maximumHandCount = 2
    }

    // MARK: - Lifecycle

    public func start() async throws {
        state = .starting

        cameraManager.subscribe(id: Self.descriptor.id) { [weak self] sampleBuffer in
            Task { @MainActor in self?.processCameraFrame(sampleBuffer) }
        }

        state = .running
    }

    public func stop() async {
        state = .stopping
        cameraManager.unsubscribe(id: Self.descriptor.id)
        overlayManager.removeOverlay(id: Self.descriptor.id)
        state = .disabled
    }

    // MARK: - Vision Processing

    private func processCameraFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .upMirrored, options: [:])

        handPoseQueue.async { [weak self] in
            guard let self else { return }
            do {
                try handler.perform([self.handPoseRequest])
                guard let observation = self.handPoseRequest.results?.first else {
                    Task { @MainActor in
                        self.latestSnapshot = nil
                        self.eventBus.emit(.handTrackingLost)
                    }
                    return
                }
                self.handleHandObservation(observation)
            } catch {
                // Vision request failed; silently skip this frame.
            }
        }
    }

    private func handleHandObservation(_ observation: VNHumanHandPoseObservation) {
        // Build a full snapshot of every joint Vision reports, at normalized coords.
        let snapshot = Self.makeSnapshot(from: observation)

        guard let indexTipLandmark = snapshot.landmarks[.indexTip],
              let thumbTipLandmark = snapshot.landmarks[.thumbTip],
              indexTipLandmark.isConfident, thumbTipLandmark.isConfident else {
            Task { @MainActor in self.latestSnapshot = snapshot }
            return
        }

        let indexTip = indexTipLandmark.position
        let thumbTip = thumbTipLandmark.position

        // Compute pinch distance for gesture detection
        let pinchDistance = hypot(indexTip.x - thumbTip.x, indexTip.y - thumbTip.y)

        // Convert normalised Vision coordinates to screen coordinates
        guard let screen = NSScreen.main else {
            Task { @MainActor in self.latestSnapshot = snapshot }
            return
        }
        let screenSize = screen.frame.size
        let cursorX = indexTip.x * screenSize.width * sensitivity
        let cursorY = (1 - indexTip.y) * screenSize.height * sensitivity

        Task { @MainActor [cursorController, eventBus, cursorX, cursorY, pinchDistance, snapshot] in
            self.latestSnapshot = snapshot

            cursorController.moveTo(CGPoint(x: cursorX, y: cursorY))

            if pinchDistance < 0.05 {
                eventBus.emit(.handGestureDetected(.pinch(phase: .began, position: CGPoint(x: cursorX, y: cursorY))))
            }
        }
    }

    // MARK: - Snapshot Construction

    /// Map a Vision observation to the neutral HandLandmarksSnapshot type.
    /// Extracted as a static method so it can be tested independently of the
    /// module's live state.
    static func makeSnapshot(from observation: VNHumanHandPoseObservation) -> HandLandmarksSnapshot {
        var landmarks: [HandJoint: HandLandmark] = [:]

        for (jointName, coreJoint) in Self.jointMapping {
            guard let point = try? observation.recognizedPoint(jointName) else { continue }
            let landmark = HandLandmark(
                joint: coreJoint,
                position: point.location,
                confidence: point.confidence
            )
            landmarks[coreJoint] = landmark
        }

        let snapshot = HandLandmarksSnapshot(
            landmarks: landmarks,
            gesture: .none
        )
        // Re-classify using the pure classifier so the snapshot carries a gesture.
        let classified = HandGestureClassifier.classify(snapshot)
        return HandLandmarksSnapshot(
            landmarks: landmarks,
            gesture: classified,
            timestamp: snapshot.timestamp
        )
    }

    /// Explicit mapping from Vision's joint names to our Core HandJoint enum.
    /// Kept here (not in Core) so Core has no Vision dependency.
    private static let jointMapping: [(VNHumanHandPoseObservation.JointName, HandJoint)] = [
        (.wrist,       .wrist),
        (.thumbCMC,    .thumbCMC),
        (.thumbMP,     .thumbMP),
        (.thumbIP,     .thumbIP),
        (.thumbTip,    .thumbTip),
        (.indexMCP,    .indexMCP),
        (.indexPIP,    .indexPIP),
        (.indexDIP,    .indexDIP),
        (.indexTip,    .indexTip),
        (.middleMCP,   .middleMCP),
        (.middlePIP,   .middlePIP),
        (.middleDIP,   .middleDIP),
        (.middleTip,   .middleTip),
        (.ringMCP,     .ringMCP),
        (.ringPIP,     .ringPIP),
        (.ringDIP,     .ringDIP),
        (.ringTip,     .ringTip),
        (.littleMCP,   .littleMCP),
        (.littlePIP,   .littlePIP),
        (.littleDIP,   .littleDIP),
        (.littleTip,   .littleTip),
    ]

    // MARK: - Settings View

    public var settingsView: some View {
        Form {
            Section("Rastreamento de Mãos") {
                HStack {
                    Text("Sensibilidade")
                    Slider(value: Binding(get: { self.sensitivity },
                                          set: { self.sensitivity = $0 }),
                           in: 0.1...3.0, step: 0.1)
                    Text(String(format: "%.1fx", sensitivity))
                        .monospacedDigit()
                        .frame(width: 40)
                }
                Text("Ajuste o quanto o movimento da mão se traduz em movimento do cursor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

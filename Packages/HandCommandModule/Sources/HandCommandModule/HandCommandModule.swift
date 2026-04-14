import SwiftUI
import Vision
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
                reason: "Hand tracking requires the front-facing camera"
            ),
            PermissionRequirement(
                type: .accessibility,
                reason: "Required for cursor control and window management"
            ),
        ]
    }

    // MARK: - Settings

    /// Sensitivity multiplier for cursor movement (0.1 ... 3.0).
    public var sensitivity: Double = 1.0

    // MARK: - Dependencies

    private let cameraManager: CameraManager
    private let overlayManager: OverlayWindowManager
    private let accessibilityService: AccessibilityService
    private let cursorController: CursorController
    private let eventBus: EventBus

    private let handPoseQueue = DispatchQueue(label: "com.sixthsense.handcommand.vision", qos: .userInteractive)
    private let handPoseRequest = VNDetectHumanHandPoseRequest()

    // MARK: - Init

    public init(
        cameraManager: CameraManager,
        overlayManager: OverlayWindowManager,
        accessibilityService: AccessibilityService,
        cursorController: CursorController,
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
        guard let indexTip = try? observation.recognizedPoint(.indexTip),
              let thumbTip = try? observation.recognizedPoint(.thumbTip),
              indexTip.confidence > 0.5, thumbTip.confidence > 0.5 else { return }

        // Compute pinch distance for gesture detection
        let pinchDistance = hypot(indexTip.location.x - thumbTip.location.x,
                                  indexTip.location.y - thumbTip.location.y)

        // Convert normalised Vision coordinates to screen coordinates
        guard let screen = NSScreen.main else { return }
        let screenSize = screen.frame.size
        let cursorX = indexTip.location.x * screenSize.width * sensitivity
        let cursorY = (1 - indexTip.location.y) * screenSize.height * sensitivity

        Task { @MainActor [cursorController, eventBus, cursorX, cursorY, pinchDistance] in
            cursorController.moveTo(CGPoint(x: cursorX, y: cursorY))

            if pinchDistance < 0.05 {
                eventBus.emit(.handGestureDetected(.pinch(phase: .began, position: CGPoint(x: cursorX, y: cursorY))))
            }
        }
    }

    // MARK: - Settings View

    public var settingsView: some View {
        Form {
            Section("Hand Tracking") {
                HStack {
                    Text("Sensitivity")
                    Slider(value: Binding(get: { self.sensitivity },
                                          set: { self.sensitivity = $0 }),
                           in: 0.1...3.0, step: 0.1)
                    Text(String(format: "%.1fx", sensitivity))
                        .monospacedDigit()
                        .frame(width: 40)
                }
                Text("Adjust how much your hand movement translates to cursor motion.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

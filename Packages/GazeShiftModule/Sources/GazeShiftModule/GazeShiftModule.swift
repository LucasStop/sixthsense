import SwiftUI
import Vision
import Combine
import CoreMedia
import SixthSenseCore
import SharedServices

// MARK: - GazeShift Module

/// Tracks the user's face and eye landmarks via the webcam to determine
/// gaze direction, enabling gaze-aware window focus and dimming.
@MainActor
@Observable
public final class GazeShiftModule: SixthSenseModule {

    // MARK: - Descriptor

    public static let descriptor = ModuleDescriptor(
        id: "gaze-shift",
        name: "GazeShift",
        tagline: "Gaze-Aware Desktop",
        systemImage: "eye",
        category: .input
    )

    // MARK: - State

    public var state: ModuleState = .disabled

    public var requiredPermissions: [PermissionRequirement] {
        [
            PermissionRequirement(
                type: .camera,
                reason: "Gaze tracking requires the front-facing camera"
            ),
            PermissionRequirement(
                type: .accessibility,
                reason: "Required to focus and dim windows based on gaze"
            ),
        ]
    }

    // MARK: - Settings

    /// How aggressively unfocused windows are dimmed (0 = off, 1 = fully opaque).
    public var dimIntensity: Double = 0.4

    // MARK: - Dependencies

    private let cameraManager: CameraManager
    private let overlayManager: OverlayWindowManager
    private let accessibilityService: AccessibilityService

    private let visionQueue = DispatchQueue(label: "com.sixthsense.gazeshift.vision", qos: .userInteractive)
    private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()

    // MARK: - Init

    public init(
        cameraManager: CameraManager,
        overlayManager: OverlayWindowManager,
        accessibilityService: AccessibilityService
    ) {
        self.cameraManager = cameraManager
        self.overlayManager = overlayManager
        self.accessibilityService = accessibilityService
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

        visionQueue.async { [weak self] in
            guard let self else { return }
            do {
                try handler.perform([self.faceLandmarksRequest])
                guard let face = self.faceLandmarksRequest.results?.first,
                      let landmarks = face.landmarks else { return }
                self.handleFaceLandmarks(landmarks, in: face.boundingBox)
            } catch {
                // Vision request failed; skip frame.
            }
        }
    }

    private func handleFaceLandmarks(_ landmarks: VNFaceLandmarks2D, in boundingBox: CGRect) {
        // Estimate gaze direction from the relative position of the pupils
        // within the eye contours.  Full production implementation would
        // use a learned model; here we use a centroid heuristic.
        guard let leftPupil = landmarks.leftPupil?.normalizedPoints.first,
              let rightPupil = landmarks.rightPupil?.normalizedPoints.first else { return }

        let avgX = (leftPupil.x + rightPupil.x) / 2.0
        let avgY = (leftPupil.y + rightPupil.y) / 2.0

        // Map normalised pupil position to screen coordinates
        guard let screen = NSScreen.main else { return }
        let screenSize = screen.frame.size
        let gazeX = CGFloat(avgX) * screenSize.width
        let gazeY = (1 - CGFloat(avgY)) * screenSize.height

        let gazePoint = CGPoint(x: gazeX, y: gazeY)

        Task { @MainActor [accessibilityService, gazePoint] in
            // Focus the window under the estimated gaze point
            if let targetWindow = accessibilityService.windowAtPoint(gazePoint) {
                accessibilityService.focusWindow(targetWindow)
            }
        }
    }

    // MARK: - Settings View

    public var settingsView: some View {
        Form {
            Section("Gaze Tracking") {
                HStack {
                    Text("Dim Intensity")
                    Slider(value: Binding(get: { self.dimIntensity },
                                          set: { self.dimIntensity = $0 }),
                           in: 0.0...1.0, step: 0.05)
                    Text(String(format: "%.0f%%", dimIntensity * 100))
                        .monospacedDigit()
                        .frame(width: 44)
                }
                Text("How much unfocused windows are dimmed when gaze leaves them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

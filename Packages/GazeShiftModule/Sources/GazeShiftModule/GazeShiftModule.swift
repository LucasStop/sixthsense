import SwiftUI
@preconcurrency import Vision
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
                reason: "O rastreamento do olhar requer a câmera frontal"
            ),
            PermissionRequirement(
                type: .accessibility,
                reason: "Necessário para focar e escurecer janelas com base no olhar"
            ),
        ]
    }

    // MARK: - Settings

    /// How aggressively unfocused windows are dimmed (0 = off, 1 = fully opaque).
    public var dimIntensity: Double = 0.4

    // MARK: - Live State

    /// The most recent estimated gaze point in screen coordinates.
    /// Consumed by the training view to show where the system thinks the
    /// user is looking. `nil` when no face is detected.
    public private(set) var latestGazePoint: CGPoint?

    /// Title of the window currently under the gaze point, if any.
    public private(set) var focusedWindowTitle: String?

    // MARK: - Dependencies

    private let cameraManager: any CameraPipeline
    private let overlayManager: any OverlayPresenter
    private let accessibilityService: any WindowAccessibility

    private let visionQueue = DispatchQueue(label: "com.sixthsense.gazeshift.vision", qos: .userInteractive)
    private let faceLandmarksRequest = VNDetectFaceLandmarksRequest()

    // MARK: - Init

    public init(
        cameraManager: any CameraPipeline,
        overlayManager: any OverlayPresenter,
        accessibilityService: any WindowAccessibility
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
        latestGazePoint = nil
        focusedWindowTitle = nil
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

        Task { @MainActor [weak self, accessibilityService, gazePoint] in
            self?.latestGazePoint = gazePoint
            // Focus the window under the estimated gaze point
            if let targetWindow = accessibilityService.windowAtPoint(gazePoint) {
                self?.focusedWindowTitle = targetWindow.title.isEmpty ? targetWindow.appName : targetWindow.title
                accessibilityService.focusWindow(targetWindow)
            } else {
                self?.focusedWindowTitle = nil
            }
        }
    }

    // MARK: - Settings View

    public var settingsView: some View {
        Form {
            Section("Rastreamento do Olhar") {
                HStack {
                    Text("Intensidade do Escurecimento")
                    Slider(value: Binding(get: { self.dimIntensity },
                                          set: { self.dimIntensity = $0 }),
                           in: 0.0...1.0, step: 0.05)
                    Text(String(format: "%.0f%%", dimIntensity * 100))
                        .monospacedDigit()
                        .frame(width: 44)
                }
                Text("O quanto as janelas sem foco escurecem quando o olhar se afasta.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

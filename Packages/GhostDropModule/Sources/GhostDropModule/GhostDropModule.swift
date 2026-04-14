import SwiftUI
import Vision
import Combine
import CoreMedia
import SixthSenseCore
import SharedServices

// MARK: - GhostDrop Module

/// Enables cross-device clipboard sharing driven by hand gestures.
/// When the user performs a "throw" gesture, the current clipboard contents
/// are transmitted to a nearby device over the local network.
@MainActor
@Observable
public final class GhostDropModule: SixthSenseModule {

    // MARK: - Descriptor

    public static let descriptor = ModuleDescriptor(
        id: "ghost-drop",
        name: "GhostDrop",
        tagline: "Cross-Reality Clipboard",
        systemImage: "hand.draw",
        category: .transfer
    )

    // MARK: - State

    public var state: ModuleState = .disabled

    public var requiredPermissions: [PermissionRequirement] {
        [
            PermissionRequirement(
                type: .camera,
                reason: "Used for hand gesture detection when HandCommand is not active"
            ),
            PermissionRequirement(
                type: .localNetwork,
                reason: "Required to send clipboard data to nearby devices"
            ),
        ]
    }

    // MARK: - Dependencies

    private let cameraManager: CameraManager
    private let bonjourService: BonjourService
    private let eventBus: EventBus

    private var eventCancellable: AnyCancellable?
    private var messageCancellable: AnyCancellable?
    private var isUsingOwnHandTracking = false

    private let handPoseQueue = DispatchQueue(label: "com.sixthsense.ghostdrop.vision", qos: .userInitiated)
    private let handPoseRequest = VNDetectHumanHandPoseRequest()

    // MARK: - Init

    public init(
        cameraManager: CameraManager,
        bonjourService: BonjourService,
        eventBus: EventBus
    ) {
        self.cameraManager = cameraManager
        self.bonjourService = bonjourService
        self.eventBus = eventBus

        handPoseRequest.maximumHandCount = 1
    }

    // MARK: - Lifecycle

    public func start() async throws {
        state = .starting

        bonjourService.startBrowsing()

        // Listen for hand gesture events from HandCommand via EventBus.
        eventCancellable = eventBus.on { event in
            if case .handGestureDetected(.throwMotion) = event { return true }
            return false
        }
        .receive(on: DispatchQueue.main)
        .sink { [weak self] event in
            if case .handGestureDetected(let gesture) = event {
                self?.handleGesture(gesture)
            }
        }

        // If HandCommand is not running, start our own hand tracking.
        // We detect this heuristically: if we receive no gesture events within 2 seconds
        // of starting, we subscribe to the camera ourselves.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.state == .running else { return }
            await self.startOwnHandTrackingIfNeeded()
        }

        messageCancellable = bonjourService.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleIncomingTransfer(message)
            }

        state = .running
    }

    public func stop() async {
        state = .stopping
        eventCancellable?.cancel()
        eventCancellable = nil
        messageCancellable?.cancel()
        messageCancellable = nil

        if isUsingOwnHandTracking {
            cameraManager.unsubscribe(id: Self.descriptor.id)
            isUsingOwnHandTracking = false
        }

        bonjourService.stopBrowsing()
        state = .disabled
    }

    // MARK: - Hand Tracking (Fallback)

    private func startOwnHandTrackingIfNeeded() async {
        guard !isUsingOwnHandTracking else { return }
        isUsingOwnHandTracking = true

        cameraManager.subscribe(id: Self.descriptor.id) { [weak self] sampleBuffer in
            Task { @MainActor in self?.processCameraFrame(sampleBuffer) }
        }
    }

    private func processCameraFrame(_ sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .upMirrored, options: [:])

        handPoseQueue.async { [weak self] in
            guard let self else { return }
            do {
                try handler.perform([self.handPoseRequest])
                guard let observation = self.handPoseRequest.results?.first else { return }
                self.detectThrowGesture(observation)
            } catch {
                // Skip frame on failure.
            }
        }
    }

    private func detectThrowGesture(_ observation: VNHumanHandPoseObservation) {
        // Simplified throw detection: look for rapid wrist movement.
        // A production implementation would track velocity over several frames.
        guard let wrist = try? observation.recognizedPoint(.wrist),
              wrist.confidence > 0.5 else { return }

        // Placeholder: emit event when wrist is detected with high confidence
        // Real implementation would compare positions across frames.
    }

    // MARK: - Gesture Handling

    private func handleGesture(_ gesture: HandGesture) {
        guard case .throwMotion(let direction) = gesture else { return }

        // Capture current pasteboard contents
        let pasteboard = NSPasteboard.general
        guard let data = pasteboard.data(forType: .string) else { return }

        // Send to the first discovered peer
        guard let peer = bonjourService.discoveredPeers.first else { return }
        bonjourService.send(data: data, to: peer.name)

        eventBus.emit(.clipboardContentCaptured(type: .text))

        _ = direction // Directional targeting for multi-device setups (future work).
    }

    // MARK: - Incoming Transfer

    private func handleIncomingTransfer(_ message: PeerMessage) {
        // Place received data on the local pasteboard.
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(message.data, forType: .string)

        eventBus.emit(.clipboardTransferCompleted(deviceId: message.peerId))
    }

    // MARK: - Settings View

    public var settingsView: some View {
        Form {
            Section("GhostDrop") {
                Text("Perform a throw gesture to send your clipboard to a nearby device.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if bonjourService.discoveredPeers.isEmpty {
                    Label("No devices found on the local network.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bonjourService.discoveredPeers) { peer in
                        Label(peer.name, systemImage: "laptopcomputer.and.iphone")
                    }
                }
            }
        }
    }
}

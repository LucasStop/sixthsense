import SwiftUI
import Combine
import SixthSenseCore
import SharedServices

// MARK: - PortalView Module

/// Creates a virtual display that streams its contents to a connected
/// device, turning an iPhone or iPad into an extended monitor.
@MainActor
@Observable
public final class PortalViewModule: SixthSenseModule {

    // MARK: - Descriptor

    public static let descriptor = ModuleDescriptor(
        id: "portal-view",
        name: "PortalView",
        tagline: "Portal Display",
        systemImage: "rectangle.on.rectangle",
        category: .display
    )

    // MARK: - State

    public var state: ModuleState = .disabled

    public var requiredPermissions: [PermissionRequirement] {
        [
            PermissionRequirement(
                type: .screenRecording,
                reason: "Required to capture the virtual display contents for streaming"
            ),
            PermissionRequirement(
                type: .localNetwork,
                reason: "Required to stream display contents to the paired device"
            ),
        ]
    }

    // MARK: - Settings

    /// Target resolution for the virtual display.
    public var resolution: CGSize = CGSize(width: 1920, height: 1080)

    /// Target frame rate for streaming.
    public var targetFPS: Int = 30

    // MARK: - Dependencies

    private let bonjourService: BonjourService

    private var messageCancellable: AnyCancellable?

    // MARK: - Init

    public init(bonjourService: BonjourService) {
        self.bonjourService = bonjourService
    }

    // MARK: - Lifecycle

    public func start() async throws {
        state = .starting

        // Start advertising so that companion apps can discover this Mac.
        try bonjourService.startAdvertising(name: "PortalView-\(ProcessInfo.processInfo.hostName)",
                                            port: 5960)

        // TODO: Create a CGVirtualDisplay with CoreGraphics private API or
        // ScreenCaptureKit to provide a headless framebuffer that can be
        // streamed to the connected device.

        messageCancellable = bonjourService.messagePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handlePeerMessage(message)
            }

        state = .running
    }

    public func stop() async {
        state = .stopping
        messageCancellable?.cancel()
        messageCancellable = nil
        bonjourService.stopAdvertising()
        state = .disabled
    }

    // MARK: - Networking

    private func handlePeerMessage(_ message: PeerMessage) {
        // Handle incoming control messages from the companion device
        // (touch events, resolution change requests, etc.)
    }

    // MARK: - Settings View

    public var settingsView: some View {
        Form {
            Section("Virtual Display") {
                LabeledContent("Resolution") {
                    Text("\(Int(resolution.width)) x \(Int(resolution.height))")
                        .monospacedDigit()
                }
                LabeledContent("Target FPS") {
                    Text("\(targetFPS)")
                        .monospacedDigit()
                }
                Text("Streams a virtual display to your connected device over the local network.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if bonjourService.discoveredPeers.isEmpty {
                    Label("No companion devices found.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bonjourService.discoveredPeers) { peer in
                        Label(peer.name, systemImage: "ipad.landscape")
                    }
                }
            }
        }
    }
}

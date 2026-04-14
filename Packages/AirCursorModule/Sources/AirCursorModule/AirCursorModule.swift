import SwiftUI
import Combine
import SixthSenseCore
import SharedServices

// MARK: - AirCursor Module

/// Turns a paired iPhone into a gyroscope-based air mouse, allowing the user
/// to point their phone at the Mac screen and control the cursor remotely.
@MainActor
@Observable
public final class AirCursorModule: SixthSenseModule {

    // MARK: - Descriptor

    public static let descriptor = ModuleDescriptor(
        id: "air-cursor",
        name: "AirCursor",
        tagline: "Telekinesis KVM",
        systemImage: "iphone.radiowaves.left.and.right",
        category: .input
    )

    // MARK: - State

    public var state: ModuleState = .disabled

    public var requiredPermissions: [PermissionRequirement] {
        [
            PermissionRequirement(
                type: .localNetwork,
                reason: "Necessário para descobrir e se comunicar com o iPhone pareado"
            ),
        ]
    }

    // MARK: - Settings

    /// Gyro-to-cursor sensitivity multiplier.
    public var gyroSensitivity: Double = 1.0

    // MARK: - Live State

    /// Latest gyro reading received from the paired iPhone. Consumed by the
    /// training view so the user can see their phone movement in real time.
    public private(set) var latestReading: AirCursorReading?

    /// Running count of taps received since the module was last started.
    public private(set) var tapCount: Int = 0

    /// Whether at least one peer is connected.
    public var isConnected: Bool {
        !discoveredPeers.isEmpty
    }

    /// Exposed for training views that want to render peer list.
    public var discoveredPeers: [DiscoveredPeer] {
        bonjourService.discoveredPeers
    }

    // MARK: - Dependencies

    private let bonjourService: any PeerNetwork
    private let cursorController: any MouseController

    private var messageCancellable: AnyCancellable?

    // MARK: - Init

    public init(
        bonjourService: any PeerNetwork,
        cursorController: any MouseController
    ) {
        self.bonjourService = bonjourService
        self.cursorController = cursorController
    }

    // MARK: - Lifecycle

    public func start() async throws {
        state = .starting

        bonjourService.startBrowsing()

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
        bonjourService.stopBrowsing()
        latestReading = nil
        tapCount = 0
        state = .disabled
    }

    // MARK: - Gyro Data Handling

    private func handlePeerMessage(_ message: PeerMessage) {
        // Expected payload: JSON with dx/dy deltas from the iPhone gyroscope.
        guard let payload = try? JSONDecoder().decode(GyroPayload.self, from: message.data) else { return }

        let dx = CGFloat(payload.dx) * gyroSensitivity
        let dy = CGFloat(payload.dy) * gyroSensitivity

        latestReading = AirCursorReading(
            dx: payload.dx,
            dy: payload.dy,
            tap: payload.tap,
            timestamp: Date()
        )

        cursorController.moveBy(dx: dx, dy: dy)

        if payload.tap {
            tapCount += 1
            let pos = cursorController.currentPosition
            cursorController.leftClick(at: pos)
        }
    }

    // MARK: - Settings View

    public var settingsView: some View {
        Form {
            Section("AirCursor") {
                HStack {
                    Text("Sensibilidade do Giroscópio")
                    Slider(value: Binding(get: { self.gyroSensitivity },
                                          set: { self.gyroSensitivity = $0 }),
                           in: 0.1...5.0, step: 0.1)
                    Text(String(format: "%.1fx", gyroSensitivity))
                        .monospacedDigit()
                        .frame(width: 40)
                }
                Text("Controla a velocidade do cursor em relação à inclinação do celular.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if bonjourService.discoveredPeers.isEmpty {
                    Label("Nenhum dispositivo encontrado na rede local.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(bonjourService.discoveredPeers) { peer in
                        Label(peer.name, systemImage: "iphone")
                    }
                }
            }
        }
    }
}

// MARK: - Gyro Payload

/// Lightweight struct decoded from the companion iPhone app.
private struct GyroPayload: Decodable {
    let dx: Double
    let dy: Double
    let tap: Bool
}

// MARK: - Air Cursor Reading

/// Public snapshot of the last gyro reading, for the training view.
public struct AirCursorReading: Sendable, Equatable {
    public let dx: Double
    public let dy: Double
    public let tap: Bool
    public let timestamp: Date

    public init(dx: Double, dy: Double, tap: Bool, timestamp: Date) {
        self.dx = dx
        self.dy = dy
        self.tap = tap
        self.timestamp = timestamp
    }
}

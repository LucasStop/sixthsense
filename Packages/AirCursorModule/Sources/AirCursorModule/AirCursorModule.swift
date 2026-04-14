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

    // MARK: - Dependencies

    private let bonjourService: BonjourService
    private let cursorController: CursorController

    private var messageCancellable: AnyCancellable?

    // MARK: - Init

    public init(
        bonjourService: BonjourService,
        cursorController: CursorController
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
        state = .disabled
    }

    // MARK: - Gyro Data Handling

    private func handlePeerMessage(_ message: PeerMessage) {
        // Expected payload: JSON with dx/dy deltas from the iPhone gyroscope.
        guard let payload = try? JSONDecoder().decode(GyroPayload.self, from: message.data) else { return }

        let dx = CGFloat(payload.dx) * gyroSensitivity
        let dy = CGFloat(payload.dy) * gyroSensitivity
        cursorController.moveBy(dx: dx, dy: dy)

        if payload.tap {
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

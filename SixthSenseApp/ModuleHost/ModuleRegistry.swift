import Foundation
import SixthSenseCore
import SharedServices
import HandCommandModule

// MARK: - Module Registry

/// Holds the HandCommand module instance and drives its lifecycle, plus
/// the face recognition gate that decides whether gestures are allowed
/// to fire at any given moment.
@MainActor
@Observable
final class ModuleRegistry {
    /// Concrete reference used by the training view to observe live state.
    let handCommand: HandCommandModule

    /// Live face gate. Always instantiated; its behaviour is driven by
    /// `faceLockMode` and the enrolled embeddings saved in Application
    /// Support. The HandCommand module holds a weak reference to it and
    /// blocks dispatch when `canUseGestures == false`.
    let faceRecognition: FaceRecognitionManager

    private let services: SharedServiceContainer

    init(services: SharedServiceContainer) {
        self.services = services
        self.faceRecognition = services.faceRecognition

        let module = HandCommandModule(
            cameraManager: services.camera,
            overlayManager: services.overlay,
            accessibilityService: services.accessibility,
            cursorController: services.input,
            eventBus: services.eventBus
        )
        module.faceGate = services.faceRecognition
        self.handCommand = module
    }

    var isActive: Bool {
        handCommand.state.isActive
    }

    /// Toggle HandCommand on/off. Starts the face gate alongside the hand
    /// tracker so the gate state is live while the user is controlling.
    func toggleHandCommand() async {
        print("[SixthSense] Alternando HandCommand, estado atual: \(handCommand.state)")

        if handCommand.state == .running || handCommand.state == .starting {
            await handCommand.stop()
            faceRecognition.stop()
            print("[SixthSense] HandCommand parado")
            return
        }

        let missing = services.permissions.checkMissing(handCommand.requiredPermissions)
        if !missing.isEmpty {
            print("[SixthSense] HandCommand com permissões faltando: \(missing.map { $0.type.label })")
        }

        do {
            faceRecognition.start()
            try await handCommand.start()
            print("[SixthSense] HandCommand iniciado com sucesso, estado: \(handCommand.state)")
        } catch {
            print("[SixthSense] Falha ao iniciar HandCommand: \(error)")
            faceRecognition.stop()
        }
    }
}

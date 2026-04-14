import Foundation
import SixthSenseCore
import SharedServices
import HandCommandModule

// MARK: - Module Registry

/// Holds the HandCommand module instance and drives its lifecycle. The
/// registry is deliberately tiny — there's only one feature module — but
/// it keeps start/stop/permission logic in a single place so the UI doesn't
/// have to know anything about camera setup or state transitions.
@MainActor
@Observable
final class ModuleRegistry {
    /// Concrete reference used by the training view to observe live state.
    let handCommand: HandCommandModule

    private let services: SharedServiceContainer

    init(services: SharedServiceContainer) {
        self.services = services
        self.handCommand = HandCommandModule(
            cameraManager: services.camera,
            overlayManager: services.overlay,
            accessibilityService: services.accessibility,
            cursorController: services.input,
            eventBus: services.eventBus
        )
    }

    /// Convenient accessor used by the menu bar toggle.
    var isActive: Bool {
        handCommand.state.isActive
    }

    /// Toggle HandCommand on/off. Logs to the console and handles errors
    /// gracefully so the UI can trust the state transition.
    func toggleHandCommand() async {
        print("[SixthSense] Alternando HandCommand, estado atual: \(handCommand.state)")

        if handCommand.state == .running || handCommand.state == .starting {
            await handCommand.stop()
            print("[SixthSense] HandCommand parado")
            return
        }

        // Verifica permissões — tenta iniciar mesmo se estiverem faltando
        // para que o módulo dispare o prompt nativo na hora certa.
        let missing = services.permissions.checkMissing(handCommand.requiredPermissions)
        if !missing.isEmpty {
            print("[SixthSense] HandCommand com permissões faltando: \(missing.map { $0.type.label })")
        }

        do {
            try await handCommand.start()
            print("[SixthSense] HandCommand iniciado com sucesso, estado: \(handCommand.state)")
        } catch {
            print("[SixthSense] Falha ao iniciar HandCommand: \(error)")
        }
    }
}

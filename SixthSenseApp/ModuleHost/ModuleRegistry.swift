import Foundation
import SixthSenseCore
import SharedServices
import HandCommandModule
import GazeShiftModule
import AirCursorModule
import PortalViewModule
import GhostDropModule
import NotchBarModule

// MARK: - Module Registry

/// Central registry that holds all module instances and manages their lifecycle.
/// Modules are registered at compile time (no runtime discovery).
/// Uses AnyModule type-erasure to store heterogeneous module types.
@MainActor
@Observable
final class ModuleRegistry {
    private(set) var modules: [AnyModule] = []
    private let services: SharedServiceContainer

    /// Concrete HandCommand reference, kept so the Training window can
    /// observe its live `latestSnapshot`. The same instance is also wrapped
    /// in the AnyModule registered in `modules`.
    let handCommand: HandCommandModule

    init(services: SharedServiceContainer) {
        self.services = services

        // Create the concrete HandCommand first so we can retain a typed
        // reference for the Training view while still registering it.
        let handCommand = HandCommandModule(
            cameraManager: services.camera,
            overlayManager: services.overlay,
            accessibilityService: services.accessibility,
            cursorController: services.input,
            eventBus: services.eventBus
        )
        self.handCommand = handCommand

        // Register all modules — explicit, compile-time safe, wrapped in AnyModule
        modules = [
            AnyModule(handCommand),
            AnyModule(GazeShiftModule(
                cameraManager: services.camera,
                overlayManager: services.overlay,
                accessibilityService: services.accessibility
            )),
            AnyModule(AirCursorModule(
                bonjourService: services.network,
                cursorController: services.input
            )),
            AnyModule(PortalViewModule(
                bonjourService: services.network
            )),
            AnyModule(GhostDropModule(
                cameraManager: services.camera,
                bonjourService: services.network,
                eventBus: services.eventBus
            )),
            AnyModule(NotchBarModule(
                overlay: services.overlay
            ))
        ]
    }

    /// Find a module by its descriptor ID.
    func module(for id: String) -> AnyModule? {
        modules.first { $0.id == id }
    }

    /// Alterna um módulo entre ligado/desligado.
    func toggle(_ module: AnyModule) async {
        print("[SixthSense] Alternando \(module.descriptor.name), estado atual: \(module.state)")

        if module.state == .running || module.state == .starting {
            await module.stop()
            print("[SixthSense] \(module.descriptor.name) parado")
        } else {
            // Verifica módulos conflitantes
            await stopConflictingModules(for: module)

            // Verifica permissões
            let missing = services.permissions.checkMissing(module.requiredPermissions)
            if !missing.isEmpty {
                print("[SixthSense] \(module.descriptor.name) com permissões faltando: \(missing.map { $0.type.label })")
                // Ainda tenta iniciar — deixa o módulo lidar com prompts de permissão
            }

            do {
                try await module.start()
                print("[SixthSense] \(module.descriptor.name) iniciado com sucesso, estado: \(module.state)")
            } catch {
                print("[SixthSense] Falha ao iniciar \(module.descriptor.name): \(error)")
            }
        }
    }

    // MARK: - Conflict Resolution

    private let cursorControlModules: Set<String> = ["hand-command", "air-cursor"]

    private func stopConflictingModules(for module: AnyModule) async {
        if cursorControlModules.contains(module.id) {
            for otherModule in modules where otherModule.id != module.id
                && cursorControlModules.contains(otherModule.id)
                && otherModule.state.isActive {
                await otherModule.stop()
            }
        }
    }
}

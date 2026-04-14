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

    /// Concrete references to each module, kept so the Training center can
    /// observe their live state properties. The same instances are also
    /// wrapped in AnyModules inside `modules`.
    let handCommand: HandCommandModule
    let gazeShift: GazeShiftModule
    let airCursor: AirCursorModule
    let portalView: PortalViewModule
    let ghostDrop: GhostDropModule
    let notchBar: NotchBarModule

    init(services: SharedServiceContainer) {
        self.services = services

        // Create the concrete modules up front so we can retain typed
        // references for the Training views while still registering them.
        let handCommand = HandCommandModule(
            cameraManager: services.camera,
            overlayManager: services.overlay,
            accessibilityService: services.accessibility,
            cursorController: services.input,
            eventBus: services.eventBus
        )
        let gazeShift = GazeShiftModule(
            cameraManager: services.camera,
            overlayManager: services.overlay,
            accessibilityService: services.accessibility
        )
        let airCursor = AirCursorModule(
            bonjourService: services.network,
            cursorController: services.input
        )
        let portalView = PortalViewModule(
            bonjourService: services.network
        )
        let ghostDrop = GhostDropModule(
            cameraManager: services.camera,
            bonjourService: services.network,
            eventBus: services.eventBus
        )
        let notchBar = NotchBarModule(
            overlay: services.overlay
        )

        self.handCommand = handCommand
        self.gazeShift = gazeShift
        self.airCursor = airCursor
        self.portalView = portalView
        self.ghostDrop = ghostDrop
        self.notchBar = notchBar

        modules = [
            AnyModule(handCommand),
            AnyModule(gazeShift),
            AnyModule(airCursor),
            AnyModule(portalView),
            AnyModule(ghostDrop),
            AnyModule(notchBar),
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

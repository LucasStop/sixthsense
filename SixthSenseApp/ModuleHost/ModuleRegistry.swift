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

    init(services: SharedServiceContainer) {
        self.services = services

        // Register all modules — explicit, compile-time safe, wrapped in AnyModule
        modules = [
            AnyModule(HandCommandModule(
                cameraManager: services.camera,
                overlayManager: services.overlay,
                accessibilityService: services.accessibility,
                cursorController: services.input,
                eventBus: services.eventBus
            )),
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

    /// Toggle a module on/off.
    func toggle(_ module: AnyModule) async {
        if module.state == .running || module.state == .starting {
            await module.stop()
        } else {
            // Check for conflicting modules
            await stopConflictingModules(for: module)

            // Check permissions
            let missing = services.permissions.checkMissing(module.requiredPermissions)
            if !missing.isEmpty {
                return
            }

            do {
                try await module.start()
            } catch {
                print("[SixthSense] Failed to start \(module.descriptor.name): \(error)")
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

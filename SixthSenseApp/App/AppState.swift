import SwiftUI
import SixthSenseCore
import SharedServices

// MARK: - App State

/// Top-level observable state for the entire app.
/// Holds the shared services container and module registry.
@MainActor
@Observable
final class AppState {
    let services: SharedServiceContainer
    let registry: ModuleRegistry

    init() {
        let services = SharedServiceContainer()
        self.services = services
        self.registry = ModuleRegistry(services: services)
    }
}

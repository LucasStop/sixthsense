import SwiftUI

// MARK: - Type-Erased Module Wrapper

/// Type-erased wrapper for SixthSenseModule, enabling heterogeneous collections.
/// Since SixthSenseModule has an associated type (SettingsContent), we cannot use
/// `any SixthSenseModule` in arrays. This wrapper provides the solution.
@MainActor
@Observable
public final class AnyModule: Identifiable {
    public let id: String
    public let descriptor: ModuleDescriptor

    private let _getState: @MainActor () -> ModuleState
    private let _getPermissions: @MainActor () -> [PermissionRequirement]
    private let _start: @MainActor () async throws -> Void
    private let _stop: @MainActor () async -> Void
    private let _settingsView: @MainActor () -> AnyView

    public var state: ModuleState { _getState() }
    public var requiredPermissions: [PermissionRequirement] { _getPermissions() }

    public init<M: SixthSenseModule>(_ module: M) {
        self.id = M.descriptor.id
        self.descriptor = M.descriptor
        self._getState = { module.state }
        self._getPermissions = { module.requiredPermissions }
        self._start = { try await module.start() }
        self._stop = { await module.stop() }
        self._settingsView = { AnyView(module.settingsView) }
    }

    public func start() async throws {
        try await _start()
    }

    public func stop() async {
        await _stop()
    }

    public var settingsView: AnyView {
        _settingsView()
    }
}

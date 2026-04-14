import SwiftUI
import Combine

// MARK: - Type-Erased Module Wrapper

/// Type-erased wrapper for SixthSenseModule, enabling heterogeneous collections.
/// Uses a polling timer to sync state from the underlying module, since @Observable
/// cannot track changes through closure-based computed properties.
@MainActor
@Observable
public final class AnyModule: Identifiable {
    public let id: String
    public let descriptor: ModuleDescriptor

    /// Stored state that the UI observes — synced from the real module
    public private(set) var state: ModuleState = .disabled

    private let _getState: @MainActor () -> ModuleState
    private let _getPermissions: @MainActor () -> [PermissionRequirement]
    private let _start: @MainActor () async throws -> Void
    private let _stop: @MainActor () async -> Void
    private let _settingsView: @MainActor () -> AnyView
    private var syncTask: Task<Void, Never>?

    public var requiredPermissions: [PermissionRequirement] { _getPermissions() }

    public init<M: SixthSenseModule>(_ module: M) {
        self.id = M.descriptor.id
        self.descriptor = M.descriptor
        self.state = module.state
        self._getState = { module.state }
        self._getPermissions = { module.requiredPermissions }
        self._start = { try await module.start() }
        self._stop = { await module.stop() }
        self._settingsView = { AnyView(module.settingsView) }

        // Sync state from underlying module periodically
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self else { break }
                let newState = self._getState()
                if self.state != newState {
                    self.state = newState
                }
            }
        }
    }

    nonisolated deinit {
        // Cannot access MainActor properties in deinit, but Task will cancel
        // when self is deallocated since it holds a weak reference
    }

    public func start() async throws {
        try await _start()
        syncState()
    }

    public func stop() async {
        await _stop()
        syncState()
    }

    /// Force a state sync from the underlying module
    public func syncState() {
        state = _getState()
    }

    public var settingsView: AnyView {
        _settingsView()
    }
}

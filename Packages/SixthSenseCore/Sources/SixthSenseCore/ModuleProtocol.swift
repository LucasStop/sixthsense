import SwiftUI
import Combine

// MARK: - Module Protocol

/// The fundamental contract that every SixthSense feature module must conform to.
/// Each module is an independent, toggleable unit of functionality.
@MainActor
public protocol SixthSenseModule: AnyObject, Observable {
    /// Associated type for the module's settings view
    associatedtype SettingsContent: View

    /// Static metadata describing this module (name, icon, category)
    static var descriptor: ModuleDescriptor { get }

    /// Current lifecycle state of the module
    var state: ModuleState { get }

    /// Permissions this module requires before it can start
    var requiredPermissions: [PermissionRequirement] { get }

    /// Start the module. Called when user enables the module.
    /// - Throws: If preconditions fail (permissions, hardware unavailable, etc.)
    func start() async throws

    /// Stop the module and release all resources.
    func stop() async

    /// SwiftUI settings view for this module, embedded in the Settings window
    @ViewBuilder var settingsView: SettingsContent { get }
}

// MARK: - Default Implementations

public extension SixthSenseModule {
    var requiredPermissions: [PermissionRequirement] { [] }
}

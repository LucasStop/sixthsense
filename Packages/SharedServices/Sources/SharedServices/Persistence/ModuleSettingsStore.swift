import Foundation

// MARK: - Module Settings Store

/// UserDefaults-backed persistence for per-module enabled/disabled state and settings.
public final class ModuleSettingsStore: @unchecked Sendable {

    private let defaults: UserDefaults
    private let prefix = "com.sixthsense.module."

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Check if a module is enabled (persisted across launches).
    public func isModuleEnabled(_ moduleId: String) -> Bool {
        defaults.bool(forKey: prefix + moduleId + ".enabled")
    }

    /// Set a module's enabled state.
    public func setModuleEnabled(_ moduleId: String, enabled: Bool) {
        defaults.set(enabled, forKey: prefix + moduleId + ".enabled")
    }

    /// Get a setting value for a module.
    public func value<T>(for key: String, moduleId: String) -> T? {
        defaults.object(forKey: prefix + moduleId + "." + key) as? T
    }

    /// Set a setting value for a module.
    public func setValue(_ value: Any?, for key: String, moduleId: String) {
        defaults.set(value, forKey: prefix + moduleId + "." + key)
    }

    /// Get a setting with a default value.
    public func value<T>(for key: String, moduleId: String, default defaultValue: T) -> T {
        (defaults.object(forKey: prefix + moduleId + "." + key) as? T) ?? defaultValue
    }
}

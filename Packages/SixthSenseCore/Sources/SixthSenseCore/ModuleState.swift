import SwiftUI

// MARK: - Module State

/// Represents the lifecycle state of a SixthSense module.
public enum ModuleState: String, Sendable {
    case disabled
    case waitingForPermissions
    case starting
    case running
    case error
    case stopping

    /// Whether the module is considered "active" (starting or running)
    public var isActive: Bool {
        self == .starting || self == .running
    }

    /// User-facing label
    public var label: String {
        switch self {
        case .disabled: return "Off"
        case .waitingForPermissions: return "Needs Permissions"
        case .starting: return "Starting..."
        case .running: return "Active"
        case .error: return "Error"
        case .stopping: return "Stopping..."
        }
    }

    /// Color for status indicator
    public var color: Color {
        switch self {
        case .disabled: return .secondary
        case .waitingForPermissions: return .orange
        case .starting, .stopping: return .yellow
        case .running: return .green
        case .error: return .red
        }
    }

    /// SF Symbol for status
    public var systemImage: String {
        switch self {
        case .disabled: return "circle"
        case .waitingForPermissions: return "lock.circle"
        case .starting, .stopping: return "circle.dotted"
        case .running: return "circle.fill"
        case .error: return "exclamationmark.circle"
        }
    }
}

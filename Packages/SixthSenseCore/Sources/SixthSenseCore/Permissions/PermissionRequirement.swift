import Foundation

// MARK: - Permission Types

/// Types of system permissions that modules may require.
public enum PermissionType: String, Sendable, CaseIterable {
    case camera
    case accessibility
    case screenRecording
    case localNetwork
    case microphone

    public var label: String {
        switch self {
        case .camera: return "Camera"
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .localNetwork: return "Local Network"
        case .microphone: return "Microphone"
        }
    }

    public var description: String {
        switch self {
        case .camera: return "Required for hand gesture and gaze tracking via webcam"
        case .accessibility: return "Required for window management and cursor control"
        case .screenRecording: return "Required for capturing screen content"
        case .localNetwork: return "Required for cross-device communication"
        case .microphone: return "Required for audio visualization in NotchBar"
        }
    }

    public var systemImage: String {
        switch self {
        case .camera: return "camera"
        case .accessibility: return "accessibility"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .localNetwork: return "network"
        case .microphone: return "mic"
        }
    }
}

// MARK: - Permission Requirement

/// A specific permission required by a module, with context for why.
public struct PermissionRequirement: Sendable {
    public let type: PermissionType
    public let reason: String
    public let isRequired: Bool  // false = optional enhancement

    public init(type: PermissionType, reason: String, isRequired: Bool = true) {
        self.type = type
        self.reason = reason
        self.isRequired = isRequired
    }
}

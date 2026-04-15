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
        case .camera: return "Câmera"
        case .accessibility: return "Acessibilidade"
        case .screenRecording: return "Gravação de Tela"
        case .localNetwork: return "Rede Local"
        case .microphone: return "Microfone"
        }
    }

    public var description: String {
        switch self {
        case .camera: return "Necessário para rastreamento de gestos e olhar via webcam"
        case .accessibility: return "Necessário para gerenciamento de janelas e controle do cursor"
        case .screenRecording: return "Necessário para captura de conteúdo da tela"
        case .localNetwork: return "Necessário para comunicação entre dispositivos"
        case .microphone: return "Necessário para captura de áudio"
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

import Foundation

// MARK: - Module Descriptor

/// Static metadata describing a SixthSense module.
public struct ModuleDescriptor: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let tagline: String
    public let systemImage: String
    public let category: ModuleCategory

    public init(
        id: String,
        name: String,
        tagline: String,
        systemImage: String,
        category: ModuleCategory
    ) {
        self.id = id
        self.name = name
        self.tagline = tagline
        self.systemImage = systemImage
        self.category = category
    }
}

// MARK: - Module Category

public enum ModuleCategory: String, Sendable, CaseIterable {
    case input       // HandCommand, GazeShift, AirCursor
    case display     // PortalView
    case transfer    // GhostDrop
    case interface   // NotchBar

    public var label: String {
        switch self {
        case .input: return "Controle de Entrada"
        case .display: return "Tela"
        case .transfer: return "Transferência"
        case .interface: return "Interface"
        }
    }

    public var systemImage: String {
        switch self {
        case .input: return "hand.raised"
        case .display: return "display"
        case .transfer: return "arrow.triangle.swap"
        case .interface: return "menubar.rectangle"
        }
    }
}

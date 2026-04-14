import SwiftUI
import AVFoundation
import SixthSenseCore
import SharedServices

// MARK: - Training Center

/// Janela central de "Centro de Treinamento" com uma sidebar listando todas
/// as features e o conteúdo de treino de cada uma no painel de detalhes.
/// Cada treino mostra o estado observável do módulo correspondente em tempo
/// real para o usuário aprender como a feature está reagindo.
struct TrainingCenterView: View {
    let appState: AppState

    @State private var selection: TrainingModule = .handCommand

    var body: some View {
        NavigationSplitView {
            List(TrainingModule.allCases, selection: $selection) { item in
                Label(item.displayName, systemImage: item.systemImage)
                    .foregroundStyle(.white)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection {
                case .handCommand:
                    HandTrainingView(
                        handModule: appState.registry.handCommand,
                        cameraSession: { appState.services.camera.avSession }
                    )
                case .gazeShift:
                    GazeShiftTrainingView(module: appState.registry.gazeShift)
                case .airCursor:
                    AirCursorTrainingView(module: appState.registry.airCursor)
                case .ghostDrop:
                    GhostDropTrainingView(module: appState.registry.ghostDrop)
                case .portalView:
                    PortalViewTrainingView(module: appState.registry.portalView)
                case .notchBar:
                    NotchBarTrainingView(module: appState.registry.notchBar)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.95))
        }
        .frame(minWidth: 780, minHeight: 620)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Training Module enum

enum TrainingModule: String, CaseIterable, Identifiable {
    case handCommand, gazeShift, airCursor, ghostDrop, portalView, notchBar

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .handCommand: return "HandCommand"
        case .gazeShift:   return "GazeShift"
        case .airCursor:   return "AirCursor"
        case .ghostDrop:   return "GhostDrop"
        case .portalView:  return "PortalView"
        case .notchBar:    return "NotchBar"
        }
    }

    var systemImage: String {
        switch self {
        case .handCommand: return "hand.raised"
        case .gazeShift:   return "eye"
        case .airCursor:   return "iphone.radiowaves.left.and.right"
        case .ghostDrop:   return "hand.draw"
        case .portalView:  return "rectangle.on.rectangle"
        case .notchBar:    return "menubar.rectangle"
        }
    }
}

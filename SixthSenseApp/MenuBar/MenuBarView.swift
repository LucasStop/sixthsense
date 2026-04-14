import SwiftUI
import SixthSenseCore

// MARK: - Menu Bar View

/// Popover shown when the user clicks the SixthSense icon in the menu
/// bar. Focused on a single feature (HandCommand), so it has one big
/// toggle on top, a live status panel underneath, and a dropdown menu
/// with the app actions at the bottom.
struct MenuBarView: View {
    let appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            mainSection
            Divider()
            footer
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fingers.spread")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("SixthSense")
                    .font(.headline)
                Text("Controle seu Mac com gestos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private var statusBadge: some View {
        let active = appState.registry.handCommand.state.isActive
        return HStack(spacing: 5) {
            Circle()
                .fill(active ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 7, height: 7)
            Text(active ? "Ativo" : "Desligado")
                .font(.caption2.weight(.medium))
                .foregroundStyle(active ? .green : .secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(
            Capsule().fill((active ? Color.green : Color.secondary).opacity(0.12))
        )
    }

    // MARK: - Main section (big toggle + quick gesture reference)

    private var mainSection: some View {
        VStack(spacing: 14) {
            bigToggle
            quickReference
        }
        .padding(16)
    }

    private var bigToggle: some View {
        let module = appState.registry.handCommand
        let active = module.state.isActive

        return Button {
            Task { await appState.registry.toggleHandCommand() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(active ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.1))
                        .frame(width: 48, height: 48)
                    Image(systemName: active ? "hand.raised.fill" : "hand.raised")
                        .font(.title2)
                        .foregroundStyle(active ? Color.accentColor : .secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(active ? "Controle ativo" : "Ativar controle")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(active ? "Toque para desligar" : "Toque para começar")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: active ? "stop.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(active ? .red : .accentColor)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(active ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var quickReference: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GESTOS ATIVOS")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            gestureRow(icon: "hand.point.up.left", color: .cyan,
                       title: "Mover", subtitle: "Mão direita aponta")
            gestureRow(icon: "hand.pinch", color: .pink,
                       title: "Clicar", subtitle: "Mão esquerda pinça")
            gestureRow(icon: "hand.raised.fill", color: .orange,
                       title: "Arrastar", subtitle: "Mão esquerda punho")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.secondary.opacity(0.05))
        )
    }

    private func gestureRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
            Spacer()
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Spacer()
            actionsMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                openWindow(id: "hand-training")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            } label: {
                Label("Modo Treinamento", systemImage: "hand.raised.fingers.spread")
            }

            Button {
                openWindow(id: "tutorials")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            } label: {
                Label("Tutorial", systemImage: "book")
            }

            Button {
                openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            } label: {
                Label("Configurações", systemImage: "gear")
            }

            Divider()

            Button {
                NotificationCenter.default.post(name: .sixthSenseOpenSetup, object: nil)
            } label: {
                Label("Configuração Inicial", systemImage: "checklist")
            }

            Button {
                NotificationCenter.default.post(name: .sixthSenseOpenEnrollment, object: nil)
            } label: {
                Label("Reconhecimento Facial", systemImage: "face.dashed")
            }

            Divider()

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Sair do SixthSense", systemImage: "power")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "ellipsis.circle")
                    .font(.callout)
                Text("Menu")
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

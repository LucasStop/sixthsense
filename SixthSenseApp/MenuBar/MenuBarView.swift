import SwiftUI
import SixthSenseCore

// MARK: - Menu Bar View

/// Main popover content shown when clicking the menu bar icon.
struct MenuBarView: View {
    let appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header

            Divider()

            // Module list
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(appState.registry.modules) { module in
                        ModuleToggleRow(
                            module: module,
                            onToggle: {
                                Task { await appState.registry.toggle(module) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            // Footer
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Image(systemName: "hand.raised.fingers.spread")
                .font(.title2)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("SixthSense")
                    .font(.headline)
                Text("Controle Futurista do Mac")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            let activeCount = appState.registry.modules.filter { $0.state.isActive }.count
            if activeCount > 0 {
                Text("\(activeCount) ativo(s)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.green.opacity(0.2))
                    .foregroundStyle(.green)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            versionBadge
            Spacer()
            actionsMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var versionBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("SixthSense")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button {
                openWindow(id: "tutorials")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            } label: {
                Label("Tutoriais", systemImage: "book")
            }

            Button {
                openWindow(id: "training-center")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
            } label: {
                Label("Treinamento", systemImage: "hand.raised.fingers.spread")
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

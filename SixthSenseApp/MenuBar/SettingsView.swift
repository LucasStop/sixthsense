import SwiftUI
import SixthSenseCore
import SharedServices
import HandCommandModule

// MARK: - Settings View

/// Tabbed settings window with HandCommand controls, a permissions tab
/// and an About tab. Auto-refreshes permission state so changes made in
/// System Settings show up without reopening the window.
struct SettingsView: View {
    let appState: AppState

    var body: some View {
        TabView {
            HandCommandSettingsTab(module: appState.registry.handCommand)
                .tabItem {
                    Label("HandCommand", systemImage: "hand.raised.fingers.spread")
                }

            PermissionsSettingsTab(permissions: appState.services.permissions)
                .tabItem {
                    Label("Permissões", systemImage: "lock.shield")
                }

            AboutSettingsTab()
                .tabItem {
                    Label("Sobre", systemImage: "info.circle")
                }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - HandCommand tab

private struct HandCommandSettingsTab: View {
    let module: HandCommandModule

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(module.state.isActive ? .green : .secondary)
                            .frame(width: 8, height: 8)
                        Text(module.state.label)
                            .foregroundStyle(module.state.isActive ? .green : .secondary)
                    }
                }
            } header: {
                Text("Estado")
            }

            Section {
                module.settingsView
            } header: {
                Text("Sensibilidade")
            } footer: {
                Text("A mão direita move o cursor (indicador). A mão esquerda pinça para clicar e fecha o punho para arrastar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Permissions tab

private struct PermissionsSettingsTab: View {
    let permissions: PermissionsManager
    @State private var ticker = 0

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                PermissionRow(
                    type: .camera,
                    granted: permissions.cameraGranted,
                    action: { Task { _ = await permissions.requestCamera() } }
                )
                PermissionRow(
                    type: .accessibility,
                    granted: permissions.accessibilityGranted,
                    action: { permissions.openAccessibilitySettings() }
                )
            } header: {
                Text("Permissões Necessárias")
            } footer: {
                Text("A acessibilidade permanece concedida entre rebuilds porque o app é instalado em ~/Applications com assinatura ad-hoc estável. Se alguma permissão for invalidada, use \"Configuração Inicial\" no menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onReceive(timer) { _ in
            permissions.refreshAll()
            ticker &+= 1
        }
        .onAppear { permissions.refreshAll() }
    }
}

private struct PermissionRow: View {
    let type: PermissionType
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.systemImage)
                .font(.title3)
                .foregroundStyle(granted ? .green : .blue)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(type.label)
                    .font(.callout.weight(.medium))
                Text(type.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if granted {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.title3)
            } else {
                Button("Conceder", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - About tab

private struct AboutSettingsTab: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "hand.raised.fingers.spread")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.top, 20)

            Text("SixthSense")
                .font(.title.weight(.semibold))
            Text("Controle seu Mac com gestos de mão.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()
                .padding(.horizontal, 60)

            VStack(spacing: 8) {
                labeledRow("Versão", "1.0.0")
                labeledRow("Arquitetura", "arm64")
                labeledRow("macOS mínimo", "14.0 (Sonoma)")
                labeledRow("Bundle ID", "com.lucasstop.sixthsense")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func labeledRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .monospaced()
        }
        .frame(maxWidth: 320)
    }
}

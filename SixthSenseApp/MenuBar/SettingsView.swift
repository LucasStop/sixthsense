import SwiftUI
import SixthSenseCore
import SharedServices

// MARK: - Settings View

struct SettingsView: View {
    let appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab(appState: appState)
                .tabItem { Label("General", systemImage: "gear") }

            ForEach(appState.registry.modules) { module in
                module.settingsView
                    .tabItem {
                        Label(module.descriptor.name, systemImage: module.descriptor.systemImage)
                    }
            }

            PermissionsSettingsTab(permissions: appState.services.permissions)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
        }
        .frame(width: 600, height: 400)
    }
}

// MARK: - General Settings

struct GeneralSettingsTab: View {
    let appState: AppState
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
            }

            Section("Modules") {
                ForEach(appState.registry.modules) { module in
                    HStack {
                        Image(systemName: module.descriptor.systemImage)
                        Text(module.descriptor.name)
                        Spacer()
                        Circle()
                            .fill(module.state.color)
                            .frame(width: 8, height: 8)
                        Text(module.state.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Permissions Settings

struct PermissionsSettingsTab: View {
    let permissions: PermissionsManager

    var body: some View {
        Form {
            Section("System Permissions") {
                PermissionRow(name: "Camera", icon: "camera",
                             granted: permissions.cameraGranted,
                             action: { Task { await permissions.requestCamera() } })

                PermissionRow(name: "Accessibility", icon: "accessibility",
                             granted: permissions.accessibilityGranted,
                             action: { permissions.openAccessibilitySettings() })

                PermissionRow(name: "Screen Recording", icon: "rectangle.dashed.badge.record",
                             granted: permissions.screenRecordingGranted,
                             action: { permissions.openScreenRecordingSettings() })
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct PermissionRow: View {
    let name: String
    let icon: String
    let granted: Bool
    let action: () -> Void

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
            Text(name)
            Spacer()
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Grant") { action() }
                    .controlSize(.small)
            }
        }
    }
}

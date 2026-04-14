import SwiftUI
import SixthSenseCore

// MARK: - Menu Bar View

/// Main popover content shown when clicking the menu bar icon.
struct MenuBarView: View {
    let appState: AppState
    @Environment(\.openSettings) private var openSettings

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
                Text("Futuristic Mac Control")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            let activeCount = appState.registry.modules.filter { $0.state.isActive }.count
            if activeCount > 0 {
                Text("\(activeCount) active")
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
        HStack {
            Button(action: {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            }) {
                Label("Settings", systemImage: "gear")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button(action: {
                NSApplication.shared.terminate(nil)
            }) {
                Label("Quit", systemImage: "power")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

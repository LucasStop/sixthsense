import SwiftUI
import SixthSenseCore

// MARK: - Module Toggle Row

/// A single row in the menu bar popover representing one module.
struct ModuleToggleRow: View {
    let module: AnyModule
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Module icon
            Image(systemName: module.descriptor.systemImage)
                .font(.title3)
                .frame(width: 28, height: 28)
                .foregroundStyle(module.state.isActive ? .primary : .secondary)

            // Module info
            VStack(alignment: .leading, spacing: 2) {
                Text(module.descriptor.name)
                    .font(.system(.body, weight: .medium))

                Text(module.descriptor.tagline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Status indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(module.state.color)
                    .frame(width: 6, height: 6)

                if module.state == .starting || module.state == .stopping {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            // Toggle
            Toggle("", isOn: Binding(
                get: { module.state.isActive },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .controlSize(.small)
            .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(module.state.isActive ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

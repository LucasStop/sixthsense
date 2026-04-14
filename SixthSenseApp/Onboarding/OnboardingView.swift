import SwiftUI

// MARK: - Onboarding / Tutorial Hub

struct OnboardingView: View {
    @State private var selectedGuideId: String?

    private var selectedGuide: ModuleGuide? {
        ModuleGuide.allGuides.first { $0.id == selectedGuideId }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .frame(minWidth: 750, minHeight: 550)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(ModuleGuide.allGuides, selection: $selectedGuideId) { guide in
            SidebarRow(guide: guide)
        }
        .listStyle(.sidebar)
        .navigationTitle("Tutoriais")
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if let guide = selectedGuide {
            ModuleGuideView(guide: guide)
        } else {
            welcomeView
        }
    }

    // MARK: - Welcome

    private var welcomeView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "hand.raised.fingers.spread")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("Bem-vindo ao SixthSense")
                .font(.largeTitle.bold())

            Text("Escolha um módulo na barra lateral para aprender a usá-lo.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()
                .frame(width: 200)

            Text("Início Rápido")
                .font(.headline)

            quickStartGrid

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var quickStartGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible())
        ], spacing: 12) {
            ForEach(ModuleGuide.allGuides) { guide in
                QuickStartButton(guide: guide) {
                    selectedGuideId = guide.id
                }
            }
        }
        .frame(maxWidth: 450)
    }
}

// MARK: - Extracted Subviews

private struct SidebarRow: View {
    let guide: ModuleGuide

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: guide.icon)
                .font(.body)
                .frame(width: 24)
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(guide.name)
                    .font(.system(.body, weight: .medium))
                Text(guide.tagline)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct QuickStartButton: View {
    let guide: ModuleGuide
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: guide.icon)
                    .font(.title2)
                Text(guide.name)
                    .font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.quaternary)
            )
        }
        .buttonStyle(.plain)
    }
}

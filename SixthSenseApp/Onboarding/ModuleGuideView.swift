import SwiftUI

// MARK: - Module Guide Detail View

/// Renders the full tutorial for HandCommand: hero header, overview,
/// requirements, numbered steps, gesture cards and pro tips. Ends with a
/// CTA to jump into the Training window.
struct ModuleGuideView: View {
    let guide: ModuleGuide
    @State private var currentStep = 0
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                heroHeader
                overviewSection
                requirementsSection
                stepsSection
                if !guide.gestures.isEmpty {
                    gesturesSection
                }
                tipsSection
                callToAction
            }
            .padding(32)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Hero Header

    private var heroHeader: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.25), .purple.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)
                Image(systemName: guide.icon)
                    .font(.system(size: 36))
                    .foregroundStyle(.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(guide.name)
                    .font(.largeTitle.weight(.semibold))
                Text(guide.tagline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        Section(title: "Visão Geral", icon: "info.circle") {
            Text(guide.overview)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }

    // MARK: - Requirements

    private var requirementsSection: some View {
        Section(title: "Requisitos", icon: "checkmark.shield") {
            VStack(spacing: 10) {
                ForEach(guide.requirements) { req in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: req.icon)
                            .font(.title3)
                            .foregroundStyle(.tint)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(req.name)
                                .font(.callout.weight(.semibold))
                            Text(req.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.secondary.opacity(0.06))
                    )
                }
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        Section(title: "Passo a Passo", icon: "list.number") {
            VStack(spacing: 10) {
                ForEach(guide.steps) { step in
                    stepRow(step: step)
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                currentStep = step.id - 1
                            }
                        }
                }

                HStack {
                    Text("Progresso: \(currentStep + 1) de \(guide.steps.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if currentStep < guide.steps.count - 1 {
                        Button("Próximo") {
                            withAnimation { currentStep += 1 }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    } else {
                        Label("Concluído", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func stepRow(step: GuideStep) -> some View {
        let isActive = step.id == currentStep + 1
        let isPast = step.id <= currentStep + 1

        return HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(isPast ? Color.accentColor : Color.secondary.opacity(0.2))
                    .frame(width: 34, height: 34)
                Text("\(step.id)")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(isPast ? .white : .secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                    .font(.body.weight(.semibold))
                Text(step.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Image(systemName: step.icon)
                .font(.title3)
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.7)))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? Color.accentColor.opacity(0.08) : .secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.accentColor.opacity(0.4) : .clear, lineWidth: 1)
        )
    }

    // MARK: - Gestures

    private var gesturesSection: some View {
        Section(title: "Gestos", icon: "hand.tap") {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(Array(guide.gestures.enumerated()), id: \.offset) { index, gesture in
                    gestureCard(gesture: gesture, accent: gestureColor(for: index))
                }
            }
        }
    }

    private func gestureCard(gesture: GestureInfo, accent: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: gesture.icon)
                .font(.system(size: 32))
                .foregroundStyle(accent)
                .frame(width: 64, height: 64)
                .background(accent.opacity(0.12), in: Circle())

            Text(gesture.name)
                .font(.callout.weight(.semibold))

            Text(gesture.action)
                .font(.caption2)
                .foregroundStyle(accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(accent.opacity(0.15), in: Capsule())

            Text(gesture.howTo)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(accent.opacity(0.25), lineWidth: 1)
        )
    }

    private func gestureColor(for index: Int) -> Color {
        switch index {
        case 0: return .cyan
        case 1: return .pink
        case 2: return .orange
        case 3: return .purple
        default: return .blue
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        Section(title: "Dicas", icon: "lightbulb") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(guide.tips.enumerated()), id: \.offset) { _, tip in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "sparkles")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .padding(.top, 3)
                        Text(tip)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Call to action

    private var callToAction: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "hand.raised.fingers.spread")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pronto para praticar?")
                        .font(.headline)
                    Text("Abra o Modo Treinamento para ver o rastreamento em tempo real.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openWindow(id: "hand-training")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApplication.shared.activate(ignoringOtherApps: true)
                    }
                } label: {
                    Label("Abrir Treinamento", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.tint.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.tint.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Section wrapper

private struct Section<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(.primary)
            content()
        }
    }
}

import SwiftUI

// MARK: - Module Guide Detail View

/// Full tutorial/training view for a single module.
struct ModuleGuideView: View {
    let guide: ModuleGuide
    @State private var currentStep = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                header

                Divider()

                // Overview
                overviewSection

                // Requirements
                requirementsSection

                Divider()

                // Step-by-step tutorial
                stepsSection

                Divider()

                // Gestures / Controls
                if !guide.gestures.isEmpty {
                    gesturesSection
                    Divider()
                }

                // Tips
                tipsSection
            }
            .padding(24)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: guide.icon)
                .font(.system(size: 36))
                .foregroundStyle(.blue)
                .frame(width: 56, height: 56)
                .background(Color.accentColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(guide.name)
                    .font(.title.bold())
                Text(guide.tagline)
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Visão Geral", systemImage: "info.circle")
                .font(.headline)

            Text(guide.overview)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Requirements

    private var requirementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Requisitos", systemImage: "checkmark.shield")
                .font(.headline)

            ForEach(guide.requirements) { req in
                HStack(spacing: 12) {
                    Image(systemName: req.icon)
                        .font(.body)
                        .frame(width: 28, height: 28)
                        .foregroundStyle(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(req.name)
                            .font(.system(.body, weight: .medium))
                        Text(req.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Steps

    private var stepsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Passo a Passo", systemImage: "list.number")
                .font(.headline)

            ForEach(guide.steps) { step in
                HStack(alignment: .top, spacing: 14) {
                    // Step number circle
                    ZStack {
                        Circle()
                            .fill(step.id <= currentStep + 1 ? Color.accentColor : Color.secondary.opacity(0.2))
                            .frame(width: 32, height: 32)

                        Text("\(step.id)")
                            .font(.system(.callout, weight: .bold))
                            .foregroundStyle(step.id <= currentStep + 1 ? .white : .secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title)
                            .font(.system(.body, weight: .semibold))

                        Text(step.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Image(systemName: step.icon)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(step.id == currentStep + 1 ? Color.accentColor.opacity(0.06) : Color.clear)
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        currentStep = step.id - 1
                    }
                }
            }

            // Progress
            HStack {
                Text("Progresso: Passo \(currentStep + 1) de \(guide.steps.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if currentStep < guide.steps.count - 1 {
                    Button("Próximo Passo") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Label("Pronto!", systemImage: "checkmark.circle.fill")
                        .font(.callout.bold())
                        .foregroundStyle(.green)
                }
            }
        }
    }

    // MARK: - Gestures

    private var gesturesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Gestos e Controles", systemImage: "hand.tap")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(guide.gestures) { gesture in
                    VStack(spacing: 8) {
                        Image(systemName: gesture.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(.blue)

                        Text(gesture.name)
                            .font(.system(.callout, weight: .bold))

                        Text(gesture.action)
                            .font(.caption)
                            .foregroundStyle(.orange)

                        Text(gesture.howTo)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.quaternary)
                    )
                }
            }
        }
    }

    // MARK: - Tips

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Dicas Pro", systemImage: "lightbulb")
                .font(.headline)

            ForEach(Array(guide.tips.enumerated()), id: \.offset) { _, tip in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.caption2)
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

import SwiftUI
import SixthSenseCore
import SharedServices
import NotchBarModule

/// Mostra se o notch foi detectado, o frame calculado, e um preview
/// desenhado do overlay que é (ou seria) renderizado na barra.
struct NotchBarTrainingView: View {
    let module: NotchBarModule

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusRow
            preview
            infoCard
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "menubar.rectangle")
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("NotchBar — Barra no Notch")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Transforma o notch em um centro de controle interativo.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            statusCard(
                title: "Notch detectado",
                value: module.hasDetectedNotch ? "Sim" : "Não",
                icon: module.hasDetectedNotch ? "checkmark.seal" : "exclamationmark.triangle",
                color: module.hasDetectedNotch ? .green : .orange
            )
            statusCard(
                title: "Auto-ocultar",
                value: module.autoHide ? "Ligado" : "Desligado",
                icon: "eye",
                color: module.autoHide ? .cyan : .white.opacity(0.5)
            )
            statusCard(
                title: "Estado",
                value: module.state.label,
                icon: module.state.systemImage,
                color: module.state == .running ? .green : .white.opacity(0.5)
            )
        }
    }

    private func statusCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview da barra")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            ZStack {
                // Fake "screen" backdrop
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color(white: 0.15), Color(white: 0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(height: 140)

                // Fake notch mimicking a MacBook Pro display cutout
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.6))
                            Text("SixthSense")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.8))
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.green)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6)
                        .background(.black, in: Capsule())
                        Spacer()
                    }
                    .padding(.top, 8)
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Frame calculado")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            if let frame = module.notchFrame {
                Text(String(format: "x: %.0f  y: %.0f  w: %.0f  h: %.0f",
                            frame.origin.x, frame.origin.y, frame.size.width, frame.size.height))
                    .font(.callout.monospaced())
                    .foregroundStyle(.white)
            } else {
                Text("Ative a NotchBar para calcular o frame.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

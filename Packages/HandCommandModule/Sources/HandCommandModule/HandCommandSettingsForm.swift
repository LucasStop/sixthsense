import SwiftUI
import SixthSenseCore

// MARK: - HandCommand Settings Form

/// SwiftUI form surfaced by `HandCommandModule.settingsView`. Kept as a
/// standalone View (instead of inline in the module) so SwiftUI properly
/// tracks @Observable updates on `sensitivity` when the slider moves.
public struct HandCommandSettingsForm: View {
    @Bindable var module: HandCommandModule

    public init(module: HandCommandModule) {
        self.module = module
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Sensitivity slider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Velocidade do cursor")
                        .font(.callout.weight(.medium))
                    Spacer()
                    Text(String(format: "%.1fx", module.sensitivity))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Slider(
                    value: $module.sensitivity,
                    in: 0.3...3.0,
                    step: 0.1
                ) {
                    Text("Velocidade")
                } minimumValueLabel: {
                    Image(systemName: "tortoise.fill")
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Image(systemName: "hare.fill")
                        .foregroundStyle(.secondary)
                }

                Text(sensitivityHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Live preview of the effective usable zone
            VStack(alignment: .leading, spacing: 6) {
                Text("Zona útil da câmera")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text("A mão precisa se mover dentro desta área para cobrir a tela toda. Valores maiores de velocidade encolhem a zona útil.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DeadzonePreview(
                    effectiveDeadzone: module.effectiveDeadzone
                )
                .frame(height: 90)
            }

            Divider()

            // Quick reset
            HStack {
                Spacer()
                Button("Restaurar padrão") {
                    module.sensitivity = 1.0
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var sensitivityHint: String {
        if module.sensitivity <= 0.6 {
            return "Ideal para movimentos grandes e precisos. Você vai precisar mover mais a mão para atravessar a tela."
        } else if module.sensitivity <= 1.3 {
            return "Equilíbrio padrão entre precisão e velocidade."
        } else if module.sensitivity <= 2.0 {
            return "Responde rápido. Pequenos movimentos da mão cobrem boa parte da tela."
        } else {
            return "Extremamente rápido. Perfeito para telas grandes; requer mais estabilidade da mão."
        }
    }
}

// MARK: - Deadzone Preview

/// Tiny visualisation that draws the camera frame as a rectangle and
/// highlights the "usable" region based on the effective deadzone. Users
/// can see the zone shrink/expand as they drag the sensitivity slider.
private struct DeadzonePreview: View {
    let effectiveDeadzone: Double

    var body: some View {
        GeometryReader { geo in
            let usableInsetX = CGFloat(effectiveDeadzone) * geo.size.width
            let usableInsetY = CGFloat(effectiveDeadzone) * geo.size.height

            ZStack {
                // Camera frame
                RoundedRectangle(cornerRadius: 10)
                    .fill(.secondary.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(.secondary.opacity(0.3), lineWidth: 1)
                    )

                // Usable region
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.25))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    )
                    .padding(.horizontal, usableInsetX)
                    .padding(.vertical, usableInsetY)

                // Label
                Text("Zona útil")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .animation(.easeInOut(duration: 0.15), value: effectiveDeadzone)
        }
    }
}

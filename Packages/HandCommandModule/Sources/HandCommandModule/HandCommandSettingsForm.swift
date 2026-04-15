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

            // Per-gesture enable toggles
            gestureToggles

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
                    module.clickEnabled = true
                    module.dragEnabled = true
                    module.scrollEnabled = true
                    module.missionControlEnabled = true
                    module.appSwitcherEnabled = true
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private var gestureToggles: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Gestos ativos")
                .font(.callout.weight(.medium))

            Text("Desative aqui os gestos que você não quer. O movimento do cursor (mão direita apontando) é sempre ativo — sem ele o controle não funciona.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                gestureToggleRow(
                    icon: "hand.pinch",
                    color: .pink,
                    label: "Clicar",
                    hint: "Mão esquerda faz pinça",
                    isOn: $module.clickEnabled
                )
                gestureToggleRow(
                    icon: "hand.raised.fill",
                    color: .orange,
                    label: "Arrastar",
                    hint: "Mão esquerda fecha o punho",
                    isOn: $module.dragEnabled
                )
                gestureToggleRow(
                    icon: "arrow.triangle.2.circlepath",
                    color: .purple,
                    label: "Rolar",
                    hint: "Círculo no ar com a esquerda",
                    isOn: $module.scrollEnabled
                )
                gestureToggleRow(
                    icon: "rectangle.on.rectangle",
                    color: .mint,
                    label: "Mission Control",
                    hint: "Punho direito fechado por ~½s",
                    isOn: $module.missionControlEnabled
                )
                gestureToggleRow(
                    icon: "square.on.square",
                    color: .yellow,
                    label: "Trocar app (⌘+Tab)",
                    hint: "Shaka com a esquerda",
                    isOn: $module.appSwitcherEnabled
                )
            }
        }
    }

    private func gestureToggleRow(
        icon: String,
        color: Color,
        label: String,
        hint: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.callout)
                    .foregroundStyle(color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(.callout)
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .toggleStyle(.switch)
        .controlSize(.small)
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

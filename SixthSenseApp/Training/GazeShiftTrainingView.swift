import SwiftUI
import SixthSenseCore
import SharedServices
import GazeShiftModule

/// Mostra em tempo real o ponto estimado do olhar sobre uma miniatura
/// da tela, mais o título da janela que está em foco.
struct GazeShiftTrainingView: View {
    let module: GazeShiftModule

    var body: some View {
        VStack(spacing: 16) {
            header
            gazeCanvas
            focusCard
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "eye")
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("GazeShift — Rastreamento do Olhar")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("O ponto indica onde o sistema acha que você está olhando.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        Group {
            if module.state == .running {
                Label("Ativo", systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("Desligado", systemImage: "circle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.white.opacity(0.06), in: Capsule())
    }

    private var gazeCanvas: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.08), Color(white: 0.02)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                // Screen frame outline for context
                RoundedRectangle(cornerRadius: 12)
                    .stroke(.white.opacity(0.15), lineWidth: 1)
                    .padding(16)

                // Gaze point (scaled to canvas)
                if let point = module.latestGazePoint,
                   let screen = NSScreen.main {
                    let canvasRect = geo.frame(in: .local).insetBy(dx: 16, dy: 16)
                    let nx = point.x / screen.frame.width
                    let ny = point.y / screen.frame.height
                    let x = canvasRect.minX + nx * canvasRect.width
                    let y = canvasRect.minY + ny * canvasRect.height

                    Circle()
                        .fill(.orange)
                        .frame(width: 18, height: 18)
                        .shadow(color: .orange.opacity(0.7), radius: 10)
                        .position(x: x, y: y)
                        .animation(.easeOut(duration: 0.2), value: point)

                    Circle()
                        .stroke(.orange.opacity(0.4), lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .position(x: x, y: y)
                }

                if module.latestGazePoint == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash")
                            .font(.system(size: 42))
                            .foregroundStyle(.white.opacity(0.3))
                        Text("Nenhum rosto detectado")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.7))
                        Text(module.state == .running
                            ? "Aproxime-se da câmera e olhe para a tela."
                            : "Ative o GazeShift para começar.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var focusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "macwindow")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.07), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text("Janela em foco")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text(module.focusedWindowTitle ?? "Nenhuma")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text("Intensidade do Dim")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                Text(String(format: "%.0f%%", module.dimIntensity * 100))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.white)
            }
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

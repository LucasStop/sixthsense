import SwiftUI
import AVFoundation
import SixthSenseCore
import SharedServices
import HandCommandModule

// MARK: - Hand Training View

/// Janela de "Modo Treinamento" que mostra ao vivo o esqueleto da mão
/// detectado pelo HandCommand e rotula o gesto reconhecido. Serve como
/// ajuda visual para o usuário aprender os gestos disponíveis.
struct HandTrainingView: View {
    let handModule: HandCommandModule
    let cameraSession: (() -> AVCaptureSession?)

    @State private var showCameraFeed: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            header
            preview
            footer
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 600)
        .background(.black.opacity(0.92))
        .preferredColorScheme(.dark)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.raised.fingers.spread")
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Modo Treinamento de Gestos")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Veja em tempo real o que a câmera está detectando.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            Toggle(isOn: $showCameraFeed) {
                Label("Mostrar câmera", systemImage: "video")
                    .labelStyle(.titleAndIcon)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(.accentColor)
            .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var preview: some View {
        let left  = handModule.latestLeftSnapshot
        let right = handModule.latestRightSnapshot
        let anyHand = left ?? right

        ZStack {
            if showCameraFeed, let session = cameraSession() {
                CameraPreviewView(session: session)
                    .overlay(
                        LinearGradient(
                            colors: [.black.opacity(0.25), .clear, .black.opacity(0.35)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            } else {
                LinearGradient(
                    colors: [.black, Color(white: 0.08)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            // Right hand in cyan, left hand in pink. The tint applies to
            // finger chains + wrist, while individual finger dots keep
            // their own color so you can still tell which finger is which.
            if let right {
                HandSkeletonCanvas(snapshot: right, tint: .cyan)
            }
            if let left {
                HandSkeletonCanvas(snapshot: left, tint: .pink)
            }

            if anyHand == nil {
                statusOverlay(
                    icon: "hand.raised.slash",
                    title: "Nenhuma mão detectada",
                    subtitle: handModule.state == .running
                        ? "Mostre uma ou as duas mãos para a câmera."
                        : "Ative o HandCommand para começar a detectar."
                )
            }

            // On-screen hint explaining which side is which
            VStack {
                HStack {
                    handHint("Mão Esquerda", color: .pink)
                    Spacer()
                    handHint("Mão Direita", color: .cyan)
                }
                Spacer()
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var footer: some View {
        let rightGesture = handModule.latestRightSnapshot?.gesture ?? .none
        let leftGesture  = handModule.latestLeftSnapshot?.gesture ?? .none

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                handCard(title: "Mão Esquerda — Atalhos", gesture: leftGesture, tint: .pink)
                handCard(title: "Mão Direita — Cursor", gesture: rightGesture, tint: .cyan)
            }

            gestureLegend
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

            debugCard
        }
    }

    private var debugCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Log de detecção (mais recente primeiro)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            if handModule.debugLines.isEmpty {
                Text("—")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.white.opacity(0.3))
            } else {
                ForEach(Array(handModule.debugLines.prefix(5).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func handHint(_ text: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(.black.opacity(0.55), in: Capsule())
    }

    private func handCard(title: String, gesture: DetectedHandGesture, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: gesture.systemImage)
                .font(.title2)
                .foregroundStyle(gesture == .none ? .white.opacity(0.4) : tint)
                .frame(width: 40, height: 40)
                .background(.white.opacity(0.07), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
                Text(gesture.label)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: gesture)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var gestureLegend: some View {
        HStack(spacing: 10) {
            ForEach(DetectedHandGesture.allCases.filter { $0 != .none }, id: \.self) { g in
                VStack(spacing: 4) {
                    Image(systemName: g.systemImage)
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(g.label)
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(width: 56)
            }
        }
    }

    private func statusOverlay(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 42))
                .foregroundStyle(.white.opacity(0.4))
            Text(title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.85))
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(24)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
    }
}

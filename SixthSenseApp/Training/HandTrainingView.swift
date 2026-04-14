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
        let snapshot = handModule.latestSnapshot

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

            HandSkeletonCanvas(snapshot: snapshot)

            if snapshot == nil {
                statusOverlay(
                    icon: "hand.raised.slash",
                    title: "Nenhuma mão detectada",
                    subtitle: handModule.state == .running
                        ? "Mostre sua mão para a câmera."
                        : "Ative o HandCommand para começar a detectar."
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var footer: some View {
        let gesture = handModule.latestSnapshot?.gesture ?? .none

        return HStack(spacing: 16) {
            Image(systemName: gesture.systemImage)
                .font(.largeTitle)
                .foregroundStyle(gesture == .none ? .white.opacity(0.5) : .accentColor)
                .frame(width: 56, height: 56)
                .background(.white.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Gesto atual")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                Text(gesture.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: gesture)
            }

            Spacer()

            gestureLegend
        }
        .padding(12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
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

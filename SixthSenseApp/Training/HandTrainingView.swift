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
    let faceRecognition: FaceRecognitionManager
    let cameraSession: (() -> AVCaptureSession?)

    @State private var showCameraFeed: Bool = true
    @State private var diagnosticsState: AccessibilityDiagnosticsState = .unknown
    @State private var lastProbeResult: AccessibilityDiagnostics.InjectionProbeResult?
    @State private var copiedPath: Bool = false

    private let diagnosticsTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 16) {
            header
            diagnosticsCard
            faceLockCard
            preview
            footer
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 760)
        .background(.black.opacity(0.92))
        .preferredColorScheme(.dark)
        .onAppear {
            refreshDiagnostics()
        }
        .onReceive(diagnosticsTimer) { _ in
            refreshDiagnostics()
        }
    }

    // MARK: - Face lock card

    @ViewBuilder
    private var faceLockCard: some View {
        let state = faceRecognition.state

        if state.mode == .disabled {
            // Don't take up space when the user has no face lock configured.
            EmptyView()
        } else {
            HStack(spacing: 12) {
                Image(systemName: faceLockIcon(for: state))
                    .font(.title3)
                    .foregroundStyle(faceLockColor(for: state))
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.statusLabel)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                    Text("Modo: \(state.mode.label)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                if let dist = state.recognitionDistance, state.mode == .enrolledFace {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Distância")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                        Text(String(format: "%.1f", dist))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                Circle()
                    .fill(state.canUseGestures ? Color.green : Color.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: state.canUseGestures ? .green : .red, radius: 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                faceLockColor(for: state).opacity(0.10),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(faceLockColor(for: state).opacity(0.35), lineWidth: 1)
            )
        }
    }

    private func faceLockIcon(for state: FaceRecognitionState) -> String {
        if !state.isFaceDetected { return "face.dashed" }
        if !state.isLookingAtScreen { return "eye.slash" }
        if state.mode == .enrolledFace && !state.isRecognizedUser { return "person.crop.circle.badge.xmark" }
        return "person.crop.circle.badge.checkmark"
    }

    private func faceLockColor(for state: FaceRecognitionState) -> Color {
        state.canUseGestures ? .green : .orange
    }

    // MARK: - Diagnostics state

    private enum AccessibilityDiagnosticsState {
        case unknown
        case granted
        case denied
    }

    private func refreshDiagnostics() {
        diagnosticsState = AccessibilityDiagnostics.isTrusted ? .granted : .denied
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

    // MARK: - Diagnostics Card

    @ViewBuilder
    private var diagnosticsCard: some View {
        if diagnosticsState == .granted {
            compactDiagnosticsBar
        } else {
            expandedDiagnosticsPanel
        }
    }

    /// Barra compacta mostrada quando tudo está OK — não rouba espaço
    /// visual, mas ainda dá feedback imediato se algo mudar.
    private var compactDiagnosticsBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.callout)
                .foregroundStyle(.green)
            Text("Acessibilidade OK — CGEvent pode controlar o cursor")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
            Button {
                lastProbeResult = AccessibilityDiagnostics.performInjectionProbe()
            } label: {
                Label("Testar", systemImage: "play.circle")
                    .font(.caption2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))

            if let probe = lastProbeResult {
                Image(systemName: probe.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(probe.isSuccess ? .green : .red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.green.opacity(0.3), lineWidth: 1)
        )
    }

    /// Painel expandido quando há pendência de permissão.
    private var expandedDiagnosticsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: diagnosticsIcon)
                    .font(.title3)
                    .foregroundStyle(diagnosticsColor)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(diagnosticsTitle)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                    Text(diagnosticsSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Button {
                    lastProbeResult = AccessibilityDiagnostics.performInjectionProbe()
                    refreshDiagnostics()
                } label: {
                    Label("Testar injeção", systemImage: "play.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(.blue)
            }

            if diagnosticsState == .denied {
                deniedPanel
            }

            if let probe = lastProbeResult {
                probeResultLine(probe)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(diagnosticsColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(diagnosticsColor.opacity(0.35), lineWidth: 1)
        )
    }

    private var diagnosticsIcon: String {
        switch diagnosticsState {
        case .unknown: return "questionmark.circle"
        case .granted: return "checkmark.shield.fill"
        case .denied:  return "exclamationmark.shield.fill"
        }
    }

    private var diagnosticsColor: Color {
        switch diagnosticsState {
        case .unknown: return .white.opacity(0.5)
        case .granted: return .green
        case .denied:  return .orange
        }
    }

    private var diagnosticsTitle: String {
        switch diagnosticsState {
        case .unknown: return "Verificando acessibilidade..."
        case .granted: return "Acessibilidade OK"
        case .denied:  return "Acessibilidade bloqueada"
        }
    }

    private var diagnosticsSubtitle: String {
        switch diagnosticsState {
        case .unknown:
            return "Aguarde..."
        case .granted:
            return "CGEvent pode injetar cursor e teclado. Os gestos devem funcionar."
        case .denied:
            return "Mesmo que apareça marcado nos Ajustes, o binário atual não está autorizado."
        }
    }

    private var deniedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().background(.orange.opacity(0.4))

            Text("Como corrigir (SPM cria um binário novo a cada build):")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))

            VStack(alignment: .leading, spacing: 4) {
                stepLine("1.", "Abra Ajustes do Sistema → Privacidade → Acessibilidade.")
                stepLine("2.", "REMOVA toda entrada \"SixthSense\" existente (clique \"-\").")
                stepLine("3.", "Clique em \"+\" e adicione o binário com o caminho abaixo.")
                stepLine("4.", "Reative o HandCommand. Os gestos devem funcionar.")
            }

            HStack(spacing: 8) {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.caption)
                Text(AccessibilityDiagnostics.executablePath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.black.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                Button {
                    AccessibilityDiagnostics.copyExecutablePathToPasteboard()
                    copiedPath = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        copiedPath = false
                    }
                } label: {
                    Label(copiedPath ? "Copiado!" : "Copiar caminho", systemImage: "doc.on.clipboard")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    AccessibilityDiagnostics.openAccessibilitySettings()
                } label: {
                    Label("Abrir Ajustes", systemImage: "gear")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()
            }
        }
    }

    private func stepLine(_ num: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(num)
                .font(.caption.monospaced().weight(.bold))
                .foregroundStyle(.orange)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
            Spacer()
        }
    }

    private func probeResultLine(_ probe: AccessibilityDiagnostics.InjectionProbeResult) -> some View {
        HStack(spacing: 8) {
            Image(systemName: probe.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(probe.isSuccess ? .green : .red)
                .font(.caption)
            Text("Último teste: \(probe.label)")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
        }
        .padding(.top, 4)
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
        let rightDetected = handModule.latestRightSnapshot != nil
        let leftGesture  = handModule.latestLeftSnapshot?.gesture ?? .none

        // Describe what the left hand is doing right now.
        let leftIcon: String
        let leftDescription: String
        let leftActive: Bool
        if leftGesture == .fist {
            leftIcon = "hand.raised.fill"
            leftDescription = "Arrastando!"
            leftActive = true
        } else if leftGesture == .pinch {
            leftIcon = "hand.pinch.fill"
            leftDescription = "Clicando!"
            leftActive = true
        } else if leftGesture == .pointing {
            leftIcon = "arrow.up.arrow.down.circle.fill"
            leftDescription = "Rolando..."
            leftActive = true
        } else {
            leftIcon = "hand.pinch"
            leftDescription = "Pinça clica   •   Punho arrasta   •   Aponta rola"
            leftActive = false
        }

        return VStack(spacing: 12) {
            HStack(spacing: 12) {
                handSimpleCard(
                    title: "Mão Esquerda — Ações",
                    description: leftDescription,
                    icon: leftIcon,
                    tint: .pink,
                    active: leftActive
                )
                handSimpleCard(
                    title: "Mão Direita — Mover",
                    description: rightDetected ? "Rastreando dedo indicador" : "Mostre a mão para a câmera",
                    icon: "hand.point.up.left",
                    tint: .cyan,
                    active: rightDetected
                )
            }

            activeGesturesLegend
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))

            debugCard
        }
    }

    private var activeGesturesLegend: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gestos ativos")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.55))

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 14) {
                    legendItem(icon: "hand.point.up.left", color: .cyan,
                               label: "Mover cursor", description: "Mão direita aponta")
                    legendItem(icon: "hand.pinch", color: .pink,
                               label: "Clicar", description: "Mão esquerda faz pinça")
                }
                HStack(alignment: .top, spacing: 14) {
                    legendItem(icon: "hand.raised.fill", color: .orange,
                               label: "Arrastar", description: "Mão esquerda fecha o punho")
                    legendItem(icon: "arrow.up.arrow.down", color: .purple,
                               label: "Rolar", description: "Mão esquerda aponta pra cima/baixo")
                }
            }
        }
    }

    private func legendItem(icon: String, color: Color, label: String, description: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.callout)
                .foregroundStyle(color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(description)
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }
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

    private func handSimpleCard(
        title: String,
        description: String,
        icon: String,
        tint: Color,
        active: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(active ? tint : .white.opacity(0.35))
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(active ? tint.opacity(0.15) : .white.opacity(0.05))
                )
                .overlay(
                    Circle()
                        .stroke(active ? tint.opacity(0.6) : .clear, lineWidth: 1.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                Text(description)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(active ? .white : .white.opacity(0.6))
                    .contentTransition(.numericText())
                    .animation(.easeInOut(duration: 0.2), value: active)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(active ? tint.opacity(0.4) : .clear, lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.15), value: active)
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

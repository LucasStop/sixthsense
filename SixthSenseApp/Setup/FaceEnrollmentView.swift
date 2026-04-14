import SwiftUI
import AVFoundation
import SharedServices
import SixthSenseCore

// MARK: - Face Enrollment View

/// Face ID-style guided enrollment. The user moves their head slowly in
/// a circle while the view shows a ring of target segments around their
/// face. As each target is captured, its segment fills green. Live pose
/// feedback moves a dot inside the ring so the user can see exactly
/// which angle they're aimed at.
struct FaceEnrollmentView: View {
    let faceRecognition: FaceRecognitionManager
    let cameraSession: () -> AVCaptureSession?
    let onFinish: () -> Void

    @State private var phase: Phase = .introducing
    @State private var choice: Choice? = nil

    // MARK: - Phases

    private enum Phase {
        case introducing
        case capturing
        case choosing
        case done
    }

    private enum Choice: String, Hashable {
        case onlyMe
        case anyone
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 28)
                .padding(.horizontal, 36)
                .padding(.bottom, 18)

            Divider()

            content
                .padding(24)
                .frame(maxWidth: .infinity)

            Divider()

            footer
                .padding(20)
        }
        .frame(width: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: faceRecognition.isEnrollmentComplete) { _, complete in
            if phase == .capturing && complete {
                phase = .choosing
            }
        }
        .onDisappear {
            if faceRecognition.isEnrolling {
                faceRecognition.cancelEnrollment()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "face.dashed")
                .font(.system(size: 44))
                .foregroundStyle(.tint)

            Text(title)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var title: String {
        switch phase {
        case .introducing: return "Reconhecimento Facial"
        case .capturing:   return "Mova a cabeça em círculo"
        case .choosing:    return "Quem pode usar os gestos?"
        case .done:        return "Tudo pronto"
        }
    }

    private var subtitle: String {
        switch phase {
        case .introducing:
            return "Vamos cadastrar seu rosto em diferentes ângulos. É parecido com o Face ID do iPhone."
        case .capturing:
            return "Olhe para a câmera e gire lentamente a cabeça para completar o círculo."
        case .choosing:
            return "Rosto cadastrado com sucesso. Escolha quem vai poder controlar o Mac com gestos."
        case .done:
            return "Preferências salvas. Você pode mudar isso nas Configurações a qualquer momento."
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .introducing: introductionContent
        case .capturing:   capturingContent
        case .choosing:    choosingContent
        case .done:        doneContent
        }
    }

    // MARK: - Introducing

    private var introductionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Como o cadastro funciona:")
                .font(.callout.weight(.semibold))

            bullet(
                icon: "face.smiling",
                title: "Comece olhando reto para a câmera",
                description: "O ponto central é o primeiro alvo. Os outros 8 ficam em volta dele em círculo."
            )

            bullet(
                icon: "arrow.turn.up.right",
                title: "Mova a cabeça lentamente em círculo",
                description: "Aponte para cada segmento do anel. Quando estiver alinhado e o rosto estiver nítido, o segmento fica verde automaticamente."
            )

            bullet(
                icon: "checkmark.shield.fill",
                title: "Tudo roda localmente",
                description: "O rosto é guardado no seu Mac como um vetor de features, nunca sai do dispositivo e nenhuma foto é salva."
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Capturing

    private var capturingContent: some View {
        VStack(spacing: 18) {
            // Circular preview + ring
            ZStack {
                // Background camera feed clipped to a circle
                CameraPreviewView(session: cameraSession())
                    .frame(width: 300, height: 300)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )

                // Dim overlay for contrast
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.clear, .black.opacity(0.25)],
                            center: .center,
                            startRadius: 110,
                            endRadius: 160
                        )
                    )
                    .frame(width: 300, height: 300)

                // Segmented ring of targets
                EnrollmentRing(
                    targets: faceRecognition.enrollmentTargets,
                    completed: faceRecognition.enrollmentCompletedIds,
                    currentIndex: faceRecognition.enrollmentCurrentTargetIndex
                )
                .frame(width: 340, height: 340)

                // Live pose cursor (indicator of current face angle)
                if let pose = faceRecognition.enrollmentCurrentPose {
                    PoseCursor(pose: pose)
                        .frame(width: 300, height: 300)
                }
            }

            instructionCard

            qualityIndicator
        }
    }

    private var instructionCard: some View {
        let current = faceRecognition.enrollmentCurrentTarget
        let label = current?.label ?? "Prepare-se..."
        let icon = current?.systemImage ?? "face.dashed"

        return HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.15), in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout.weight(.semibold))
                Text("\(faceRecognition.enrollmentProgress) de \(faceRecognition.enrollmentTotal) ângulos capturados")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private var qualityIndicator: some View {
        let quality = faceRecognition.enrollmentQuality
        let visible = faceRecognition.enrollmentCurrentPose != nil
        return HStack(spacing: 8) {
            Image(systemName: visible ? qualityIcon(quality) : "face.dashed")
                .font(.caption)
                .foregroundStyle(visible ? qualityColor(quality) : .secondary)
            Text(visible ? qualityText(quality) : "Procurando rosto...")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func qualityIcon(_ q: Float) -> String {
        q < 0.4 ? "exclamationmark.triangle" :
        q < 0.6 ? "lightbulb" : "sparkles"
    }

    private func qualityColor(_ q: Float) -> Color {
        q < 0.4 ? .orange : q < 0.6 ? .yellow : .green
    }

    private func qualityText(_ q: Float) -> String {
        if q < 0.4 {
            return "Qualidade baixa — melhore a iluminação ou aproxime-se"
        } else if q < 0.6 {
            return "Qualidade razoável — tente olhar direto para a câmera"
        } else {
            return "Qualidade ótima"
        }
    }

    // MARK: - Choosing

    private var choosingContent: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 42))
                .foregroundStyle(.green)
                .padding(.top, 4)

            VStack(spacing: 12) {
                choiceCard(
                    .onlyMe,
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Apenas eu",
                    description: "Só o rosto cadastrado aciona os gestos, e apenas quando estiver olhando para a tela."
                )
                choiceCard(
                    .anyone,
                    icon: "person.2.circle",
                    title: "Qualquer pessoa",
                    description: "Qualquer rosto pode acionar os gestos, desde que esteja olhando para a tela."
                )
            }
        }
    }

    private func choiceCard(
        _ value: Choice,
        icon: String,
        title: String,
        description: String
    ) -> some View {
        let isSelected = choice == value
        return Button {
            choice = value
        } label: {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isSelected ? Color.accentColor : Color.accentColor.opacity(0.15))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        isSelected ? Color.accentColor.opacity(0.5) : .clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Done

    private var doneContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            Text("Preferências salvas!")
                .font(.title3.weight(.semibold))

            Text("O modo ativo agora é \(faceRecognition.store.lockMode.label.lowercased()).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if phase == .introducing {
                Button("Pular por enquanto") {
                    faceRecognition.setLockMode(.disabled)
                    onFinish()
                }
                .buttonStyle(.bordered)
            } else if phase == .capturing {
                Button(role: .cancel) {
                    faceRecognition.cancelEnrollment()
                    onFinish()
                } label: {
                    Text("Cancelar")
                }
                .buttonStyle(.bordered)
            }

            Spacer()

            primaryButton
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch phase {
        case .introducing:
            Button {
                faceRecognition.beginGuidedEnrollment()
                phase = .capturing
            } label: {
                Text("Começar cadastro")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .capturing:
            Button {
                phase = .choosing
            } label: {
                Text("Continuar")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!faceRecognition.isEnrollmentComplete)

        case .choosing:
            Button {
                finalizeChoice()
            } label: {
                Text("Salvar")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(choice == nil)
            .keyboardShortcut(.defaultAction)

        case .done:
            Button {
                onFinish()
            } label: {
                Text("Concluir")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Finalization

    private func finalizeChoice() {
        guard let choice else { return }
        let embeddings = faceRecognition.capturedEnrollmentEmbeddings()

        do {
            switch choice {
            case .onlyMe:
                try faceRecognition.enroll(embeddings: embeddings, activateMode: true)
            case .anyone:
                faceRecognition.setLockMode(.anyFace)
            }
            phase = .done
        } catch {
            print("[SixthSense] Falha ao salvar enrollment: \(error)")
            onFinish()
        }
    }
}

// MARK: - Enrollment Ring

/// The circular ring of target segments drawn around the camera preview.
/// Each segment is an arc that represents one EnrollmentTarget. Completed
/// targets fill solid green. The "current" target pulses in the accent color.
private struct EnrollmentRing: View {
    let targets: [EnrollmentTarget]
    let completed: Set<Int>
    let currentIndex: Int

    @State private var pulse: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background ring (always visible, faint)
                Circle()
                    .stroke(.white.opacity(0.1), lineWidth: 10)
                    .padding(10)

                // Target dots arranged in a circle
                ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                    let position = ringPosition(
                        for: index,
                        count: targets.count,
                        in: geo.size
                    )
                    let isDone = completed.contains(target.id)
                    let isCurrent = index == currentIndex && !isDone

                    Circle()
                        .fill(dotColor(isDone: isDone, isCurrent: isCurrent))
                        .frame(width: isCurrent ? 22 : 16, height: isCurrent ? 22 : 16)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(0.4), lineWidth: isCurrent ? 2 : 1)
                        )
                        .shadow(
                            color: dotColor(isDone: isDone, isCurrent: isCurrent).opacity(0.6),
                            radius: isCurrent ? 10 : 4
                        )
                        .scaleEffect(isCurrent && pulse ? 1.15 : 1.0)
                        .position(position)
                        .animation(
                            .easeInOut(duration: 0.35),
                            value: isDone
                        )
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    /// Places the target dot around the ring. Index 0 is the center
    /// (straight ahead), so it sits at the middle; the remaining targets
    /// distribute evenly around the circle starting from the top.
    private func ringPosition(for index: Int, count: Int, in size: CGSize) -> CGPoint {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        if index == 0 {
            return center
        }
        let orbitCount = max(1, count - 1)
        let orbitIndex = index - 1
        // Start at the top (angle = -π/2) and go clockwise.
        let angle = (Double(orbitIndex) / Double(orbitCount)) * 2 * .pi - .pi / 2
        let radius = min(size.width, size.height) / 2 - 16
        return CGPoint(
            x: center.x + CGFloat(cos(angle)) * radius,
            y: center.y + CGFloat(sin(angle)) * radius
        )
    }

    private func dotColor(isDone: Bool, isCurrent: Bool) -> Color {
        if isDone { return .green }
        if isCurrent { return .accentColor }
        return .white.opacity(0.35)
    }
}

// MARK: - Pose Cursor

/// Live indicator of the user's current face angle, placed inside the
/// ring at a normalized position derived from yaw/pitch.
private struct PoseCursor: View {
    let pose: FaceAngle

    var body: some View {
        GeometryReader { geo in
            let normalized = pose.normalizedPosition()
            let x = CGFloat(normalized.x) * geo.size.width
            let y = CGFloat(normalized.y) * geo.size.height

            ZStack {
                Circle()
                    .fill(.cyan.opacity(0.3))
                    .frame(width: 26, height: 26)
                    .blur(radius: 4)
                Circle()
                    .fill(.cyan)
                    .frame(width: 12, height: 12)
                    .shadow(color: .cyan, radius: 6)
            }
            .position(x: x, y: y)
            .animation(.easeOut(duration: 0.12), value: pose)
        }
    }
}

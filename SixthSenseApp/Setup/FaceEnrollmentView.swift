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
    @State private var lastSeenPose: FaceAngle?
    @State private var faceLostSince: Date?

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

                // Segmented ring of targets — sits on the same 300pt
                // square as the pose cursor so `normalizedPosition` maps
                // the same angles to the same pixels.
                EnrollmentRing(
                    targets: faceRecognition.enrollmentTargets,
                    completed: faceRecognition.enrollmentCompletedIds,
                    currentIndex: faceRecognition.enrollmentCurrentTargetIndex
                )
                .frame(width: 300, height: 300)

                // Live pose cursor: shown at full opacity when Vision is
                // currently seeing the face, and faded at the LAST known
                // position when the face was briefly lost — this keeps
                // the user oriented instead of making the cursor vanish.
                if let pose = effectiveCursorPose {
                    PoseCursor(pose: pose, opacity: isFaceVisible ? 1.0 : 0.35)
                        .frame(width: 300, height: 300)
                }

                // Center "face lost" banner when Vision has been blind
                // for more than half a second.
                if showFaceLostBanner {
                    faceLostBanner
                }
            }
            .onChange(of: faceRecognition.enrollmentCurrentPose) { _, newPose in
                if let newPose {
                    lastSeenPose = newPose
                    faceLostSince = nil
                } else if faceLostSince == nil {
                    faceLostSince = Date()
                }
            }

            instructionCard

            qualityIndicator
        }
    }

    /// Pose used to render the cursor — prefers the live value, but
    /// falls back to the last seen value so the cursor fades instead
    /// of snapping to nothing.
    private var effectiveCursorPose: FaceAngle? {
        faceRecognition.enrollmentCurrentPose ?? lastSeenPose
    }

    /// Whether Vision is currently producing a pose reading.
    private var isFaceVisible: Bool {
        faceRecognition.enrollmentCurrentPose != nil
    }

    /// The banner shows after ~500ms without a pose, so brief glitches
    /// don't flash a warning.
    private var showFaceLostBanner: Bool {
        guard let lost = faceLostSince else { return false }
        return Date().timeIntervalSince(lost) >= 0.5
    }

    private var faceLostBanner: some View {
        VStack(spacing: 6) {
            Image(systemName: "eye.trianglebadge.exclamationmark")
                .font(.title2)
                .foregroundStyle(.orange)
            Text("Não consigo ver seu rosto")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
            Text("Volte devagar para o centro")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.75))
        }
        .padding(12)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(.orange.opacity(0.5), lineWidth: 1)
        )
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

/// Draws the guided-enrollment targets as dots positioned by the same
/// `normalizedPosition(maxDegrees:)` math that drives the pose cursor —
/// this guarantees the cursor and the targets share one coordinate system,
/// so "cursor on top of the target" really means "your face is at that
/// angle". Completed targets flip to a green checkmark badge so they're
/// visually distinct from the live pose cursor underneath.
private struct EnrollmentRing: View {
    let targets: [EnrollmentTarget]
    let completed: Set<Int>
    let currentIndex: Int

    /// Max degrees represented by the full radius of the ring. Must match
    /// the value used by PoseCursor so both sit in the same coordinate
    /// space. 14° gives a small margin around the default ±12° targets.
    private let maxDegrees: Double = 14.0

    @State private var pulse: Bool = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Faint background ring so the empty area is still visible.
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 2)
                    .padding(6)

                ForEach(Array(targets.enumerated()), id: \.element.id) { index, target in
                    let position = normalizedPoint(for: target.angle, in: geo.size)
                    let isDone = completed.contains(target.id)
                    let isCurrent = index == currentIndex && !isDone

                    targetDot(isDone: isDone, isCurrent: isCurrent)
                        .position(position)
                        .animation(.easeInOut(duration: 0.35), value: isDone)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }

    @ViewBuilder
    private func targetDot(isDone: Bool, isCurrent: Bool) -> some View {
        if isDone {
            // Done: green checkmark badge so it can't be confused with
            // the live pose cursor (which is a white crosshair).
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.green)
                .background(
                    Circle()
                        .fill(.black.opacity(0.5))
                        .frame(width: 26, height: 26)
                )
                .shadow(color: .green.opacity(0.6), radius: 6)
        } else if isCurrent {
            // Current: pulsing accent dot with a clear white outline.
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(width: 34, height: 34)
                    .blur(radius: 6)
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 22, height: 22)
                Circle()
                    .stroke(.white, lineWidth: 2)
                    .frame(width: 22, height: 22)
            }
            .scaleEffect(pulse ? 1.15 : 1.0)
            .shadow(color: .accentColor.opacity(0.7), radius: 8)
        } else {
            // Pending: a hollow ring, deliberately subtle.
            Circle()
                .stroke(.white.opacity(0.45), lineWidth: 2)
                .background(Circle().fill(.black.opacity(0.35)))
                .frame(width: 14, height: 14)
        }
    }

    /// Converts a target angle to a pixel coordinate using the same math
    /// as the pose cursor (`normalizedPosition`), so the two always line
    /// up regardless of how the ring is sized.
    private func normalizedPoint(for angle: FaceAngle, in size: CGSize) -> CGPoint {
        let normalized = angle.normalizedPosition(maxDegrees: maxDegrees)
        return CGPoint(
            x: CGFloat(normalized.x) * size.width,
            y: CGFloat(normalized.y) * size.height
        )
    }
}

// MARK: - Pose Cursor

/// Live indicator of the user's current face angle, placed inside the
/// ring at a normalized position derived from yaw/pitch. Rendered as a
/// white reticle (outer ring + inner cross) so it reads as "your cursor"
/// and never blends in with the green check badges of completed targets.
/// `opacity` is used to fade the cursor when the face is briefly lost
/// instead of removing it entirely — the user still sees where it WAS,
/// which helps them recover the pose.
private struct PoseCursor: View {
    let pose: FaceAngle
    var opacity: Double = 1.0

    /// Must match `EnrollmentRing.maxDegrees` so the cursor and the
    /// targets share the same coordinate system.
    private let maxDegrees: Double = 14.0

    var body: some View {
        GeometryReader { geo in
            let normalized = pose.normalizedPosition(maxDegrees: maxDegrees)
            let x = CGFloat(normalized.x) * geo.size.width
            let y = CGFloat(normalized.y) * geo.size.height

            ZStack {
                // Soft halo for visibility over any camera background.
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 46, height: 46)
                    .blur(radius: 8)

                // Outer reticle ring.
                Circle()
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.5), radius: 3)

                // Inner cross — purely decorative but makes the cursor
                // look like a viewfinder, not "another target dot".
                Path { path in
                    path.move(to: CGPoint(x: -6, y: 0))
                    path.addLine(to: CGPoint(x: 6, y: 0))
                    path.move(to: CGPoint(x: 0, y: -6))
                    path.addLine(to: CGPoint(x: 0, y: 6))
                }
                .offset(x: 16, y: 16)
                .stroke(.white, lineWidth: 2)
                .frame(width: 32, height: 32)
            }
            .opacity(opacity)
            .position(x: x, y: y)
            .animation(.easeOut(duration: 0.12), value: pose)
            .animation(.easeInOut(duration: 0.2), value: opacity)
        }
    }
}

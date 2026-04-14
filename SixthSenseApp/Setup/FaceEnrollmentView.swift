import SwiftUI
import AVFoundation
import SharedServices
import SixthSenseCore

// MARK: - Face Enrollment View

/// Modal view that captures the user's face and lets them pick whether
/// only they should be allowed to drive gestures, or any face counts.
/// All the heavy lifting (camera subscription, Vision feature prints,
/// progress tracking) lives in FaceRecognitionManager — this view is a
/// thin front-end that observes `enrollmentProgress` / `enrollmentFaceBox`
/// and calls `beginEnrollment` / `enroll`.
struct FaceEnrollmentView: View {
    let faceRecognition: FaceRecognitionManager
    let cameraSession: () -> AVCaptureSession?
    let onFinish: () -> Void

    @State private var phase: Phase = .introducing
    @State private var choice: Choice? = nil

    private let targetCaptures = 10

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

        var mode: FaceLockMode {
            switch self {
            case .onlyMe: return .enrolledFace
            case .anyone: return .anyFace
            }
        }
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
        .onAppear {
            // Capturing phase is driven by the manager; we watch its
            // progress via observation in the view body.
        }
        .onChange(of: faceRecognition.enrollmentProgress) { _, newValue in
            if phase == .capturing && newValue >= targetCaptures {
                // Finished — move the user to the choice phase.
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
        case .capturing:   return "Cadastrando rosto..."
        case .choosing:    return "Quem pode usar os gestos?"
        case .done:        return "Tudo pronto"
        }
    }

    private var subtitle: String {
        switch phase {
        case .introducing:
            return "Você pode configurar o SixthSense para funcionar apenas quando uma pessoa específica estiver olhando para a tela."
        case .capturing:
            return "Olhe para a câmera. Vamos capturar \(targetCaptures) frames para que o rosto seja reconhecido depois."
        case .choosing:
            return "Rosto capturado com sucesso. Escolha quem vai poder controlar o Mac com gestos."
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
            Text("O SixthSense pode:")
                .font(.callout.weight(.semibold))

            bullet(
                icon: "eye.fill",
                title: "Funcionar só quando você estiver olhando para a tela",
                description: "Os gestos pausam automaticamente se você desvia o olhar — evita cliques acidentais."
            )

            bullet(
                icon: "person.crop.circle.badge.checkmark",
                title: "Reconhecer apenas você como usuário",
                description: "O rosto é guardado localmente, nunca sai do seu Mac, e só você consegue disparar gestos."
            )

            bullet(
                icon: "hand.raised.slash",
                title: "Ou você pode pular e deixar qualquer pessoa usar",
                description: "Clique em 'Pular' se não quiser reconhecimento facial agora. Dá para ativar depois em Configurações."
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
        VStack(spacing: 14) {
            ZStack {
                CameraPreviewView(session: cameraSession())
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(.white.opacity(0.2), lineWidth: 1)
                    )

                if let box = faceRecognition.enrollmentFaceBox {
                    FaceBoxOverlay(box: box)
                }

                if faceRecognition.enrollmentFaceBox == nil {
                    Text("Procurando rosto...")
                        .font(.callout)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.6), in: Capsule())
                        .foregroundStyle(.white)
                }
            }

            ProgressView(
                value: Double(faceRecognition.enrollmentProgress),
                total: Double(targetCaptures)
            )
            .progressViewStyle(.linear)
            .tint(Color.accentColor)

            Text("\(faceRecognition.enrollmentProgress) de \(targetCaptures) frames capturados")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        .frame(maxWidth: .infinity, minHeight: 200)
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
                faceRecognition.beginEnrollment(target: targetCaptures)
                phase = .capturing
            } label: {
                Text("Começar cadastro")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

        case .capturing:
            // Primary action is disabled until the manager finishes; the
            // onChange handler above advances phase automatically.
            Button {
                phase = .choosing
            } label: {
                Text("Continuar")
                    .frame(minWidth: 150)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(faceRecognition.enrollmentProgress < targetCaptures)

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
                // Não guardamos os embeddings quando o usuário escolhe
                // "qualquer pessoa" — o modo anyFace só precisa de
                // detecção facial + olhar para a tela.
                faceRecognition.setLockMode(.anyFace)
            }
            phase = .done
        } catch {
            print("[SixthSense] Falha ao salvar enrollment: \(error)")
            onFinish()
        }
    }
}

// MARK: - Face box overlay

/// Draws a rounded outline around the detected face's bounding box.
/// Uses the same Vision coords mirroring convention as HandSkeletonCanvas
/// (image already flipped by .upMirrored, so X goes straight).
struct FaceBoxOverlay: View {
    let box: CGRect

    var body: some View {
        GeometryReader { geo in
            let rect = screenRect(for: box, in: geo.size)
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 3
                )
                .frame(width: rect.width, height: rect.height)
                .position(x: rect.midX, y: rect.midY)
                .shadow(color: .cyan.opacity(0.5), radius: 8)
        }
    }

    private func screenRect(for normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.origin.x * size.width,
            y: (1 - normalized.origin.y - normalized.height) * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}

import SwiftUI
import AVFoundation
import AppKit
import SharedServices

// MARK: - Setup View

/// Janela de onboarding mostrada na primeira execução (ou sempre que
/// alguma permissão crítica estiver pendente). Consulta ao vivo o estado
/// de Câmera e Acessibilidade, oferece botões para conceder cada uma e
/// fecha automaticamente quando ambas estão OK. A janela é apresentada
/// pelo AppDelegate via NSWindow para funcionar mesmo antes do primeiro
/// clique no ícone do menu bar.
struct SetupView: View {
    /// Callback invocado quando o usuário clica "Começar" (com tudo OK)
    /// ou fecha a janela manualmente.
    let onFinish: () -> Void

    @State private var cameraGranted: Bool = false
    @State private var accessibilityGranted: Bool = false
    @State private var copiedPath: Bool = false
    @State private var requestingCamera: Bool = false

    private let refreshTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var allGranted: Bool { cameraGranted && accessibilityGranted }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.top, 32)
                .padding(.horizontal, 36)
                .padding(.bottom, 24)

            Divider()

            VStack(spacing: 16) {
                cameraCard
                accessibilityCard
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)

            Divider()

            footer
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
        }
        .frame(width: 580)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { refresh() }
        .onReceive(refreshTimer) { _ in refresh() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.raised.fingers.spread")
                .font(.system(size: 52))
                .foregroundStyle(.tint)

            Text("Bem-vindo ao SixthSense")
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("Vamos conceder as permissões necessárias. Você só precisa fazer isso uma vez.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Permission cards

    private var cameraCard: some View {
        permissionCard(
            icon: "camera.fill",
            title: "Câmera",
            description: "Usada para detectar suas mãos e rastrear os gestos.",
            granted: cameraGranted
        ) {
            cameraAction
        }
    }

    private var accessibilityCard: some View {
        permissionCard(
            icon: "figure.wave.circle.fill",
            title: "Acessibilidade",
            description: "Usada para controlar o cursor e clicar no seu Mac.",
            granted: accessibilityGranted,
            extraInfo: accessibilityGranted ? nil : pathHint
        ) {
            accessibilityActions
        }
    }

    @ViewBuilder
    private var cameraAction: some View {
        if cameraGranted {
            Label("Concedida", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout.weight(.medium))
        } else {
            Button {
                Task { await requestCameraPermission() }
            } label: {
                if requestingCamera {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.horizontal, 8)
                } else {
                    Text("Conceder acesso")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(requestingCamera)
        }
    }

    @ViewBuilder
    private var accessibilityActions: some View {
        if accessibilityGranted {
            Label("Concedida", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .font(.callout.weight(.medium))
        } else {
            HStack(spacing: 8) {
                Button {
                    AccessibilityDiagnostics.copyPreferredPathToPasteboard()
                    copiedPath = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                        copiedPath = false
                    }
                } label: {
                    Label(
                        copiedPath
                            ? "Copiado!"
                            : (AccessibilityDiagnostics.bundlePath != nil
                                ? "Copiar caminho do .app"
                                : "Copiar caminho"),
                        systemImage: "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button {
                    AccessibilityDiagnostics.openAccessibilitySettings()
                } label: {
                    Text("Abrir Ajustes")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
    }

    private var pathHint: some View {
        VStack(alignment: .leading, spacing: 4) {
            if AccessibilityDiagnostics.bundlePath != nil {
                Text("Em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade, clique em \"+\" e adicione o SixthSense.app pelo Finder:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Adicione o executável deste binário em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade:")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(AccessibilityDiagnostics.preferredInstallablePath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Permission card builder

    private func permissionCard<Action: View>(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        extraInfo: (some View)? = Optional<EmptyView>.none,
        @ViewBuilder action: () -> Action
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(granted ? Color.green.opacity(0.15) : Color.blue.opacity(0.15))
                    .frame(width: 52, height: 52)
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(granted ? .green : .blue)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                    Spacer()
                    action()
                }
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let extra = extraInfo {
                    extra
                        .padding(.top, 4)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.background.secondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(granted ? Color.green.opacity(0.4) : .clear, lineWidth: 1.5)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if allGranted {
                Label("Tudo pronto!", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.callout.weight(.medium))
            } else {
                Label("Aguardando permissões...", systemImage: "clock")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Spacer()

            Button {
                onFinish()
            } label: {
                Text(allGranted ? "Começar a usar" : "Fechar")
                    .frame(minWidth: 120)
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(allGranted ? .green : .blue)
        }
    }

    // MARK: - Actions

    private func refresh() {
        cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        accessibilityGranted = AccessibilityDiagnostics.isTrusted

        // Auto-dismiss as soon as everything is granted — we don't block
        // the user on "Começar a usar", we just let them in immediately.
        if allGranted {
            // Give them a beat to see the green state, then close.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                if cameraGranted && accessibilityGranted {
                    onFinish()
                }
            }
        }
    }

    private func requestCameraPermission() async {
        requestingCamera = true
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        cameraGranted = granted
        requestingCamera = false
    }
}

import SwiftUI
import SixthSenseCore
import SharedServices
import GhostDropModule

/// Mostra o preview do conteúdo atual da área de transferência, os
/// dispositivos próximos e o histórico das últimas transferências.
struct GhostDropTrainingView: View {
    let module: GhostDropModule

    /// Força um refresh do preview periodicamente.
    @State private var ticker = 0

    private let refreshTimer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            clipboardCard
            peersCard
            historyCard
            Spacer(minLength: 0)
        }
        .padding(20)
        .onReceive(refreshTimer) { _ in
            module.refreshClipboardPreview()
            ticker &+= 1
        }
        .onAppear {
            module.refreshClipboardPreview()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.draw")
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("GhostDrop — Clipboard entre Dispositivos")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Faça um gesto de arremesso para enviar o que está copiado.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    private var clipboardCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Área de transferência atual", systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                Button {
                    module.refreshClipboardPreview()
                    ticker &+= 1
                } label: {
                    Label("Atualizar", systemImage: "arrow.clockwise")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
            }

            if let preview = module.clipboardPreview, !preview.isEmpty {
                Text(preview)
                    .font(.callout.monospaced())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    .id(ticker)
            } else {
                Text("Área de transferência vazia ou conteúdo não textual.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var peersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Destinos próximos")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            if module.discoveredPeers.isEmpty {
                Label("Nenhum dispositivo na rede local.", systemImage: "wifi.slash")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(module.discoveredPeers) { peer in
                    HStack {
                        Image(systemName: "laptopcomputer.and.iphone")
                            .foregroundStyle(.cyan)
                        Text(peer.name)
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Histórico recente")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            if module.recentTransfers.isEmpty {
                Text("Nenhuma transferência ainda.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ForEach(module.recentTransfers) { transfer in
                    HStack(spacing: 10) {
                        Image(systemName: transfer.direction.systemImage)
                            .foregroundStyle(transfer.direction == .sent ? .orange : .green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(transfer.direction.label) — \(transfer.peerName)")
                                .font(.caption)
                                .foregroundStyle(.white)
                            Text(transfer.preview)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }
}

import SwiftUI
import SixthSenseCore
import SharedServices
import PortalViewModule

/// Mostra o estado do PortalView: se está advertising, qual nome está sendo
/// anunciado, lista de peers e a resolução alvo.
struct PortalViewTrainingView: View {
    let module: PortalViewModule

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            statusRow
            configCard
            peersCard
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("PortalView — Display Virtual")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Transmite uma tela virtual para um dispositivo próximo via WebRTC.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    private var statusRow: some View {
        HStack(spacing: 12) {
            statusCard(
                title: "Status",
                value: module.isAdvertising ? "Anunciando" : "Parado",
                icon: module.isAdvertising ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash",
                color: module.isAdvertising ? .green : .red
            )
            statusCard(
                title: "Resolução",
                value: "\(Int(module.resolution.width)) × \(Int(module.resolution.height))",
                icon: "display",
                color: .cyan
            )
            statusCard(
                title: "FPS Alvo",
                value: "\(module.targetFPS)",
                icon: "speedometer",
                color: .orange
            )
        }
    }

    private func statusCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
    }

    private var configCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nome anunciado na rede")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Text(module.advertisedName ?? "—")
                .font(.callout.monospaced())
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private var peersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dispositivos conectados")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            if module.discoveredPeers.isEmpty {
                Label("Nenhum dispositivo companheiro descoberto.", systemImage: "wifi.slash")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(module.discoveredPeers) { peer in
                    HStack {
                        Image(systemName: "ipad.landscape")
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
}

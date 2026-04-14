import SwiftUI
import SixthSenseCore
import SharedServices
import AirCursorModule

/// Mostra ao vivo os dados chegando do iPhone (dx, dy, tap), o total de
/// cliques recebidos e a lista de dispositivos descobertos na rede local.
struct AirCursorTrainingView: View {
    let module: AirCursorModule

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            readingCard
            statsRow
            peersCard
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "iphone.radiowaves.left.and.right")
                .font(.title2)
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("AirCursor — iPhone como Remoto")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Pareie seu iPhone para controlar o cursor pelo giroscópio.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
    }

    private var readingCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Última leitura do giroscópio")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            if let reading = module.latestReading {
                HStack(spacing: 24) {
                    axisReading(label: "Δx", value: reading.dx, color: .cyan)
                    axisReading(label: "Δy", value: reading.dy, color: .pink)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tap")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.5))
                        Image(systemName: reading.tap ? "hand.tap.fill" : "hand.tap")
                            .font(.title2)
                            .foregroundStyle(reading.tap ? .green : .white.opacity(0.3))
                    }
                }
            } else {
                Text("Aguardando dados do iPhone...")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func axisReading(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
            Text(String(format: "%+.2f", value))
                .font(.title3.monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(minWidth: 80, alignment: .leading)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(
                icon: "cursorarrow.click",
                title: "Taps recebidos",
                value: "\(module.tapCount)",
                color: .green
            )
            statCard(
                icon: "dial.max",
                title: "Sensibilidade",
                value: String(format: "%.1fx", module.gyroSensitivity),
                color: .orange
            )
            statCard(
                icon: module.isConnected ? "wifi" : "wifi.slash",
                title: "Conexão",
                value: module.isConnected ? "Pareado" : "Não pareado",
                color: module.isConnected ? .green : .red
            )
        }
    }

    private func statCard(icon: String, title: String, value: String, color: Color) -> some View {
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

    private var peersCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Dispositivos na rede local")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            if module.discoveredPeers.isEmpty {
                Label("Nenhum iPhone encontrado.", systemImage: "wifi.slash")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(module.discoveredPeers) { peer in
                    HStack {
                        Image(systemName: "iphone")
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

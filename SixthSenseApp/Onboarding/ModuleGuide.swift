import Foundation

// MARK: - Module Guide Data

/// Tutorial data for HandCommand — the only feature module.
/// Shape is kept intentionally open so future modules can reuse it.
struct ModuleGuide: Identifiable {
    let id: String
    let name: String
    let icon: String
    let tagline: String
    let overview: String
    let requirements: [GuideRequirement]
    let steps: [GuideStep]
    let gestures: [GestureInfo]
    let tips: [String]
}

struct GuideRequirement: Identifiable {
    let id = UUID()
    let icon: String
    let name: String
    let description: String
}

struct GuideStep: Identifiable {
    let id: Int
    let title: String
    let description: String
    let icon: String
}

struct GestureInfo: Identifiable {
    let id = UUID()
    let name: String
    let icon: String
    let action: String
    let howTo: String
}

// MARK: - HandCommand guide

extension ModuleGuide {

    static let handCommand = ModuleGuide(
        id: "hand-command",
        name: "HandCommand",
        icon: "hand.raised.fingers.spread",
        tagline: "Controle o Mac com gestos",
        overview: """
        O HandCommand usa a câmera frontal do seu Mac para rastrear as duas \
        mãos em tempo real. A mão direita controla o cursor pelo dedo \
        indicador, e a mão esquerda dispara ações como clicar e arrastar. \
        Toda a detecção roda localmente no seu Mac — nenhum dado sai do \
        dispositivo.
        """,
        requirements: [
            GuideRequirement(
                icon: "camera.fill",
                name: "Câmera",
                description: "Usada para detectar as posições das suas mãos em 21 pontos cada."
            ),
            GuideRequirement(
                icon: "figure.wave.circle.fill",
                name: "Acessibilidade",
                description: "Permite ao SixthSense controlar o cursor e clicar por você via CGEvent."
            ),
            GuideRequirement(
                icon: "light.max",
                name: "Iluminação razoável",
                description: "Você não precisa de estúdio — só evite contraluz forte atrás das mãos."
            ),
        ],
        steps: [
            GuideStep(
                id: 1,
                title: "Conceda as permissões",
                description: "Na primeira execução, a janela \"Configuração Inicial\" abre automaticamente pedindo câmera e acessibilidade. Conceda as duas uma única vez.",
                icon: "checkmark.shield.fill"
            ),
            GuideStep(
                id: 2,
                title: "Ative o controle",
                description: "Clique no ícone 🖐️ na menu bar e toque no botão grande \"Ativar controle\". O app começa a rastrear suas mãos imediatamente.",
                icon: "power.circle.fill"
            ),
            GuideStep(
                id: 3,
                title: "Posicione-se confortavelmente",
                description: "Fique a 30-60 cm da câmera, com as mãos visíveis mais ou menos na altura do peito. Não precisa esticar — a zona útil do frame é ajustada para movimentos naturais.",
                icon: "figure.arms.open"
            ),
            GuideStep(
                id: 4,
                title: "Aprenda os 3 gestos",
                description: "No Modo Treinamento você vê os pontos detectados em tempo real sobre a câmera. Pratique cada gesto observando a legenda acesa no canto.",
                icon: "hand.raised.fingers.spread"
            ),
            GuideStep(
                id: 5,
                title: "Use!",
                description: "Você já pode soltar o mouse físico. Os gestos são suavizados automaticamente (One Euro Filter) para o cursor não tremer com a mão parada.",
                icon: "hands.sparkles.fill"
            ),
        ],
        gestures: [
            GestureInfo(
                name: "Mover cursor",
                icon: "hand.point.up.left",
                action: "Mão direita",
                howTo: "Estenda o dedo indicador na direção da tela. O cursor segue a ponta do indicador em tempo real."
            ),
            GestureInfo(
                name: "Clicar",
                icon: "hand.pinch",
                action: "Mão esquerda",
                howTo: "Junte a ponta do polegar com a ponta do indicador da mão esquerda. Um clique dispara exatamente onde o cursor estiver."
            ),
            GestureInfo(
                name: "Arrastar",
                icon: "hand.raised.fill",
                action: "Mão esquerda",
                howTo: "Feche o punho da mão esquerda para segurar. Enquanto o punho estiver fechado, a direita arrasta o que estiver sob o cursor. Abra a mão para soltar."
            ),
            GestureInfo(
                name: "Rolar",
                icon: "arrow.triangle.2.circlepath",
                action: "Mão esquerda",
                howTo: "Trace um círculo no ar com o dedo indicador esquerdo, como se girasse uma roda de scroll invisível. Sentido anti-horário rola para cima; sentido horário rola para baixo. A velocidade do giro controla a velocidade da rolagem — quanto mais rápido você girar, mais rápido a página passa."
            ),
            GestureInfo(
                name: "Mission Control",
                icon: "rectangle.on.rectangle",
                action: "Mão direita",
                howTo: "Feche o punho direito e segure por cerca de meio segundo. O macOS abre o Mission Control (equivalente a Ctrl+↑ ou F3) mostrando todas as janelas e Spaces. Abra a mão direita e feche de novo para disparar outra vez — o hold evita disparos acidentais quando a mão passa perto do punho por um frame."
            ),
            GestureInfo(
                name: "Trocar app (⌘+Tab)",
                icon: "square.on.square",
                action: "Mão esquerda",
                howTo: "Faça o gesto shaka (hang loose) com a mão esquerda: polegar e mindinho abertos, índice/médio/anelar dobrados. Cada vez que você entra na pose, o macOS cicla para o próximo app. Saia da pose e volte para cicar de novo — como se estivesse batendo Tab com o Cmd segurado."
            ),
        ],
        tips: [
            "Mantenha as mãos entre 30 e 60 cm da câmera para detecção estável.",
            "Use iluminação frontal ou ambiente — evite janelas claras atrás de você.",
            "Se o cursor parece lento, aumente a sensibilidade em Configurações → HandCommand.",
            "A classificação é escala-invariante — o gesto é reconhecido perto e longe da câmera.",
            "No Modo Treinamento, o log de detecção mostra exatamente o que o classificador está vendo a cada frame.",
            "Se um gesto falhar, verifique se sua mão está toda dentro do frame da câmera.",
        ]
    )

    static let allGuides: [ModuleGuide] = [handCommand]
}

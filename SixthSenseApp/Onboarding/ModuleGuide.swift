import Foundation

// MARK: - Module Guide Data

/// Contains all tutorial/training data for each SixthSense module.
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

// MARK: - All Guides

extension ModuleGuide {

    static let allGuides: [ModuleGuide] = [
        handCommand,
        gazeShift,
        airCursor,
        portalView,
        ghostDrop,
        notchBar
    ]

    // MARK: - HandCommand

    static let handCommand = ModuleGuide(
        id: "hand-command",
        name: "HandCommand",
        icon: "hand.raised",
        tagline: "Minority Report Desktop",
        overview: "Controle as janelas do seu Mac usando gestos de mão capturados pela sua webcam. Mova, redimensione e gerencie janelas apenas movendo suas mãos na frente da câmera.",
        requirements: [
            GuideRequirement(icon: "camera", name: "Câmera", description: "Webcam integrada ou externa"),
            GuideRequirement(icon: "accessibility", name: "Acessibilidade", description: "Necessária para mover e redimensionar janelas"),
            GuideRequirement(icon: "light.max", name: "Boa Iluminação", description: "Ambiente bem iluminado para detecção precisa das mãos"),
        ],
        steps: [
            GuideStep(id: 1, title: "Conceder Permissões", description: "Ative Câmera e Acessibilidade em Ajustes do Sistema > Privacidade e Segurança.", icon: "lock.open"),
            GuideStep(id: 2, title: "Posicione-se", description: "Sente-se a cerca de 50-80cm da webcam. Certifique-se de que suas mãos estejam visíveis no enquadramento da câmera.", icon: "person.and.background.dotted"),
            GuideStep(id: 3, title: "Ative o Módulo", description: "Ative o HandCommand no menu bar. Um esqueleto da mão aparecerá na tela.", icon: "power"),
            GuideStep(id: 4, title: "Experimente Gestos Básicos", description: "Comece apontando (dedo indicador levantado) para mover o cursor. Depois tente a pinça para agarrar uma janela.", icon: "hand.point.up.left"),
            GuideStep(id: 5, title: "Pratique o Controle de Janelas", description: "Faça a pinça para agarrar, mova sua mão para reposicionar, abra os dedos para redimensionar. Abra a mão para soltar.", icon: "macwindow.on.rectangle"),
        ],
        gestures: [
            GestureInfo(name: "Apontar", icon: "hand.point.up", action: "Mover Cursor", howTo: "Estenda o dedo indicador. O cursor acompanha a posição da ponta do seu dedo."),
            GestureInfo(name: "Pinça", icon: "hand.pinch", action: "Agarrar Janela", howTo: "Encoste o polegar e o indicador sobre uma janela para agarrá-la."),
            GestureInfo(name: "Mover", icon: "hand.draw", action: "Arrastar Janela", howTo: "Enquanto faz a pinça, mova sua mão para arrastar a janela agarrada."),
            GestureInfo(name: "Abrir Dedos", icon: "hand.raised.fingers.spread", action: "Redimensionar Janela", howTo: "Com uma janela agarrada, abra todos os dedos para aumentá-la."),
            GestureInfo(name: "Punho", icon: "hand.raised.slash", action: "Soltar", howTo: "Feche a mão em um punho para soltar a janela."),
            GestureInfo(name: "Deslizar", icon: "hand.wave", action: "Trocar Área de Trabalho", howTo: "Deslize a mão aberta para a esquerda ou direita rapidamente para trocar de área de trabalho."),
        ],
        tips: [
            "Mantenha sua mão entre 30-60cm da câmera para melhor rastreamento",
            "Evite usar luvas ou segurar objetos nas mãos",
            "Um fundo liso atrás das suas mãos melhora a precisão",
            "Comece com gestos lentos e deliberados até se sentir confortável",
            "Ajuste a sensibilidade nas Configurações se os gestos parecerem rápidos ou lentos demais",
        ]
    )

    // MARK: - GazeShift

    static let gazeShift = ModuleGuide(
        id: "gaze-shift",
        name: "GazeShift",
        icon: "eye",
        tagline: "Gaze-Aware Desktop",
        overview: "Seu Mac sabe para onde você está olhando. Janelas que você observa ficam focadas e mais brilhantes, enquanto as outras escurecem. Um HUD sutil acompanha o ponto do seu olhar.",
        requirements: [
            GuideRequirement(icon: "camera", name: "Câmera", description: "Webcam integrada (câmera FaceTime funciona melhor)"),
            GuideRequirement(icon: "accessibility", name: "Acessibilidade", description: "Necessária para focar e gerenciar janelas"),
            GuideRequirement(icon: "light.max", name: "Iluminação Consistente", description: "Iluminação uniforme no rosto, evite luz de fundo"),
        ],
        steps: [
            GuideStep(id: 1, title: "Conceder Permissões", description: "Ative Câmera e Acessibilidade nos Ajustes do Sistema.", icon: "lock.open"),
            GuideStep(id: 2, title: "Posicione-se", description: "Sente-se diretamente de frente para a webcam, a cerca de 50-70cm de distância. Mantenha a cabeça relativamente parada.", icon: "person.crop.circle"),
            GuideStep(id: 3, title: "Ative o GazeShift", description: "Ative o GazeShift. Uma tela de calibração aparecerá.", icon: "power"),
            GuideStep(id: 4, title: "Calibrar", description: "Olhe para cada ponto que aparece na tela por 2 segundos. Isso mapeia as posições dos seus olhos para coordenadas da tela. Mínimo de 5 pontos.", icon: "scope"),
            GuideStep(id: 5, title: "Comece a Usar", description: "Olhe para diferentes janelas. Após um breve tempo de permanência (~500ms), a janela que você está olhando ficará em foco e as outras escurecerão.", icon: "eye.trianglebadge.exclamationmark"),
        ],
        gestures: [
            GestureInfo(name: "Olhar para Janela", icon: "eye", action: "Focar Janela", howTo: "Olhe para uma janela por cerca de meio segundo. Ela virá para a frente e ficará mais brilhante."),
            GestureInfo(name: "Desviar o Olhar", icon: "eye.slash", action: "Escurecer Janela", howTo: "Quando você desvia o olhar de uma janela, ela escurece gradualmente para indicar que não está em foco."),
            GestureInfo(name: "HUD do Olhar", icon: "circle.dotted", action: "Feedback Visual", howTo: "Um círculo sutil acompanha o ponto estimado do seu olhar na tela."),
        ],
        tips: [
            "Recalibre se você mudar significativamente a posição sentada",
            "Funciona melhor com a câmera integrada do MacBook (mais próxima da tela)",
            "A detecção do olhar funciona por região da tela, não com precisão de pixel — ela detecta para qual área você está olhando",
            "Evite fontes de luz forte atrás de você (luz de fundo confunde a detecção facial)",
            "Ajuste a intensidade do escurecimento nas Configurações conforme sua preferência",
        ]
    )

    // MARK: - AirCursor

    static let airCursor = ModuleGuide(
        id: "air-cursor",
        name: "AirCursor",
        icon: "iphone.radiowaves.left.and.right",
        tagline: "Telekinesis KVM",
        overview: "Transforme seu iPhone em um Wii Remote! Aponte seu celular para o Mac e o cursor acompanha. Incline para clicar, gire para rolar. Como mágica.",
        requirements: [
            GuideRequirement(icon: "iphone", name: "iPhone", description: "iPhone com o app companheiro SixthSense instalado"),
            GuideRequirement(icon: "wifi", name: "Mesma Rede", description: "Ambos os dispositivos no mesmo Wi-Fi"),
            GuideRequirement(icon: "network", name: "Rede Local", description: "Permita acesso à rede local quando solicitado"),
        ],
        steps: [
            GuideStep(id: 1, title: "Instalar o App Companheiro", description: "Instale o app companheiro SixthSense no seu iPhone (compile a partir da pasta SixthSenseCompanion no Xcode).", icon: "arrow.down.app"),
            GuideStep(id: 2, title: "Mesmo Wi-Fi", description: "Certifique-se de que seu Mac e iPhone estão conectados ao mesmo Wi-Fi.", icon: "wifi"),
            GuideStep(id: 3, title: "Ative o AirCursor", description: "Ative o AirCursor no seu Mac. Ele começará a anunciar via Bonjour.", icon: "power"),
            GuideStep(id: 4, title: "Conectar pelo iPhone", description: "Abra o app companheiro > aba AirCursor. Seu Mac deve aparecer na lista. Toque para conectar.", icon: "link"),
            GuideStep(id: 5, title: "Calibrar", description: "Segure seu iPhone apontando para o centro da tela do Mac. Pressione 'Calibrar' no app companheiro.", icon: "scope"),
            GuideStep(id: 6, title: "Comece a Controlar", description: "Aponte seu celular para mover o cursor. Incline para frente para clicar, gire para rolar!", icon: "hand.point.right"),
        ],
        gestures: [
            GestureInfo(name: "Apontar", icon: "iphone.gen3", action: "Mover Cursor", howTo: "Aponte seu iPhone para a tela. O cursor se move para onde você aponta (inclinação = vertical, rotação = horizontal)."),
            GestureInfo(name: "Inclinar para Baixo", icon: "iphone.gen3.radiowaves.left.and.right.circle", action: "Clique Esquerdo", howTo: "Incline rapidamente o celular para frente (em direção à tela) para realizar um clique esquerdo."),
            GestureInfo(name: "Girar", icon: "arrow.triangle.2.circlepath", action: "Clique Direito", howTo: "Gire o pulso no sentido horário rapidamente para acionar um clique direito."),
            GestureInfo(name: "Inclinar e Segurar", icon: "arrow.up.and.down", action: "Rolar", howTo: "Incline o celular suavemente para cima ou para baixo e segure para rolar continuamente."),
        ],
        tips: [
            "Segure o celular confortavelmente — você não precisa apontar com precisão",
            "Ajuste a sensibilidade do giroscópio nas Configurações se o cursor se mover rápido/lento demais",
            "A conexão usa UDP para latência mínima (~5ms)",
            "Se o cursor desviar, recalibre apontando para o centro da tela",
            "Ótimo para apresentações — controle seu Mac do outro lado da sala!",
        ]
    )

    // MARK: - PortalView

    static let portalView = ModuleGuide(
        id: "portal-view",
        name: "PortalView",
        icon: "rectangle.on.rectangle",
        tagline: "Portal Display",
        overview: "Transforme QUALQUER dispositivo com navegador em uma tela extra para o seu Mac. Escaneie um QR code e seu celular, tablet ou outro computador se torna um monitor sem fio. Com o modo AR, a janela do Mac flutua no espaço físico!",
        requirements: [
            GuideRequirement(icon: "rectangle.badge.checkmark", name: "Gravação de Tela", description: "Necessária para capturar o conteúdo da tela"),
            GuideRequirement(icon: "wifi", name: "Mesma Rede", description: "Todos os dispositivos na mesma rede local"),
            GuideRequirement(icon: "qrcode", name: "Câmera no Dispositivo", description: "O dispositivo receptor precisa de câmera para escanear o QR code"),
        ],
        steps: [
            GuideStep(id: 1, title: "Conceder Gravação de Tela", description: "Ative a permissão de Gravação de Tela em Ajustes do Sistema > Privacidade e Segurança.", icon: "lock.open"),
            GuideStep(id: 2, title: "Ative o PortalView", description: "Ative o PortalView. Uma tela virtual será criada e um QR code aparecerá.", icon: "power"),
            GuideStep(id: 3, title: "Escanear QR Code", description: "Em qualquer outro dispositivo, escaneie o QR code com a câmera. Isso abre uma página no navegador mostrando a tela virtual do seu Mac.", icon: "qrcode.viewfinder"),
            GuideStep(id: 4, title: "Arrastar Janelas", description: "Arraste qualquer janela para a tela virtual (ela aparece nos ajustes de Monitor como uma tela extra).", icon: "macwindow.badge.plus"),
            GuideStep(id: 5, title: "Modo AR (iPhone)", description: "Usando o app companheiro, a tela virtual aparece como um painel flutuante em AR, ancorado a uma superfície.", icon: "arkit"),
        ],
        gestures: [
            GestureInfo(name: "Arrastar para o Portal", icon: "arrow.right.square", action: "Enviar Janela", howTo: "Arraste qualquer janela para a área da tela virtual (mostrada nos ajustes de Monitor)."),
            GestureInfo(name: "Escanear QR", icon: "qrcode.viewfinder", action: "Conectar Dispositivo", howTo: "Escaneie o QR code em qualquer dispositivo para começar a receber o stream da tela."),
        ],
        tips: [
            "Wi-Fi de 5GHz oferece a melhor qualidade de streaming com menor latência",
            "Você pode conectar vários dispositivos simultaneamente",
            "A resolução da tela virtual é configurável nas Configurações",
            "O modo AR no iPhone requer uma superfície plana para o ponto de ancoragem",
            "Ótimo para estender seu espaço de trabalho para um iPad ou tablet antigo!",
        ]
    )

    // MARK: - GhostDrop

    static let ghostDrop = ModuleGuide(
        id: "ghost-drop",
        name: "GhostDrop",
        icon: "hand.draw",
        tagline: "Cross-Reality Clipboard",
        overview: "Agarre conteúdo da tela do seu Mac com um gesto de mão e arremesse para o seu celular! Textos, imagens e arquivos voam entre dispositivos com um movimento de arremesso. É como ter copiar e colar telecinético.",
        requirements: [
            GuideRequirement(icon: "camera", name: "Câmera", description: "Webcam para detecção de gestos de mão"),
            GuideRequirement(icon: "wifi", name: "Mesma Rede", description: "Ambos os dispositivos no mesmo Wi-Fi"),
            GuideRequirement(icon: "iphone", name: "App Companheiro", description: "SixthSense Companion no dispositivo receptor"),
        ],
        steps: [
            GuideStep(id: 1, title: "Ative o GhostDrop", description: "Ative o GhostDrop. Se o HandCommand também estiver ativo, ele compartilha o mesmo rastreamento de mão.", icon: "power"),
            GuideStep(id: 2, title: "Conectar Dispositivo", description: "Abra o app companheiro > aba GhostDrop. Seu Mac deve aparecer. Toque para conectar.", icon: "link"),
            GuideStep(id: 3, title: "Copiar Conteúdo", description: "Copie qualquer texto, imagem ou arquivo para a área de transferência do Mac (Cmd+C como de costume).", icon: "doc.on.clipboard"),
            GuideStep(id: 4, title: "Gesto de Agarrar", description: "Faça um gesto de agarrar (feche todos os dedos em um punho) na frente da câmera. Você verá uma confirmação visual.", icon: "hand.raised.slash"),
            GuideStep(id: 5, title: "Arremesse!", description: "Faça um movimento rápido de arremesso em direção ao seu celular. O conteúdo voa para o dispositivo conectado!", icon: "paperplane"),
            GuideStep(id: 6, title: "Receber no Celular", description: "O conteúdo aparece no app companheiro e é copiado para a área de transferência do seu celular.", icon: "checkmark.circle"),
        ],
        gestures: [
            GestureInfo(name: "Agarrar", icon: "hand.raised.slash", action: "Capturar Área de Transferência", howTo: "Feche todos os dedos em um punho. Isso captura o que estiver na área de transferência do seu Mac."),
            GestureInfo(name: "Arremessar", icon: "paperplane", action: "Enviar para Dispositivo", howTo: "Depois de agarrar, lance a mão rapidamente em qualquer direção para enviar o conteúdo."),
            GestureInfo(name: "Pegar", icon: "hand.raised", action: "Receber Conteúdo", howTo: "Abra a mão (palma voltada para a câmera) quando conteúdo estiver chegando de outro dispositivo."),
        ],
        tips: [
            "Funciona melhor quando o HandCommand também está ativo (compartilha o pipeline de rastreamento de mão)",
            "Você pode arremessar para qualquer dispositivo conectado — a direção do arremesso escolhe o alvo",
            "Textos, imagens e arquivos pequenos são suportados",
            "A animação de arremesso mostra o conteúdo voando para fora da tela",
            "Se você tiver vários dispositivos conectados, arremesse para a esquerda ou direita para escolher qual",
        ]
    )

    // MARK: - NotchBar

    static let notchBar = ModuleGuide(
        id: "notch-bar",
        name: "NotchBar",
        icon: "menubar.rectangle",
        tagline: "Notch Alive",
        overview: "Transforme o notch do MacBook de espaço morto em um centro de controle interativo. Veja a música tocando agora com um visualizador, notificações rápidas e ações de atalho — tudo vivendo dentro do notch.",
        requirements: [
            GuideRequirement(icon: "laptopcomputer", name: "MacBook com Notch", description: "MacBook Pro 14\"/16\" (2021+) ou MacBook Air M2+. Em outros Macs, usa uma barra no topo central."),
            GuideRequirement(icon: "mic", name: "Microfone (Opcional)", description: "Para visualização de áudio no notch"),
        ],
        steps: [
            GuideStep(id: 1, title: "Ative o NotchBar", description: "Ative o NotchBar. A área do notch se transformará em uma barra interativa.", icon: "power"),
            GuideStep(id: 2, title: "Passar o Cursor para Expandir", description: "Mova o cursor para a área do notch. Ele expande para mostrar mais controles e informações.", icon: "arrow.up.left.and.arrow.down.right"),
            GuideStep(id: 3, title: "Tocando Agora", description: "Quando uma música está tocando, o notch mostra o título da música e um visualizador de ondas.", icon: "music.note"),
            GuideStep(id: 4, title: "Notificações", description: "Novas notificações deslizam para baixo a partir do notch brevemente antes de desaparecer.", icon: "bell"),
            GuideStep(id: 5, title: "Personalizar", description: "Nas Configurações, escolha o que aparece no notch: música, notificações, ações rápidas ou status do sistema.", icon: "slider.horizontal.3"),
        ],
        gestures: [
            GestureInfo(name: "Passar o Cursor", icon: "cursorarrow.motionlines", action: "Expandir Notch", howTo: "Mova o cursor para a área do notch para revelar o centro de controle expandido."),
            GestureInfo(name: "Clicar", icon: "cursorarrow.click", action: "Ações Rápidas", howTo: "Clique nos itens do notch expandido para acionar ações."),
            GestureInfo(name: "Afastar o Cursor", icon: "cursorarrow", action: "Recolher", howTo: "Afaste o cursor e a barra do notch recolhe para a visualização mínima."),
        ],
        tips: [
            "Em Macs sem notch, o NotchBar cria uma barra flutuante no topo central",
            "O visualizador de música reage a qualquer áudio que estiver tocando",
            "Você pode desativar o auto-ocultar nas Configurações para manter a barra do notch sempre visível",
            "O NotchBar funciona junto com todos os outros módulos — não haverá conflito",
            "Conceda permissão de Microfone para o recurso de visualizador de áudio",
        ]
    )
}

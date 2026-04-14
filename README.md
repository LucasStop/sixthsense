# SixthSense

> Controle futurista do macOS: gestos de mão, rastreamento do olhar, iPhone como controle remoto, exibições de portal, área de transferência entre realidades e uma barra de notch interativa.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)

## Módulos

| Módulo | Descrição | Status |
|--------|-----------|--------|
| **HandCommand** | Controle janelas com gestos de mão via webcam (pinça, deslizar, abrir) | Em desenvolvimento |
| **GazeShift** | Desktop com rastreamento do olhar: janelas reagem para onde você olha | Em desenvolvimento |
| **AirCursor** | Use seu iPhone como um Wii Remote para controlar o cursor do Mac | Em desenvolvimento |
| **PortalView** | Transforme qualquer dispositivo em um portal para seu Mac via QR code + WebRTC | Em desenvolvimento |
| **GhostDrop** | Agarre conteúdo com um gesto de mão e jogue para outro dispositivo | Em desenvolvimento |
| **NotchBar** | Transforme o notch do MacBook em um centro de controle interativo | Em desenvolvimento |

## Arquitetura

Aplicativo único de menu bar com arquitetura modular. Cada feature é um Swift Package independente que pode ser ativado/desativado em tempo de execução.

```
SixthSense/
├── Packages/
│   ├── SixthSenseCore/       # Protocolos do domínio (ModuleProtocol, EventBus)
│   ├── SharedServices/        # Câmera, Rede, Overlay, Acessibilidade, Input
│   ├── HandCommandModule/     # Controle por gestos de mão
│   ├── GazeShiftModule/       # Rastreamento do olhar
│   ├── AirCursorModule/       # Cursor via giroscópio do iPhone
│   ├── PortalViewModule/      # Streaming de display via WebRTC
│   ├── GhostDropModule/       # Área de transferência entre dispositivos
│   └── NotchBarModule/        # UI do notch
├── SixthSenseApp/             # Shell principal do aplicativo
└── SixthSenseCompanion/       # App companion para iOS
```

## Stack Tecnológico

- **Swift + SwiftUI** (macOS nativo)
- **Vision Framework** (pose de mão + landmarks faciais)
- **CGEvent** (injeção de eventos sintéticos)
- **Accessibility API** (gerenciamento de janelas)
- **Network.framework** (descoberta de dispositivos via Bonjour)
- **ScreenCaptureKit** (captura de tela)
- **WebRTC** (streaming de display)
- **ARKit** (features AR do companion iOS)

## Requisitos

- macOS 14 (Sonoma) ou superior
- Xcode 15+
- Swift 5.9+
- MacBook com câmera (para HandCommand e GazeShift)
- iPhone (para o companion AirCursor)

## Compilação

```bash
# Clonar
git clone https://github.com/LucasStop/SixthSense.git
cd SixthSense

# Compilar com SPM
swift build

# Executar
swift run SixthSense

# Rodar os testes
swift test
```

## Permissões

O aplicativo requer as seguintes permissões do sistema:
- **Câmera** — Rastreamento de gestos e do olhar
- **Acessibilidade** — Gerenciamento de janelas e controle do cursor
- **Gravação de Tela** — Captura de tela para o PortalView
- **Rede Local** — Comunicação entre dispositivos

## Licença

Licença MIT. Veja [LICENSE](LICENSE) para detalhes.

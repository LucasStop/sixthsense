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

# Build + install + run em um único comando (recomendado)
./scripts/dev.sh

# Ou só compilar sem rodar
./scripts/build-app.sh --debug

# Rodar os testes
swift test
```

O script `dev.sh` empacota o binário em `~/Applications/SixthSense.app`
com assinatura ad-hoc e path fixo. Isso permite que a permissão de
Acessibilidade concedida **persista entre rebuilds** — veja a seção
de permissões abaixo.

Evite usar `swift run SixthSense` diretamente: o binário fica em um
path diferente do DerivedData a cada build e a macOS invalida a
autorização de Acessibilidade toda vez.

## Permissões

O aplicativo requer as seguintes permissões do sistema:
- **Câmera** — Rastreamento de gestos e do olhar
- **Acessibilidade** — Gerenciamento de janelas e controle do cursor
- **Gravação de Tela** — Captura de tela para o PortalView
- **Rede Local** — Comunicação entre dispositivos

### Acessibilidade não persiste entre builds?

Esse é um problema conhecido de binários SPM sem `.app` bundle. A
macOS TCC database identifica apps autorizados por **bundle ID +
assinatura de código + path**. Quando nenhum dos três é estável
(caso do `swift run`), a permissão é invalidada a cada rebuild.

A solução está no script `scripts/build-app.sh`, que monta um
`SixthSense.app` com:

- **Path fixo**: `~/Applications/SixthSense.app`
- **Bundle ID estável**: `com.lucasstop.sixthsense`
- **Assinatura ad-hoc**: `codesign --force --deep --sign -`

Fluxo de setup (apenas uma vez):

1. `./scripts/dev.sh` — compila e abre o app.
2. Ajustes do Sistema → Privacidade e Segurança → Acessibilidade.
3. Clique em "+" e adicione `~/Applications/SixthSense.app`.
4. Reinicie o app (ou rode `./scripts/dev.sh` de novo).

A partir daí, qualquer `./scripts/dev.sh` posterior preserva a
autorização automaticamente — o bundle ID + assinatura ad-hoc +
path continuam idênticos entre builds.

Você pode conferir o status em tempo real no **Centro de Treinamento
→ HandCommand**, que mostra um painel de diagnóstico com
`AXIsProcessTrusted()` e um botão "Testar injeção" para validar o
pipeline CGEvent.

## Licença

Licença MIT. Veja [LICENSE](LICENSE) para detalhes.

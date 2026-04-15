# SixthSense

> Controle futurista do macOS com gestos de mão detectados por webcam.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)

## Visão geral

O SixthSense é um app de menu bar que rastreia as duas mãos do usuário em
tempo real e converte gestos em ações reais do macOS via CGEvent. Toda a
detecção roda localmente no Mac — nenhum dado sai do dispositivo.

### Gestos

| Gesto | Mão | Ação |
|-------|-----|------|
| Apontar o indicador | Direita | Move o cursor |
| Punho fechado (hold ~250ms) | Direita | Mission Control |
| Pinça (polegar + indicador) | Esquerda | Clicar |
| Punho fechado | Esquerda | Segurar para arrastar |
| Traçar círculo no ar | Esquerda | Rolar (anti-horário = cima, horário = baixo) |
| Shaka (polegar + mindinho) | Esquerda | ⌘+Tab (trocar app) |

Cada gesto pode ser ligado ou desligado individualmente em **Configurações
→ HandCommand**.

## Arquitetura

Aplicativo único de menu bar com arquitetura em pacotes Swift. A lógica
pura de classificação, roteamento de ações e filtros vive em
`SixthSenseCore` e é testada de forma isolada.

```
SixthSense/
├── Packages/
│   ├── SixthSenseCore/         # Classificação de gestos, router, filtros (puros)
│   ├── SharedServices/         # Câmera, cursor, acessibilidade, overlays
│   ├── SharedServicesMocks/    # Fakes para testes da pipeline
│   └── HandCommandModule/      # Glue Vision + CGEvent para o HandCommand
├── SixthSenseApp/              # Shell principal (menu bar, janelas, tutorial)
└── scripts/                    # Build e empacotamento em .app
```

## Stack Tecnológico

- **Swift + SwiftUI** (macOS nativo)
- **Vision Framework** (pose de mão em 21 landmarks)
- **CGEvent + CGEventSource** (injeção de eventos sintéticos de mouse e teclado)
- **Accessibility API** (AXIsProcessTrusted, gate de permissão)
- **Swift Testing** (@Test, #expect)

## Requisitos

- macOS 14 (Sonoma) ou superior
- Xcode 15+ / Swift 5.9+
- MacBook com câmera frontal
- Boa iluminação frontal (evite contraluz atrás das mãos)

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

O aplicativo requer duas permissões do sistema:

- **Câmera** — Detecta as duas mãos em tempo real via Vision
- **Acessibilidade** — Injeta eventos de cursor e teclado via CGEvent

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

Você pode conferir o status em tempo real no **Modo Treinamento
→ HandCommand**, que mostra um painel de diagnóstico com
`AXIsProcessTrusted()` e um botão "Testar injeção" para validar o
pipeline CGEvent.

## Licença

Licença MIT. Veja [LICENSE](LICENSE) para detalhes.

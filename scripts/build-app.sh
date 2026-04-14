#!/usr/bin/env bash
#
# build-app.sh — Empacota o executável do SPM em um .app bundle com
# assinatura ad-hoc estável e path fixo, para que a permissão de
# Acessibilidade concedida pelo usuário persista entre rebuilds.
#
# Por padrão:
#   - Compila em release mode (para velocidade de runtime)
#   - Monta SixthSense.app em build/SixthSense.app
#   - Assina ad-hoc com identidade "-" (identity estável baseada em bundle ID)
#
# Flags:
#   -d, --debug     Compila em debug mode
#   -i, --install   Copia o .app resultante para ~/Applications/SixthSense.app
#   -r, --run       Abre o .app após o build (implica -i)
#   -h, --help      Mostra esta mensagem
#
# O path resultante é SEMPRE o mesmo, então o usuário só precisa autorizar
# o SixthSense em Ajustes do Sistema → Privacidade → Acessibilidade UMA vez.

set -euo pipefail

# ---------- Parse flags ----------

CONFIG="release"
DO_INSTALL=0
DO_RUN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d|--debug)    CONFIG="debug"; shift ;;
        -i|--install)  DO_INSTALL=1; shift ;;
        -r|--run)      DO_RUN=1; DO_INSTALL=1; shift ;;
        -h|--help)
            sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Opção desconhecida: $1" >&2
            exit 2
            ;;
    esac
done

# ---------- Paths ----------

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
APP_NAME="SixthSense"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
INFO_PLIST_SRC="$REPO_ROOT/SixthSenseApp/Resources/Info.plist"
INSTALL_DEST="$HOME/Applications/$APP_NAME.app"

cd "$REPO_ROOT"

# ---------- Step 1: swift build ----------

echo "▶ Compilando ($CONFIG)..."
swift build -c "$CONFIG" --product SixthSense

EXECUTABLE_PATH="$(swift build -c "$CONFIG" --show-bin-path)/SixthSense"
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
    echo "✗ Executável não encontrado em $EXECUTABLE_PATH" >&2
    exit 1
fi
echo "  binary: $EXECUTABLE_PATH"

# ---------- Step 2: montar o .app bundle ----------

echo "▶ Montando $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$INFO_PLIST_SRC" "$APP_BUNDLE/Contents/Info.plist"

# Permite que o runtime saiba o bundle root — Bundle.main passa a funcionar.
touch "$APP_BUNDLE/Contents/Resources/.keep"

# ---------- Step 3: ad-hoc codesign ----------
#
# A assinatura ad-hoc (identity "-") gera um code directory hash derivado
# exclusivamente do conteúdo + bundle identifier. Dois binários idênticos
# com mesmo bundle ID produzem a MESMA assinatura, mesmo que compilados
# em momentos diferentes. Com isso, a TCC database do macOS reconhece o
# app como o mesmo entre rebuilds e preserva a permissão de Acessibilidade.

echo "▶ Assinando ad-hoc..."
codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --verbose=2 "$APP_BUNDLE" 2>&1 | sed 's/^/  /'

# ---------- Step 4: install ----------

if [[ "$DO_INSTALL" -eq 1 ]]; then
    mkdir -p "$HOME/Applications"

    # Se já existe em ~/Applications, só substitui o conteúdo interno
    # (não apaga o bundle) — isso preserva o inode e qualquer dado que o
    # TCC possa usar como reforço de identidade entre rebuilds.
    if [[ -d "$INSTALL_DEST" ]]; then
        echo "▶ Atualizando $INSTALL_DEST (preservando bundle)..."
        rsync -a --delete "$APP_BUNDLE/" "$INSTALL_DEST/"
    else
        echo "▶ Instalando em $INSTALL_DEST..."
        cp -R "$APP_BUNDLE" "$INSTALL_DEST"
    fi

    # Re-codesign after install — rsync pode invalidar a signature.
    codesign --force --deep --sign - "$INSTALL_DEST"
    echo "  instalado"
fi

# ---------- Step 5: run ----------

if [[ "$DO_RUN" -eq 1 ]]; then
    echo "▶ Abrindo $INSTALL_DEST..."
    # Mata qualquer instância anterior antes de abrir a nova
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    open "$INSTALL_DEST"
fi

# ---------- Done ----------

echo ""
echo "✓ Concluído."
echo ""
if [[ "$DO_INSTALL" -eq 1 ]]; then
    echo "  Bundle instalado em:"
    echo "    $INSTALL_DEST"
else
    echo "  Bundle pronto em:"
    echo "    $APP_BUNDLE"
fi
echo ""
echo "  Se for a primeira execução, vá em Ajustes do Sistema →"
echo "  Privacidade → Acessibilidade e adicione o .app acima. Depois"
echo "  disso, rebuilds vão preservar a permissão."

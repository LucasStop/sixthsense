#!/usr/bin/env bash
#
# build-app.sh — Empacota o executável do SPM em um .app bundle com
# assinatura estável e path fixo, para que a permissão de
# Acessibilidade concedida pelo usuário persista entre rebuilds.
#
# Por padrão:
#   - Compila em release mode (para velocidade de runtime)
#   - Monta SixthSense.app em build/SixthSense.app
#   - Assina com a primeira identidade "Apple Development" do keychain
#     (ou SIXTHSENSE_SIGN_ID); sem nenhuma, cai para ad-hoc
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

# ---------- Step 3: codesign ----------
#
# O TCC casa a permissão com o designated requirement da assinatura.
# Ad-hoc ("-") vira `cdhash H"..."`, que muda a cada build → a chave em
# Ajustes continua ligada mas AXIsProcessTrusted() devolve false.
# Com um certificado, o requirement é bundle ID + certificado, estável
# entre builds.

SIGN_ID="${SIXTHSENSE_SIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ {print $2; exit}')}"
SIGN_ID="${SIGN_ID:--}"

if [[ "$SIGN_ID" == "-" ]]; then
    echo "▶ Assinando ad-hoc (sem certificado — Acessibilidade será pedida a cada build)..."
else
    echo "▶ Assinando com \"$SIGN_ID\"..."
fi
codesign --force --deep --sign "$SIGN_ID" "$APP_BUNDLE"
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
    codesign --force --deep --sign "$SIGN_ID" "$INSTALL_DEST"
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

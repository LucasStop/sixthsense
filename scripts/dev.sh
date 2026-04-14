#!/usr/bin/env bash
#
# dev.sh — Loop de desenvolvimento rápido.
#
# Recompila o SixthSense.app em debug mode, reinstala em
# ~/Applications/SixthSense.app (preservando o bundle para manter a
# permissão de Acessibilidade) e relança o app.
#
# Uso:
#   ./scripts/dev.sh
#
# Na primeira execução, autorize o app em Ajustes do Sistema →
# Privacidade → Acessibilidade. Daí em diante, toda execução deste
# script mantém a permissão.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/build-app.sh" --debug --run

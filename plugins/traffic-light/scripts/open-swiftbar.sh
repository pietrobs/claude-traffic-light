#!/usr/bin/env bash
# Abre o SwiftBar (a bolinha 🚦) se ele não estiver rodando.
# Não instala nada — para instalação use setup-swiftbar.sh (/traffic-light:setup).

set -euo pipefail

if /usr/bin/pgrep -xq SwiftBar; then
    echo "SwiftBar já está rodando — a bolinha deve estar na barra de menu."
    exit 0
fi

# Mesma lógica do setup: logo após instalar via brew, "open -a" pode falhar
# (LaunchServices ainda não indexou) — prefere abrir pelo caminho.
if [ -d "/Applications/SwiftBar.app" ]; then
    open "/Applications/SwiftBar.app"
elif [ -d "$HOME/Applications/SwiftBar.app" ]; then
    open "$HOME/Applications/SwiftBar.app"
elif open -a SwiftBar 2>/dev/null; then
    :
else
    echo "ERRO: SwiftBar não está instalado. Rode /traffic-light:setup primeiro."
    exit 1
fi

echo "SwiftBar iniciado — a bolinha 🚦 deve aparecer na barra de menu."

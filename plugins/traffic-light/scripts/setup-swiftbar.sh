#!/usr/bin/env bash
# Configura a camada de display (SwiftBar) do Claude Traffic Light.
# - Instala o SwiftBar via Homebrew se preciso
# - Configura a pasta de plugins do SwiftBar
# - Copia claude-light.30s.sh para lá e inicia o SwiftBar
# Idempotente: pode rodar de novo pra atualizar.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Verificando SwiftBar"
if [ ! -d "/Applications/SwiftBar.app" ] && [ ! -d "$HOME/Applications/SwiftBar.app" ]; then
    if command -v brew >/dev/null 2>&1; then
        echo "   SwiftBar não encontrado — instalando via Homebrew..."
        brew install --cask swiftbar
    else
        echo "   ERRO: SwiftBar não está instalado e o Homebrew não foi encontrado."
        echo "   Instale o SwiftBar (https://swiftbar.app ou 'brew install --cask swiftbar')"
        echo "   e rode este setup de novo."
        exit 1
    fi
fi

echo "==> Configurando pasta de plugins do SwiftBar"
# Fecha o SwiftBar antes de mexer nas preferências (senão ele sobrescreve ao sair).
killall SwiftBar 2>/dev/null || true
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -z "${PLUGIN_DIR:-}" ]; then
    PLUGIN_DIR="$HOME/SwiftBarPlugins"
    defaults write com.ameba.SwiftBar PluginDirectory "$PLUGIN_DIR"
    echo "   Pasta de plugins definida: $PLUGIN_DIR"
fi
PLUGIN_DIR="${PLUGIN_DIR/#\~/$HOME}"
mkdir -p "$PLUGIN_DIR"
# Remove qualquer versão anterior (nome antigo claude-light.5s.sh) antes de
# copiar — senão o SwiftBar mostra DUAS bolinhas após a renomeação do intervalo.
rm -f "$PLUGIN_DIR"/claude-light.*.sh
cp "$SRC_DIR/claude-light.30s.sh" "$PLUGIN_DIR/claude-light.30s.sh"
chmod +x "$PLUGIN_DIR/claude-light.30s.sh"
echo "   Plugin copiado para $PLUGIN_DIR"

# Carimba a versão instalada pro menu do display ler. Fonte: plugin.json
# (caminho plugin). No caminho zip não há plugin.json — fica vazio e o
# display simplesmente não mostra a linha de versão.
APP_DIR="$HOME/.claude-traffic-light"
mkdir -p "$APP_DIR"
PJ="$SRC_DIR/../.claude-plugin/plugin.json"
if [ -f "$PJ" ]; then
    /usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("version",""))' \
        "$PJ" > "$APP_DIR/version" 2>/dev/null || : > "$APP_DIR/version"
else
    : > "$APP_DIR/version"
fi

echo "==> Iniciando SwiftBar"
# Logo após o brew instalar, "open -a SwiftBar" pode falhar (LaunchServices
# ainda não indexou o app) — abre pelo caminho e nunca aborta a instalação aqui.
if [ -d "/Applications/SwiftBar.app" ]; then
    open "/Applications/SwiftBar.app" || true
elif [ -d "$HOME/Applications/SwiftBar.app" ]; then
    open "$HOME/Applications/SwiftBar.app" || true
else
    open -a SwiftBar 2>/dev/null || echo "   Não consegui abrir sozinho — abra o SwiftBar pelo Launchpad."
fi

echo ""
echo "Pronto! 🚦 A bolinha deve aparecer na barra de menu."

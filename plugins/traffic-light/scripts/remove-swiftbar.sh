#!/usr/bin/env bash
# Remove a camada de display (SwiftBar) do Claude Traffic Light.
# - Remove claude-light.*.sh da pasta de plugins do SwiftBar
# - Remove os estados em ~/.claude-traffic-light
# O SwiftBar em si fica (brew uninstall --cask swiftbar, se quiser).

set -euo pipefail

echo "==> Removendo plugin do SwiftBar"
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
PLUGIN_DIR="${PLUGIN_DIR/#\~/$HOME}"
if [ -n "${PLUGIN_DIR:-}" ] && ls "$PLUGIN_DIR"/claude-light.*.sh >/dev/null 2>&1; then
    rm -f "$PLUGIN_DIR"/claude-light.*.sh
    echo "   Removido de $PLUGIN_DIR"
fi

echo "==> Removendo estados em ~/.claude-traffic-light"
rm -rf "$HOME/.claude-traffic-light"

open -g "swiftbar://refreshallplugins" >/dev/null 2>&1 || true

echo ""
echo "Display removido. O SwiftBar em si não foi removido."

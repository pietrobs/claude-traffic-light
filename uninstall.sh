#!/usr/bin/env bash
# Desinstalador do Claude Traffic Light.
# - Remove os hooks de ~/.claude/settings.json
# - Remove o plugin da pasta do SwiftBar
# - Remove ~/.claude-traffic-light

set -euo pipefail

APP_DIR="$HOME/.claude-traffic-light"

echo "==> Removendo hooks de ~/.claude/settings.json"
/usr/bin/python3 <<'PY'
import json, os

settings = os.path.join(os.path.expanduser("~"), ".claude", "settings.json")
if os.path.exists(settings):
    with open(settings) as f:
        data = json.load(f)
    hooks = data.get("hooks", {})
    for event in list(hooks):
        groups = [
            g for g in hooks[event]
            if not any("claude-light-hook.sh" in h.get("command", "")
                       for h in g.get("hooks", []))
        ]
        if groups:
            hooks[event] = groups
        else:
            del hooks[event]
    with open(settings, "w") as f:
        json.dump(data, f, indent=2)
    print("   hooks removidos")
else:
    print("   settings.json não existe, nada a fazer")
PY

echo "==> Removendo plugin do SwiftBar"
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
PLUGIN_DIR="${PLUGIN_DIR/#\~/$HOME}"
if [ -n "${PLUGIN_DIR:-}" ] && ls "$PLUGIN_DIR"/claude-light.*.sh >/dev/null 2>&1; then
    rm -f "$PLUGIN_DIR"/claude-light.*.sh
    echo "   Removido de $PLUGIN_DIR"
fi

echo "==> Removendo $APP_DIR"
rm -rf "$APP_DIR"

open -g "swiftbar://refreshallplugins" >/dev/null 2>&1 || true

echo ""
echo "Desinstalado. O SwiftBar em si não foi removido (brew uninstall --cask swiftbar, se quiser)."

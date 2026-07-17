#!/usr/bin/env bash
# Instalador do Claude Traffic Light (menu bar, macOS).
# - Copia o hook para ~/.claude-traffic-light/
# - Faz merge idempotente dos hooks em ~/.claude/settings.json
# - Instala o plugin do SwiftBar (se o diretório de plugins estiver configurado)

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$HOME/.claude-traffic-light"
HOOK="$APP_DIR/claude-light-hook.sh"

echo "==> Instalando em $APP_DIR"
mkdir -p "$APP_DIR"
cp "$SRC_DIR/claude-light-hook.sh" "$HOOK"
cp "$SRC_DIR/claude-light.5s.sh"   "$APP_DIR/claude-light.5s.sh"
chmod +x "$HOOK" "$APP_DIR/claude-light.5s.sh"

echo "==> Registrando hooks em ~/.claude/settings.json"
/usr/bin/python3 - "$HOOK" <<'PY'
import json, os, sys

hook = sys.argv[1]
settings = os.path.join(os.path.expanduser("~"), ".claude", "settings.json")
os.makedirs(os.path.dirname(settings), exist_ok=True)

data = {}
if os.path.exists(settings):
    try:
        with open(settings) as f:
            data = json.load(f)
    except Exception:
        data = {}

hooks = data.setdefault("hooks", {})

# event -> (state, matcher_needed)
mapping = {
    "UserPromptSubmit": ("running", False),
    "PreToolUse":       ("running", True),
    # PermissionRequest dispara depois do PreToolUse; sem isto o vermelho fica preso após aprovar.
    "PostToolUse":      ("running", True),
    "Notification":     ("waiting", False),
    # Notification não dispara na extensão VSCode (issue #28774); PermissionRequest cobre lá.
    "PermissionRequest": ("waiting", True),
    "Stop":             ("done",    False),
    "SessionEnd":       ("end",     False),
}

for event, (state, needs_matcher) in mapping.items():
    cmd = f'"{hook}" {state}'
    arr = hooks.setdefault(event, [])
    already = any(
        any(h.get("command") == cmd for h in g.get("hooks", []))
        for g in arr if isinstance(g, dict)
    )
    if already:
        continue
    group = {"hooks": [{"type": "command", "command": cmd}]}
    if needs_matcher:
        group["matcher"] = "*"
    arr.append(group)

with open(settings, "w") as f:
    json.dump(data, f, indent=2)
print("   settings.json atualizado")
PY

echo "==> Instalando plugin do SwiftBar"
PLUGIN_DIR="$(defaults read com.ameba.SwiftBar PluginDirectory 2>/dev/null || true)"
if [ -n "${PLUGIN_DIR:-}" ] && [ -d "$PLUGIN_DIR" ]; then
    cp "$SRC_DIR/claude-light.5s.sh" "$PLUGIN_DIR/claude-light.5s.sh"
    chmod +x "$PLUGIN_DIR/claude-light.5s.sh"
    echo "   Copiado para $PLUGIN_DIR"
    open -g "swiftbar://refreshallplugins" >/dev/null 2>&1 || true
else
    echo "   SwiftBar ainda não tem pasta de plugins configurada."
    echo "   1) brew install --cask swiftbar   (se ainda não tiver)"
    echo "   2) Abra o SwiftBar e escolha uma pasta de plugins"
    echo "   3) Copie manualmente:"
    echo "        cp \"$APP_DIR/claude-light.5s.sh\" <sua-pasta-de-plugins>/"
fi

echo ""
echo "Pronto. Abra uma nova sessão do Claude Code para os hooks entrarem em ação."

#!/usr/bin/env bash
# Instalador do Claude Traffic Light (menu bar, macOS) — caminho SEM plugin.
# Se você usa o plugin do Claude Code (claude plugin install traffic-light@...),
# NÃO precisa deste script: os hooks vêm do plugin e o display via /traffic-light:setup.
#
# - Copia o hook para ~/.claude-traffic-light/
# - Faz merge idempotente dos hooks em ~/.claude/settings.json
# - Configura o SwiftBar via setup-swiftbar.sh

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# No zip gerado pelo build.sh os scripts ficam ao lado; no repo, em plugins/traffic-light/scripts.
if [ -f "$SRC_DIR/claude-light-hook.sh" ]; then
    SCRIPTS_DIR="$SRC_DIR"
else
    SCRIPTS_DIR="$SRC_DIR/plugins/traffic-light/scripts"
fi

APP_DIR="$HOME/.claude-traffic-light"
HOOK="$APP_DIR/claude-light-hook.sh"

echo "==> Instalando em $APP_DIR"
mkdir -p "$APP_DIR"
cp "$SCRIPTS_DIR/claude-light-hook.sh" "$HOOK"
cp "$SCRIPTS_DIR/claude-light.5s.sh"   "$APP_DIR/claude-light.5s.sh"
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

bash "$SCRIPTS_DIR/setup-swiftbar.sh"

echo "Abra uma NOVA sessão do Claude Code para os hooks entrarem em ação."

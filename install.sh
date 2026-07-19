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
rm -f "$APP_DIR"/claude-light.*.sh   # limpa nome antigo (.5s) ao atualizar
cp "$SCRIPTS_DIR/claude-light.30s.sh" "$APP_DIR/claude-light.30s.sh"
chmod +x "$HOOK" "$APP_DIR/claude-light.30s.sh"

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
    # "prompt" marca o turno como iniciado pelo usuário — só esses turnos
    # tocam som; turnos de background (subagentes, wakeups) ficam mudos.
    "UserPromptSubmit": ("prompt", False),
    # PostToolUse devolve o amarelo depois que você aprova uma permissão.
    "PostToolUse":      ("running", True),
    # PermissionRequest funciona na CLI e na extensão VSCode.
    "PermissionRequest": ("waiting", True),
    "Stop":             ("done",    False),
    "SessionEnd":       ("end",     False),
}

# Migração: instalações antigas registravam UserPromptSubmit -> "running".
old_cmd = f'"{hook}" running'
for g in hooks.get("UserPromptSubmit", []):
    if isinstance(g, dict):
        g["hooks"] = [h for h in g.get("hooks", []) if h.get("command") != old_cmd]
hooks["UserPromptSubmit"] = [
    g for g in hooks.get("UserPromptSubmit", [])
    if not (isinstance(g, dict) and not g.get("hooks"))
]

# Migração: versões anteriores registravam PreToolUse e Notification apontando
# para este hook — agora removidos. Tira grupos nossos desses eventos.
for event in ("PreToolUse", "Notification"):
    kept = [
        g for g in hooks.get(event, [])
        if not (isinstance(g, dict)
                and any("claude-light-hook.sh" in h.get("command", "")
                        for h in g.get("hooks", [])))
    ]
    if kept:
        hooks[event] = kept
    elif event in hooks:
        del hooks[event]

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

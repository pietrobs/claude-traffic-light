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

echo "==> Verificando SwiftBar"
if [ ! -d "/Applications/SwiftBar.app" ] && [ ! -d "$HOME/Applications/SwiftBar.app" ]; then
    if command -v brew >/dev/null 2>&1; then
        echo "   SwiftBar não encontrado — instalando via Homebrew..."
        brew install --cask swiftbar
    else
        echo "   ERRO: SwiftBar não está instalado e o Homebrew não foi encontrado."
        echo "   Instale o SwiftBar (https://swiftbar.app ou 'brew install --cask swiftbar')"
        echo "   e rode este instalador de novo."
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
cp "$SRC_DIR/claude-light.5s.sh" "$PLUGIN_DIR/claude-light.5s.sh"
chmod +x "$PLUGIN_DIR/claude-light.5s.sh"
echo "   Plugin copiado para $PLUGIN_DIR"

echo "==> Iniciando SwiftBar"
open -a SwiftBar

echo ""
echo "Pronto! 🚦 A bolinha deve aparecer na barra de menu."
echo "Abra uma NOVA sessão do Claude Code para os hooks entrarem em ação."

#!/usr/bin/env bash
# Claude Traffic Light 🚦 — instalador de duplo clique (gerado por build.sh).
set -euo pipefail
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/claude-light-hook.sh" <<'EOF_claude_light_hook_sh'
#!/usr/bin/env bash
# claude-light-hook.sh <state>
# state: running | waiting | done | end
#
# Called by Claude Code hooks. Reads the hook JSON payload from stdin,
# extracts session_id and writes the current state for THIS instance.
# Never prints to stdout (some hooks inject stdout into Claude's context).

set -euo pipefail

STATE="${1:-done}"
DIR="$HOME/.claude-traffic-light"
mkdir -p "$DIR"

# Read the hook payload and pull out session_id (fallback: "default").
INPUT="$(cat || true)"
SID="$(printf '%s' "$INPUT" | /usr/bin/python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    sid = str(d.get("session_id") or "default")
except Exception:
    sid = "default"
# keep filename safe
print("".join(c for c in sid if c.isalnum() or c in "-_") or "default")
' 2>/dev/null || echo default)"

FILE="$DIR/$SID.state"

# Sound mode: silent | traffic | beep. Set via the SwiftBar dropdown
# (writes $DIR/sound-mode). Legacy "muted" flag file counts as silent.
MODE="$(cat "$DIR/sound-mode" 2>/dev/null || true)"
if [ -z "$MODE" ]; then
    if [ -f "$DIR/muted" ]; then MODE="silent"; else MODE="traffic"; fi
fi

HORN="$DIR/horn.wav"
if [ "$MODE" = "traffic" ] && [ ! -f "$HORN" ]; then
    # Synthesize the car horn on first use (no binary assets to ship).
    /usr/bin/python3 - "$HORN" <<'PY' >/dev/null 2>&1 || true
import sys, wave, math, struct

SR = 44100
DUR = 0.9
freqs = [(420, 1.0), (505, 0.9)]                      # classic dual-tone horn
harmonics = [(1, 1.0), (2, 0.55), (3, 0.35), (4, 0.18), (5, 0.08)]

frames = bytearray()
for i in range(int(SR * DUR)):
    t = i / SR
    if t < 0.02:
        env = t / 0.02
    elif t > DUR - 0.08:
        env = (DUR - t) / 0.08
    else:
        env = 1.0
    s = sum(a * ha * math.sin(2 * math.pi * f * h * t)
            for f, a in freqs for h, ha in harmonics)
    s = max(-1.0, min(1.0, s * 0.12)) * env
    frames += struct.pack('<h', int(s * 32767))

with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(1)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(bytes(frames))
PY
fi

case "$MODE" in
    silent)  SOUND=""; SOUND_DONE="" ;;
    beep)    SOUND="/System/Library/Sounds/Glass.aiff"
             SOUND_DONE="/System/Library/Sounds/Hero.aiff" ;;
    *)       SOUND="$HORN"
             SOUND_DONE="/System/Library/Sounds/Hero.aiff" ;;
esac
# Env vars still override whatever the mode picked (empty = silent).
SOUND="${CLAUDE_LIGHT_SOUND:-$SOUND}"
SOUND_DONE="${CLAUDE_LIGHT_SOUND_DONE:-$SOUND_DONE}"

# No SwiftBar running = user quit the menu bar app = they don't want the
# feature making noise. State files still get written so the light is
# correct if SwiftBar comes back.
if ! /usr/bin/pgrep -xq SwiftBar; then
    SOUND=""
    SOUND_DONE=""
fi

prev="$(cat "$FILE" 2>/dev/null || true)"

if [ "$STATE" = "end" ]; then
    rm -f "$FILE"
else
    printf '%s' "$STATE" > "$FILE"
fi

# Alert only on state transitions — no repeat while state unchanged.
if [ "$STATE" = "waiting" ] && [ "$prev" != "waiting" ] && [ -n "$SOUND" ] && [ -f "$SOUND" ]; then
    ( /usr/bin/afplay "$SOUND" >/dev/null 2>&1 & )
elif [ "$STATE" = "done" ] && [ "$prev" = "running" ] && [ -n "$SOUND_DONE" ] && [ -f "$SOUND_DONE" ]; then
    ( /usr/bin/afplay "$SOUND_DONE" >/dev/null 2>&1 & )
fi

# Best-effort: nudge SwiftBar to refresh instantly. Only when it is already
# running — `open` on the URL scheme would otherwise RELAUNCH a quit SwiftBar.
if /usr/bin/pgrep -xq SwiftBar; then
    /usr/bin/open -g "swiftbar://refreshplugin?name=claude-light.5s.sh" >/dev/null 2>&1 || true
fi

exit 0
EOF_claude_light_hook_sh
cat > "$TMP/claude-light.5s.sh" <<'EOF_claude_light_5s_sh'
#!/usr/bin/env bash
# <xbar.title>Claude Traffic Light</xbar.title>
# <xbar.desc>Semáforo do estado do Claude (amarelo=rodando, vermelho=esperando você, verde=livre)</xbar.desc>
# <xbar.version>1.0</xbar.version>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
#
# SwiftBar/xbar plugin. Reads every per-instance state file, applies priority
# (waiting > running > free) and renders the light in the menu bar.

DIR="$HOME/.claude-traffic-light"
STALE=1800   # seconds: a running/waiting file older than this = dead session, ignored

now=$(date +%s)
red=0; yellow=0; running_n=0; waiting_n=0; done_n=0

if [ -d "$DIR" ]; then
    for f in "$DIR"/*.state; do
        [ -e "$f" ] || continue
        st=$(cat "$f" 2>/dev/null)
        mt=$(stat -f %m "$f" 2>/dev/null || echo "$now")
        age=$(( now - mt ))
        case "$st" in
            waiting)
                if [ "$age" -lt "$STALE" ]; then red=1; waiting_n=$((waiting_n+1)); fi ;;
            running)
                if [ "$age" -lt "$STALE" ]; then yellow=1; running_n=$((running_n+1)); fi ;;
            done)
                done_n=$((done_n+1)) ;;
        esac
    done
fi

if [ "$red" -eq 1 ]; then
    echo "🔴"
    label="Esperando você"
elif [ "$yellow" -eq 1 ]; then
    echo "🟡"
    label="Rodando"
else
    echo "🟢"
    label="Livre"
fi

echo "---"
echo "Claude: $label | color=#888888"
echo "Rodando: $running_n · Esperando: $waiting_n · Concluídas: $done_n | color=#888888"
echo "---"
# Sound mode selector (legacy "muted" flag counts as silent).
MODE="$(cat "$DIR/sound-mode" 2>/dev/null)"
if [ -z "$MODE" ]; then
    if [ -f "$DIR/muted" ]; then MODE="silent"; else MODE="traffic"; fi
fi
case "$MODE" in
    silent) mode_label="🔇 Silencioso" ;;
    beep)   mode_label="🔔 Beep" ;;
    *)      mode_label="🚗 Buzina" ;;
esac
mark() { [ "$MODE" = "$1" ] && echo "✓ " || echo ""; }
set_mode="printf %s MODENAME > '$DIR/sound-mode'; rm -f '$DIR/muted'"
echo "Som: $mode_label"
echo "--$(mark traffic)🚗 Buzina | bash=/bin/bash param1=-c param2=\"${set_mode/MODENAME/traffic}\" terminal=false refresh=true"
echo "--$(mark beep)🔔 Beep | bash=/bin/bash param1=-c param2=\"${set_mode/MODENAME/beep}\" terminal=false refresh=true"
echo "--$(mark silent)🔇 Silencioso | bash=/bin/bash param1=-c param2=\"${set_mode/MODENAME/silent}\" terminal=false refresh=true"
echo "Limpar estados concluídos | bash=/bin/bash param1=-c param2=\"rm -f '$DIR'/*.state\" terminal=false refresh=true"
echo "Atualizar | refresh=true"
EOF_claude_light_5s_sh
cat > "$TMP/setup-swiftbar.sh" <<'EOF_setup_swiftbar_sh'
#!/usr/bin/env bash
# Configura a camada de display (SwiftBar) do Claude Traffic Light.
# - Instala o SwiftBar via Homebrew se preciso
# - Configura a pasta de plugins do SwiftBar
# - Copia claude-light.5s.sh para lá e inicia o SwiftBar
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
cp "$SRC_DIR/claude-light.5s.sh" "$PLUGIN_DIR/claude-light.5s.sh"
chmod +x "$PLUGIN_DIR/claude-light.5s.sh"
echo "   Plugin copiado para $PLUGIN_DIR"

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
EOF_setup_swiftbar_sh
cat > "$TMP/install.sh" <<'EOF_install_sh'
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
EOF_install_sh
chmod +x "$TMP"/*.sh
bash "$TMP/install.sh"
echo ""
read -r -p "Pressione Enter para fechar esta janela..."

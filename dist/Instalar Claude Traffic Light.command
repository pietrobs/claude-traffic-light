#!/usr/bin/env bash
# Claude Traffic Light 🚦 — instalador de duplo clique (gerado por build.sh).
set -euo pipefail
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/claude-light-hook.sh" <<'EOF_claude_light_hook_sh'
#!/usr/bin/env bash
# claude-light-hook.sh <state>
# state: prompt | running | waiting | done | end
# "prompt" = UserPromptSubmit: same as running, but marks the turn as
# user-initiated so its sounds are allowed to play.
#
# Called by Claude Code hooks. Reads the hook JSON payload from stdin,
# extracts session_id and writes the current state for THIS instance.
# Never prints to stdout (some hooks inject stdout into Claude's context).

set -euo pipefail

STATE="${1:-done}"
DIR="$HOME/.claude-traffic-light"
mkdir -p "$DIR"

# Read the hook payload and pull out session_id (fallback: "default").
# PostToolUse fires on every tool call, so avoid spawning python3 on the hot
# path: session_id is a single-line JSON string, so a line-oriented sed pulls
# it cheaply. Fall back to python only if the fast path finds nothing.
INPUT="$(cat || true)"
SID="$(printf '%s' "$INPUT" | LC_ALL=C /usr/bin/sed -n \
    's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
if [ -z "$SID" ]; then
    SID="$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("session_id") or "default")
except Exception: print("default")' 2>/dev/null || echo default)"
fi
# Keep filename safe.
SID="$(printf '%s' "$SID" | tr -cd 'A-Za-z0-9_-')"
[ -n "$SID" ] || SID="default"

FILE="$DIR/$SID.state"
FLAG="$DIR/$SID.prompted"

# Owning `claude` process PID, for liveness detection. A session that dies
# abnormally (crash, kill, closed window) never fires Stop/SessionEnd, so its
# state file would stay "running" until the STALE timeout — a ghost yellow
# light with nothing running. We record the claude PID here and the display
# script ignores files whose process is gone. Walk up the ancestry (the hook
# may run under a transient shell) to the first ancestor named exactly
# `claude`; fall back to empty (display then uses the time-based STALE check).
OWNER_PID=""
p="$PPID"
for _ in 1 2 3 4 5 6; do
    [ -n "$p" ] && [ "$p" != "0" ] || break
    read -r pp comm < <(/bin/ps -o ppid=,comm= -p "$p" 2>/dev/null)
    case "$(basename "${comm:-}")" in
        claude) OWNER_PID="$p"; break ;;
    esac
    p="$pp"
done

# Only turns the user started get sounds. Claude Code re-invokes the agent
# on its own when background work finishes (subagents, background Bash,
# scheduled wakeups) — those turns fire the same hooks but never
# UserPromptSubmit, so without this flag they would beep at nothing.
#
# Belt-and-suspenders: even when a background re-invocation DOES fire
# UserPromptSubmit, its payload carries an empty "user_message". Only arm the
# flag for a genuine human prompt (non-empty user_message) — this guarantees
# no sound from autonomous work after the answer ("pós prompt respondido").
# Field absent (unexpected payload) → arm, keeping the old user-first default.
if [ "$STATE" = "prompt" ]; then
    STATE="running"
    if printf '%s' "$INPUT" | LC_ALL=C /usr/bin/grep -q '"user_message"[[:space:]]*:[[:space:]]*""'; then
        :   # empty prompt = synthetic/background re-invocation — stay silent
    else
        touch "$FLAG"
    fi
fi

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

# State file format: "<state> <owner_pid>" (pid optional, may be absent in
# files written by older versions). Read back just the state token.
prev="$(cut -d' ' -f1 "$FILE" 2>/dev/null || true)"

if [ "$STATE" = "end" ]; then
    rm -f "$FILE" "$FLAG"
else
    printf '%s %s' "$STATE" "$OWNER_PID" > "$FILE"
fi

# Background turns (no user prompt since last Stop) never make noise —
# the light still updates, but only user-initiated turns may beep.
if [ ! -f "$FLAG" ]; then
    SOUND=""
    SOUND_DONE=""
fi

# Alert only on state transitions — no repeat while state unchanged.
if [ "$STATE" = "waiting" ] && [ "$prev" != "waiting" ] && [ -n "$SOUND" ] && [ -f "$SOUND" ]; then
    ( /usr/bin/afplay "$SOUND" >/dev/null 2>&1 & )
elif [ "$STATE" = "done" ] && [ "$prev" = "running" ] && [ -n "$SOUND_DONE" ] && [ -f "$SOUND_DONE" ]; then
    ( /usr/bin/afplay "$SOUND_DONE" >/dev/null 2>&1 & )
fi

# Turn over: the next sound requires a fresh user prompt.
if [ "$STATE" = "done" ]; then
    rm -f "$FLAG"
fi

# Best-effort: nudge SwiftBar to refresh instantly. Only when it is already
# running — `open` on the URL scheme would otherwise RELAUNCH a quit SwiftBar.
if /usr/bin/pgrep -xq SwiftBar; then
    /usr/bin/open -g "swiftbar://refreshplugin?name=claude-light.30s.sh" >/dev/null 2>&1 || true
fi

exit 0
EOF_claude_light_hook_sh
cat > "$TMP/claude-light.30s.sh" <<'EOF_claude_light_30s_sh'
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
red=0; yellow=0; running_n=0; waiting_n=0

if [ -d "$DIR" ]; then
    for f in "$DIR"/*.state; do
        [ -e "$f" ] || continue
        # Format: "<state> <owner_pid>" (pid optional in files from older versions).
        read -r st pid < "$f" 2>/dev/null
        mt=$(stat -f %m "$f" 2>/dev/null || echo "$now")
        age=$(( now - mt ))
        # Liveness: if the owning claude process is gone, the session died
        # without firing Stop/SessionEnd — ignore its stale running/waiting.
        # When no pid was recorded, fall back to the time-based STALE window.
        if [ -n "$pid" ]; then
            /bin/kill -0 "$pid" 2>/dev/null || continue
        elif [ "$age" -ge "$STALE" ]; then
            continue
        fi
        case "$st" in
            waiting) red=1; waiting_n=$((waiting_n+1)) ;;
            running) yellow=1; running_n=$((running_n+1)) ;;
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
echo "Rodando: $running_n · Esperando: $waiting_n | color=#888888"
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
echo "Atualizar | refresh=true"
# Versão instalada (carimbada pelo setup em $DIR/version a partir do plugin.json).
VER="$(cat "$DIR/version" 2>/dev/null)"
[ -n "$VER" ] && echo "Versão $VER | color=#888888"
EOF_claude_light_30s_sh
cat > "$TMP/setup-swiftbar.sh" <<'EOF_setup_swiftbar_sh'
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
EOF_install_sh
chmod +x "$TMP"/*.sh
bash "$TMP/install.sh"
echo ""
read -r -p "Pressione Enter para fechar esta janela..."

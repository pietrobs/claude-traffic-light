#!/usr/bin/env bash
# <xbar.title>Claude Traffic Light</xbar.title>
# <xbar.desc>Semáforo do estado do Claude (amarelo=rodando, vermelho=esperando você, verde=livre)</xbar.desc>
# <xbar.version>1.2</xbar.version>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
#
# SwiftBar/xbar plugin. Reads every per-instance state file, applies priority
# (waiting > running > free) and renders the light in the menu bar. The
# dropdown lists each live session by project name; clicking one focuses its
# VS Code window (via focus-session.sh).

DIR="$HOME/.claude-traffic-light"
STALE=1800   # seconds: a running/waiting file older than this = dead session, ignored
# focus-session.sh is copied next to this script by setup-swiftbar.sh.
SELF_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)"
FOCUS="$SELF_DIR/focus-session.sh"

now=$(date +%s)
running_n=0; waiting_n=0

# Live sessions, one entry per array slot: state and cwd kept in parallel arrays.
sess_state=(); sess_cwd=()

if [ -d "$DIR" ]; then
    for f in "$DIR"/*.state; do
        [ -e "$f" ] || continue
        # Format: "<state> <owner_pid> <cwd>" (pid "-" when unknown; cwd may
        # contain spaces and runs to end of line). Older files may omit fields.
        read -r st pid cwd < "$f" 2>/dev/null
        mt=$(stat -f %m "$f" 2>/dev/null || echo "$now")
        age=$(( now - mt ))
        # Liveness: if the owning claude process is gone, the session died
        # without firing Stop/SessionEnd (window closed, crash) — its .state is
        # an orphan. Delete it so the dir doesn't grow unbounded and it never
        # flashes in the list. When no pid was recorded ("-"/empty), fall back
        # to the time-based STALE window before pruning.
        if [ -n "$pid" ] && [ "$pid" != "-" ]; then
            /bin/kill -0 "$pid" 2>/dev/null || { rm -f "$f"; continue; }
        elif [ "$age" -ge "$STALE" ]; then
            rm -f "$f"; continue
        fi
        case "$st" in
            waiting) waiting_n=$((waiting_n+1)) ;;
            running) running_n=$((running_n+1)) ;;
        esac
        sess_state+=("$st"); sess_cwd+=("$cwd")
    done
fi

if [ "$waiting_n" -gt 0 ]; then
    echo "🔴"
    label="Esperando você"
elif [ "$running_n" -gt 0 ]; then
    echo "🟡"
    label="Rodando"
else
    echo "🟢"
    label="Livre"
fi

echo "---"
echo "Claude: $label | color=#888888"
echo "Rodando: $running_n · Esperando: $waiting_n | color=#888888"

# Project label from a cwd (basename). Falls back to "sessão" for old files.
projname() { [ -n "$1" ] && basename "$1" || echo "sessão"; }
# Emit a clickable session line that focuses its VS Code window.
sessitem() { # <prefix> <emoji> <cwd>
    local proj; proj="$(projname "$3")"
    if [ -n "$3" ]; then
        echo "$1$2 $proj | bash=\"$FOCUS\" param1=\"$3\" terminal=false refresh=false"
    else
        echo "$1$2 $proj | color=#888888"   # no cwd = nothing to focus
    fi
}

total=${#sess_state[@]}

# Sessions waiting on you, pinned to the top so a single click after opening
# the menu jumps straight to the one asking for permission.
if [ "$waiting_n" -gt 0 ]; then
    echo "---"
    echo "Esperando permissão | color=#cc3333"
    for i in "${!sess_state[@]}"; do
        [ "${sess_state[$i]}" = "waiting" ] || continue
        sessitem "" "🔴" "${sess_cwd[$i]}"
    done
fi

# All live sessions (running + free) with their state dot.
echo "---"
echo "Sessões ($total) | color=#888888"
if [ "$total" -eq 0 ]; then
    echo "Nenhuma sessão ativa | color=#888888"
else
    for i in "${!sess_state[@]}"; do
        case "${sess_state[$i]}" in
            waiting) continue ;;                 # already listed above
            running) emoji="🟡" ;;
            *)       emoji="🟢" ;;
        esac
        sessitem "" "$emoji" "${sess_cwd[$i]}"
    done
fi

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
exit 0

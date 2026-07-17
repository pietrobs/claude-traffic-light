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

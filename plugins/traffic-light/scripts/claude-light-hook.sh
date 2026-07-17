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

# Best-effort: nudge SwiftBar to refresh instantly (ignored if not installed).
/usr/bin/open -g "swiftbar://refreshplugin?name=claude-light.5s.sh" >/dev/null 2>&1 || true

exit 0

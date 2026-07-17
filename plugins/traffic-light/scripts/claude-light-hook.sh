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
if [ "$STATE" = "prompt" ]; then
    STATE="running"
    touch "$FLAG"
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
    /usr/bin/open -g "swiftbar://refreshplugin?name=claude-light.5s.sh" >/dev/null 2>&1 || true
fi

exit 0

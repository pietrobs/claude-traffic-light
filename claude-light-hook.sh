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

# Sounds per state transition (empty = silent).
SOUND="${CLAUDE_LIGHT_SOUND:-/System/Library/Sounds/Glass.aiff}"
SOUND_DONE="${CLAUDE_LIGHT_SOUND_DONE:-/System/Library/Sounds/Hero.aiff}"

prev="$(cat "$FILE" 2>/dev/null || true)"

if [ "$STATE" = "end" ]; then
    rm -f "$FILE"
else
    printf '%s' "$STATE" > "$FILE"
fi

# Alert only on state transitions — no repeat while state unchanged.
# Mute toggle lives in the SwiftBar dropdown (creates/removes this flag file).
if [ -f "$DIR/muted" ]; then
    :
elif [ "$STATE" = "waiting" ] && [ "$prev" != "waiting" ] && [ -n "$SOUND" ] && [ -f "$SOUND" ]; then
    ( /usr/bin/afplay "$SOUND" >/dev/null 2>&1 & )
elif [ "$STATE" = "done" ] && [ "$prev" = "running" ] && [ -n "$SOUND_DONE" ] && [ -f "$SOUND_DONE" ]; then
    ( /usr/bin/afplay "$SOUND_DONE" >/dev/null 2>&1 & )
fi

# Best-effort: nudge SwiftBar to refresh instantly (ignored if not installed).
/usr/bin/open -g "swiftbar://refreshplugin?name=claude-light.5s.sh" >/dev/null 2>&1 || true

exit 0

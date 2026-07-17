#!/usr/bin/env bash
# Gera dist/claude-traffic-light-installer.sh: instalador auto-contido
# (hook + plugin + install.sh embutidos) pra mandar como um arquivo só.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SRC/dist"
OUT="$OUT_DIR/claude-traffic-light-installer.sh"
mkdir -p "$OUT_DIR"

{
    echo '#!/usr/bin/env bash'
    echo '# Claude Traffic Light 🚦 — instalador auto-contido (gerado por build.sh).'
    echo '# Uso: bash claude-traffic-light-installer.sh'
    echo 'set -euo pipefail'
    echo 'TMP="$(mktemp -d)"'
    echo "trap 'rm -rf \"\$TMP\"' EXIT"
    for f in claude-light-hook.sh claude-light.5s.sh install.sh; do
        delim="EOF_$(printf '%s' "$f" | tr -c 'A-Za-z0-9' '_')"
        echo "cat > \"\$TMP/$f\" <<'$delim'"
        cat "$SRC/$f"
        echo "$delim"
    done
    echo 'chmod +x "$TMP"/*.sh'
    echo 'bash "$TMP/install.sh"'
} > "$OUT"

chmod +x "$OUT"
echo "Gerado: $OUT"

#!/usr/bin/env bash
# Gera os instaladores distribuíveis em dist/:
#   - claude-traffic-light-installer.sh          (rodar no terminal)
#   - Instalar Claude Traffic Light.command      (duplo clique)
#   - claude-traffic-light.zip                   (o .command zipado — mande ESTE;
#     o zip preserva a permissão de execução, anexo solto perde)
# Todos auto-contidos: hook + plugin + install.sh embutidos via heredoc.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$SRC/dist"
SH_OUT="$OUT_DIR/claude-traffic-light-installer.sh"
CMD_OUT="$OUT_DIR/Instalar Claude Traffic Light.command"
ZIP_OUT="$OUT_DIR/claude-traffic-light.zip"
mkdir -p "$OUT_DIR"

emit_payload() {
    echo 'TMP="$(mktemp -d)"'
    echo "trap 'rm -rf \"\$TMP\"' EXIT"
    for f in claude-light-hook.sh claude-light.5s.sh install.sh; do
        local delim
        delim="EOF_$(printf '%s' "$f" | tr -c 'A-Za-z0-9' '_')"
        echo "cat > \"\$TMP/$f\" <<'$delim'"
        cat "$SRC/$f"
        echo "$delim"
    done
    echo 'chmod +x "$TMP"/*.sh'
    echo 'bash "$TMP/install.sh"'
}

{
    echo '#!/usr/bin/env bash'
    echo '# Claude Traffic Light 🚦 — instalador auto-contido (gerado por build.sh).'
    echo '# Uso: bash claude-traffic-light-installer.sh'
    echo 'set -euo pipefail'
    emit_payload
} > "$SH_OUT"
chmod +x "$SH_OUT"

{
    echo '#!/usr/bin/env bash'
    echo '# Claude Traffic Light 🚦 — instalador de duplo clique (gerado por build.sh).'
    echo 'set -euo pipefail'
    emit_payload
    echo 'echo ""'
    echo 'read -r -p "Pressione Enter para fechar esta janela..."'
} > "$CMD_OUT"
chmod +x "$CMD_OUT"

rm -f "$ZIP_OUT"
(cd "$OUT_DIR" && ditto -c -k --norsrc "Instalar Claude Traffic Light.command" "$(basename "$ZIP_OUT")")

echo "Gerados:"
echo "  $SH_OUT"
echo "  $CMD_OUT"
echo "  $ZIP_OUT"

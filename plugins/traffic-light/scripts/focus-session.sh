#!/usr/bin/env bash
# focus-session.sh <cwd>
# Traz para frente a janela do VS Code cuja pasta é <cwd>.
#
# Truque: `code <pasta>` — se a pasta já está aberta em alguma janela do
# VS Code, o VS Code foca essa janela existente em vez de abrir outra. É o
# jeito mais confiável de "ir para a sessão" sem depender de foco de aba.
# Chamado pelos itens do menu do SwiftBar (display: claude-light.30s.sh).

set -euo pipefail

CWD="${1:-}"
[ -n "$CWD" ] || exit 0

# Resolve o binário `code` (SwiftBar roda com PATH mínimo, então tenta os
# caminhos comuns antes de desistir).
CODE=""
for c in \
    "$(command -v code 2>/dev/null || true)" \
    "/usr/local/bin/code" \
    "/opt/homebrew/bin/code" \
    "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code" \
    "$HOME/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"; do
    if [ -n "$c" ] && [ -x "$c" ]; then CODE="$c"; break; fi
done

if [ -n "$CODE" ] && [ -d "$CWD" ]; then
    # Foca (ou reabre) a janela dessa pasta.
    "$CODE" "$CWD" >/dev/null 2>&1 || true
fi

# Garante que o VS Code venha para frente mesmo se o `code` acima falhar.
/usr/bin/open -a "Visual Studio Code" >/dev/null 2>&1 || true

exit 0

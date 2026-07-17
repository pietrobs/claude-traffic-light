# Claude Traffic Light 🚦

Semáforo do estado do Claude na barra de menu do Mac.

- 🟡 **Amarelo** — o Claude está rodando (qualquer instância)
- 🔴 **Vermelho** — está esperando um input seu
- 🟢 **Verde** — livre (nada rodando ou tarefa concluída)

## Como funciona

Duas camadas independentes:

1. **Detecção** — hooks do Claude Code disparam em eventos do ciclo de vida e cada instância grava seu estado em `~/.claude-traffic-light/<session_id>.state`:
   - `UserPromptSubmit` / `PreToolUse` → `running`
   - `Notification` (pede permissão / aguarda input) → `waiting`
   - `Stop` (terminou a resposta) → `done`
   - `SessionEnd` → apaga o arquivo
2. **Display** — o plugin do SwiftBar lê todos os arquivos, aplica a prioridade **vermelho > amarelo > verde** e mostra a bolinha. O hook ainda dá um "refresh" instantâneo no SwiftBar a cada mudança.

> Prioridade: se qualquer instância te espera, a luz fica vermelha — mesmo que outra ainda esteja rodando.

## Instalação

```bash
brew install --cask swiftbar     # se ainda não tiver
# abra o SwiftBar e escolha uma pasta de plugins na primeira execução
bash install.sh
```

Depois abra uma **nova** sessão do Claude Code (os hooks são lidos no início da sessão).

## Testar sem esperar o Claude

```bash
DIR=~/.claude-traffic-light
echo running > "$DIR/teste.state"   # deve ficar 🟡
echo waiting > "$DIR/teste.state"   # deve ficar 🔴
echo done    > "$DIR/teste.state"   # deve ficar 🟢
rm "$DIR/teste.state"               # volta pro estado agregado real
```

## Ajustes

- **Staleness**: no `claude-light.5s.sh`, `STALE=1800` ignora estados `running`/`waiting` de sessões que morreram sem disparar `Stop` (30 min). Reduza se quiser.
- **Trocar de display depois** (lâmpada, Luxafor etc.): basta reaproveitar a camada de detecção — a lógica de leitura dos `.state` é a mesma.

## Desinstalar

```bash
rm -rf ~/.claude-traffic-light
# remova as entradas "claude-light-hook.sh" de ~/.claude/settings.json
# remova claude-light.5s.sh da sua pasta de plugins do SwiftBar
```

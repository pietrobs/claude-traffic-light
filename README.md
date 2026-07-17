# Claude Traffic Light 🚦

Semáforo do estado do Claude Code na barra de menu do Mac.

- 🟡 **Amarelo** — o Claude está rodando (qualquer instância)
- 🔴 **Vermelho** — está esperando você (aprovação de permissão)
- 🟢 **Verde** — livre (nada rodando ou tarefa concluída)

Com som: 🔔 quando fica vermelho, 🎉 quando uma tarefa termina. Dá pra silenciar
pelo próprio menu da bolinha (🔊/🔇).

## Instalação

Requisitos: macOS + [Claude Code](https://claude.com/claude-code). O instalador
cuida do resto (instala o SwiftBar via Homebrew se precisar).

Recebeu o arquivo `claude-traffic-light-installer.sh`? Um comando só:

```bash
bash ~/Downloads/claude-traffic-light-installer.sh
```

Depois abra uma **nova** sessão do Claude Code (os hooks são lidos no início da
sessão). Pronto — a bolinha aparece na barra de menu.

O instalador é idempotente: pode rodar de novo quantas vezes quiser (útil pra
atualizar).

### A partir do repositório

```bash
./install.sh      # instala direto
./build.sh        # gera dist/claude-traffic-light-installer.sh pra distribuir
```

## Como funciona

Duas camadas independentes:

1. **Detecção** — hooks do Claude Code disparam em eventos do ciclo de vida e
   cada instância grava seu estado em `~/.claude-traffic-light/<session_id>.state`:
   - `UserPromptSubmit` / `PreToolUse` / `PostToolUse` → `running`
   - `PermissionRequest` / `Notification` → `waiting`
   - `Stop` (terminou a resposta) → `done`
   - `SessionEnd` → apaga o arquivo
2. **Display** — o plugin do SwiftBar lê todos os arquivos, aplica a prioridade
   **vermelho > amarelo > verde** e mostra a bolinha. O hook ainda dá um
   "refresh" instantâneo no SwiftBar a cada mudança.

> Prioridade: se qualquer instância te espera, a luz fica vermelha — mesmo que
> outra ainda esteja rodando.

> Por que `PermissionRequest` E `Notification`? A extensão do VSCode não dispara
> `Notification` (bug conhecido, anthropics/claude-code#28774). `PermissionRequest`
> funciona nos dois. E `PostToolUse` devolve o amarelo depois que você aprova
> uma permissão.

## Sons

| Evento | Som padrão | Variável |
|--------|-----------|----------|
| Ficou vermelho | Glass.aiff | `CLAUDE_LIGHT_SOUND` |
| Tarefa terminou | Hero.aiff | `CLAUDE_LIGHT_SOUND_DONE` |

- Silenciar/reativar: clique na bolinha → item 🔊/🔇.
- Trocar som: edite as variáveis no topo de `~/.claude-traffic-light/claude-light-hook.sh`
  (opções em `/System/Library/Sounds/`). Valor vazio = sem som.
- O som só toca na **transição** de estado (não fica repetindo).

## Testar sem esperar o Claude

```bash
DIR=~/.claude-traffic-light
echo running > "$DIR/teste.state"   # deve ficar 🟡
echo waiting > "$DIR/teste.state"   # deve ficar 🔴
echo done    > "$DIR/teste.state"   # deve ficar 🟢
rm "$DIR/teste.state"               # volta pro estado agregado real
```

## Ajustes

- **Staleness**: no `claude-light.5s.sh`, `STALE=1800` ignora estados
  `running`/`waiting` de sessões que morreram sem disparar `Stop` (30 min).
- **Limitação conhecida**: na extensão do VSCode, quando o Claude termina e fica
  esperando sua próxima mensagem, o evento `idle_prompt` não dispara — esse caso
  aparece como 🟢, não 🔴. Só prompt de permissão fica vermelho.
- **Trocar de display** (lâmpada, Luxafor etc.): reaproveite a camada de
  detecção — a lógica de leitura dos `.state` é a mesma.

## Desinstalar

```bash
./uninstall.sh
```

Remove hooks, plugin e estados. O SwiftBar em si fica (remova com
`brew uninstall --cask swiftbar` se quiser).

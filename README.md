# Claude Traffic Light 🚦

Semáforo do estado do Claude Code na barra de menu do Mac.

- 🟡 **Amarelo** — o Claude está rodando (qualquer instância)
- 🔴 **Vermelho** — está esperando você (aprovação de permissão)
- 🟢 **Verde** — livre (nada rodando ou tarefa concluída)

Com som: 🔔 quando fica vermelho, 🎉 quando uma tarefa termina. Dá pra silenciar
pelo próprio menu da bolinha (🔊/🔇).

Requisitos: macOS + [Claude Code](https://claude.com/claude-code). O setup
cuida do resto (instala o SwiftBar via Homebrew se precisar).

## Instalação como plugin do Claude Code (recomendado)

No terminal:

```bash
claude plugin marketplace add pietrobs/claude-traffic-light
claude plugin install traffic-light@claude-traffic-light
```

(ou, dentro do Claude Code: `/plugin marketplace add pietrobs/claude-traffic-light`
e `/plugin install traffic-light@claude-traffic-light`)

Depois, dentro de uma sessão do Claude Code:

```
/traffic-light:setup
```

Isso instala o SwiftBar (via Homebrew, se preciso) e coloca a bolinha na barra
de menu. Os hooks já vêm com o plugin — nada de mexer em `settings.json`.
Atualizações chegam sozinhas junto com o plugin.

Pra remover: `/traffic-light:remove` (tira a bolinha) e
`claude plugin uninstall traffic-light@claude-traffic-light` (tira os hooks).

## Instalação via zip (sem plugin)

### Recebeu o `claude-traffic-light.zip`? (duplo clique)

1. Duplo clique no zip — vira `Instalar Claude Traffic Light.command`.
2. **Clique direito** no `.command` → **Abrir** → **Abrir** de novo no aviso.
   (Só na primeira vez — o macOS bloqueia duplo clique direto em script baixado
   de fora, sem assinatura de desenvolvedor.)
3. O Terminal abre, instala tudo e avisa quando terminar.

### Recebeu o `claude-traffic-light-installer.sh`? (terminal)

```bash
bash ~/Downloads/claude-traffic-light-installer.sh
```

Depois abra uma **nova** sessão do Claude Code (os hooks são lidos no início da
sessão). Pronto — a bolinha aparece na barra de menu.

O instalador é idempotente: pode rodar de novo quantas vezes quiser (útil pra
atualizar). Esse caminho registra os hooks direto em `~/.claude/settings.json`.

> Use **um** dos dois caminhos. Se instalar pelos dois, os hooks rodam em dobro
> (inofensivo, mas desnecessário) — rode `./uninstall.sh` pra tirar a versão zip.

### A partir do repositório

```bash
./install.sh      # instala direto (caminho sem plugin)
./build.sh        # gera dist/ (installer .sh, .command e zip) pra distribuir
./uninstall.sh    # remove a versão sem plugin (hooks + bolinha)
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

No caminho **plugin**, os hooks vêm de `plugins/traffic-light/hooks/hooks.json`
e rodam direto do cache do plugin (`${CLAUDE_PLUGIN_ROOT}`). No caminho **zip**,
o `install.sh` copia o hook pra `~/.claude-traffic-light/` e registra em
`~/.claude/settings.json`. A camada de display é idêntica nos dois.

> Prioridade: se qualquer instância te espera, a luz fica vermelha — mesmo que
> outra ainda esteja rodando.

> Por que `PermissionRequest` E `Notification`? A extensão do VSCode não dispara
> `Notification` (bug conhecido, anthropics/claude-code#28774). `PermissionRequest`
> funciona nos dois. E `PostToolUse` devolve o amarelo depois que você aprova
> uma permissão.

## Sons

Três modos, escolhidos na bolinha → **Som**:

| Modo | Ficou vermelho | Tarefa terminou |
|------|----------------|-----------------|
| 🚗 Buzina (padrão) | buzina de carro (sintetizada na 1ª vez em `~/.claude-traffic-light/horn.wav`) | Hero.aiff |
| 🔔 Beep | Glass.aiff | Hero.aiff |
| 🔇 Silencioso | — | — |

- Trocar por som próprio: exporte `CLAUDE_LIGHT_SOUND` / `CLAUDE_LIGHT_SOUND_DONE`
  no ambiente (opções em `/System/Library/Sounds/`) — elas vencem o modo.
  Valor vazio = sem som.
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

- **Plugin**: `/traffic-light:remove` + `claude plugin uninstall traffic-light@claude-traffic-light`
- **Zip**: `./uninstall.sh`

O SwiftBar em si fica nos dois casos (remova com `brew uninstall --cask swiftbar`
se quiser).

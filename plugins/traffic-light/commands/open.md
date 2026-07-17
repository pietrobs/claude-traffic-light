---
description: Abre a bolinha do Claude Traffic Light na barra de menu (inicia o SwiftBar se estiver fechado)
allowed-tools: Bash
---

Open the Claude Traffic Light menu bar display:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/open-swiftbar.sh"
```

This starts SwiftBar if it is not already running (the 🚦 light appears in the menu bar). It does not install anything.

If it fails because SwiftBar is not installed, tell the user to run `/traffic-light:setup` first.

---
description: Instala o SwiftBar e a bolinha do Claude Traffic Light na barra de menu
allowed-tools: Bash
---

Run the Claude Traffic Light display setup:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/setup-swiftbar.sh"
```

This installs SwiftBar via Homebrew if needed, configures its plugin folder, copies the menu bar plugin there and launches SwiftBar. It is idempotent.

If it fails because Homebrew is missing, tell the user to install SwiftBar manually from https://swiftbar.app and run `/traffic-light:setup` again.

After it succeeds, tell the user: the hooks are already active via the plugin — the 🚦 light in the menu bar will start reacting from the NEXT Claude Code session onward.

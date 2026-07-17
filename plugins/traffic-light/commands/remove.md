---
description: Remove a bolinha do Claude Traffic Light da barra de menu (SwiftBar)
allowed-tools: Bash
---

Run the Claude Traffic Light display removal:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/remove-swiftbar.sh"
```

This removes the SwiftBar menu bar plugin and the state files in `~/.claude-traffic-light`. SwiftBar itself is kept.

After it succeeds, remind the user: to also remove the hooks, uninstall the plugin itself with `/plugin uninstall traffic-light@claude-traffic-light` (or `claude plugin uninstall traffic-light@claude-traffic-light` in the terminal).

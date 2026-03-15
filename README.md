# tmux-claude-session-manager

A tmux plugin that manages dedicated [OpenCode](https://opencode.ai) and [Claude Code](https://docs.anthropic.com/en/docs/claude-code) sessions per working directory. Pure shell -- no build step, no runtime dependencies beyond tmux and bash.

Press a leader key followed by a tool key from any tmux pane. The plugin opens (or reuses) a window running that tool in your current working directory inside a background session. Press the same combo again to jump back.

## Requirements

- [tmux](https://github.com/tmux/tmux) >= 3.0
- bash

## Installation

### With TPM (recommended)

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'd071996/tmux-claude-session-manager'
```

Then press `prefix + I` inside tmux to install.

### Manual

```sh
git clone https://github.com/d071996/tmux-claude-session-manager.git \
    ~/.tmux/plugins/tmux-claude-session-manager
```

Add to `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-claude-session-manager/claude-session-manager.tmux
```

Reload:

```sh
tmux source-file ~/.tmux.conf
```

## Default keybindings

| Keys | Action |
|---|---|
| `Ctrl-o` then `o` | Toggle OpenCode for current directory |
| `Ctrl-o` then `p` | Toggle Claude Code for current directory |

Pressing the same combo while focused on the tool window switches back to your previous session.

## Configuration

All options are set in `~/.tmux.conf` via tmux user options. Place them **before** the plugin line.

### Leader key

```tmux
set -g @tcsm-leader 'C-space'    # default: C-o
```

Any valid tmux key name works (`C-a`, `C-space`, `M-s`, etc.).

### Tool keybindings

```tmux
set -g @tcsm-opencode-key 'o'    # default: o
set -g @tcsm-claudecode-key 'c'  # default: p
```

### Tool commands

```tmux
set -g @tcsm-opencode-cmd 'opencode'   # default: opencode
set -g @tcsm-claudecode-cmd 'claude'    # default: claude
```

### Adding a new tool

No code changes required. Add the tool name to `@tcsm-tools` and set its key and command:

```tmux
set -g @tcsm-tools 'opencode,claudecode,aider'
set -g @tcsm-aider-key 'a'
set -g @tcsm-aider-cmd 'aider'
```

Reload tmux and the new tool is available at `leader + a`.

If you omit `-key`, the first character of the tool name is used.
If you omit `-cmd`, the tool name itself is used as the command.

### Full example

```tmux
# -- claude-session-manager config --
set -g @tcsm-leader 'C-space'
set -g @tcsm-tools 'opencode,claudecode,aider'
set -g @tcsm-opencode-key 'o'
set -g @tcsm-claudecode-key 'c'
set -g @tcsm-claudecode-cmd 'claude'
set -g @tcsm-aider-key 'a'
set -g @tcsm-aider-cmd 'aider'

# -- TPM --
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'd071996/tmux-claude-session-manager'
run '~/.tmux/plugins/tpm/tpm'
```

## How it works

1. On tmux startup, the plugin creates a detached session called `claude-session-manager`.
2. When you press `leader + tool key`, `scripts/toggle.sh` runs:
   - If you are already in the `claude-session-manager` session, it calls `switch-client -l` to return to your previous session.
   - Otherwise it iterates over windows in the manager session, checking `@tcsm_tool` and `@tcsm_cwd` window options to find a match.
   - If a matching window exists, it switches to it. If not, it creates a new window running the tool command in your working directory and tags it.
3. Window tags (`@tcsm_tool`, `@tcsm_cwd`) ensure lookups are exact even when multiple directories share the same basename.

## Project structure

```
tmux-claude-session-manager/
├── claude-session-manager.tmux    TPM entry point (reads config, binds keys)
├── scripts/
│   └── toggle.sh                  Toggle logic (find/create window, switch)
├── .claude/
│   └── skills/
│       └── configure-plugin.md    AI assistant skill for configuration help
└── README.md
```

## Troubleshooting

**Plugin doesn't load** -- Make sure TPM is installed and the plugin line is in `~/.tmux.conf`. Run `tmux source-file ~/.tmux.conf` to reload.

**Leader key conflict** -- Run `tmux list-keys | grep 'C-o'` to check for conflicts. Change the leader with `@tcsm-leader`.

**Tool command not found** -- Set the full path: `set -g @tcsm-opencode-cmd '/usr/local/bin/opencode'`

**Verify keybindings** -- `tmux list-keys -T tcsm`

**Check management session** -- `tmux list-windows -t claude-session-manager`

## License

MIT

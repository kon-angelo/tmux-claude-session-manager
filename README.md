# tmux-claude-session-manager

A tmux plugin that manages dedicated [OpenCode](https://opencode.ai), [Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Neovim](https://neovim.io), and other tool sessions per working directory. Pure shell -- no build step, no runtime dependencies beyond tmux and bash.

Press `Alt-t` from any tmux pane to toggle OpenCode in your current working directory. The plugin opens (or reuses) a window running the tool inside a background session. Press `Alt-t` again to jump back. Add extra quick-keys to toggle other tools (e.g. `Alt-v` for nvim). Optionally enable a leader key for multi-tool access.

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
| `Alt-t` | Toggle OpenCode for current directory |

Only `Alt-t` is registered by default. The leader key, per-tool sub-keys, and extra quick-keys are available but must be explicitly enabled (see below).

Pressing `Alt-t` while focused on the tool window switches back to your previous session.

## Configuration

All options are set in `~/.tmux.conf` via tmux user options. Place them **before** the plugin line.

### Quick key (primary keybinding)

`Alt-t` is the only keybinding registered by default. It opens OpenCode directly with a single keypress.

```tmux
set -g @tcsm-quickkey 'M-o'             # change to Alt-o (default: M-t)
set -g @tcsm-quickkey-tool 'claudecode'  # open Claude Code instead (default: opencode)
```

Set `@tcsm-quickkey` to an empty string to disable:

```tmux
set -g @tcsm-quickkey ''
```

### Extra quick-keys

Bind additional tools to their own quick-keys (no leader required). Each entry is a `tool:key` pair, comma-separated:

```tmux
set -g @tcsm-extra-quickkeys 'nvim:M-v'          # Alt-v toggles nvim
set -g @tcsm-extra-quickkeys 'nvim:M-v,aider:M-a' # multiple tools
```

### Per-tool session names

By default, all tools share the `claude-session-manager` background session. nvim defaults to its own `nvim-session-manager` session. You can override the session name for any tool:

```tmux
set -g @tcsm-nvim-session 'nvim-session-manager'       # default for nvim
set -g @tcsm-opencode-session 'claude-session-manager'  # default for others
set -g @tcsm-aider-session 'aider-session-manager'      # custom for aider
```

### Leader key (optional, disabled by default)

Enable a leader key to access multiple tools via `<leader> <tool-key>`:

```tmux
set -g @tcsm-leader 'C-o'    # not set by default
```

### Tool keybindings (used with leader key)

```tmux
set -g @tcsm-opencode-key 'o'    # default: o
set -g @tcsm-claudecode-key 'c'  # default: p
set -g @tcsm-nvim-key 'v'        # default: v
```

### Tool commands

```tmux
set -g @tcsm-opencode-cmd 'opencode'   # default: opencode
set -g @tcsm-claudecode-cmd 'claude'    # default: claude
set -g @tcsm-nvim-cmd 'nvim'            # default: nvim
```

### Adding a new tool

No code changes required. Add the tool name to `@tcsm-tools` and set its key and command:

```tmux
set -g @tcsm-tools 'opencode,claudecode,nvim,aider'
set -g @tcsm-aider-key 'a'
set -g @tcsm-aider-cmd 'aider'
```

Reload tmux and the new tool is available at `leader + a` (requires `@tcsm-leader` to be set).

To also give it a direct quick-key, use `@tcsm-extra-quickkeys`:

```tmux
set -g @tcsm-extra-quickkeys 'aider:M-a'
```

If you omit `-key`, the first character of the tool name is used.
If you omit `-cmd`, the tool name itself is used as the command.

### Full example

```tmux
# -- claude-session-manager config --
set -g @tcsm-quickkey 'M-t'              # default, shown for clarity
set -g @tcsm-quickkey-tool 'opencode'     # default, shown for clarity
set -g @tcsm-extra-quickkeys 'nvim:M-v'  # Alt-v toggles nvim
set -g @tcsm-leader 'C-space'            # opt-in: enable leader key
set -g @tcsm-tools 'opencode,claudecode,nvim,aider'
set -g @tcsm-opencode-key 'o'
set -g @tcsm-claudecode-key 'c'
set -g @tcsm-claudecode-cmd 'claude'
set -g @tcsm-nvim-key 'v'
set -g @tcsm-aider-key 'a'
set -g @tcsm-aider-cmd 'aider'

# -- TPM --
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'd071996/tmux-claude-session-manager'
run '~/.tmux/plugins/tpm/tpm'
```

## How it works

1. On tmux startup, the plugin creates detached background sessions for managing tool windows. By default `claude-session-manager` is used; nvim uses `nvim-session-manager`. Custom session names can be set per tool.
2. When you press `Alt-t` (or another quick-key, or `leader + tool key`), `scripts/toggle.sh` runs:
   - It resolves the target session for the tool (via `@tcsm-<tool>-session` or built-in defaults).
   - If you are already in that managed session, it calls `switch-client` to return to your previous session.
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

**Verify keybindings** -- `tmux list-keys -T tcsm` and `tmux list-keys -T root | grep toggle`

**Check management sessions** -- `tmux list-sessions | grep session-manager`

**Check windows in a session** -- `tmux list-windows -t claude-session-manager` or `tmux list-windows -t nvim-session-manager`

## License

MIT

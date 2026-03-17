# Skill: Configure tmux-claude-session-manager

## When to use

Use this skill when the user wants to:
- Configure the tmux-claude-session-manager plugin
- Change keybindings (leader key or per-tool keys)
- Add a new tool to the plugin
- Change which command a tool runs
- Troubleshoot the plugin not working

## Context

tmux-claude-session-manager is a TPM plugin written in pure bash. It manages a detached tmux session called `claude-session-manager` that holds tool windows (OpenCode, Claude Code, etc.) organized by working directory.

### Architecture (2 files)

- **`claude-session-manager.tmux`** -- TPM entry point. Reads tmux user options, ensures the background session exists, binds the leader key to the `tcsm` key table, and iterates `@tcsm-tools` to bind each tool's key.
- **`scripts/toggle.sh`** -- Called by keybindings at runtime. Receives the tool name, caller's working directory, and caller's session name as arguments. Finds or creates a window in the manager session, or switches back if already there.

### How keybindings work

By default, only a single **quick-key** (`Alt-q` / `M-q`) is registered. It directly calls `toggle.sh` to open OpenCode for the caller's working directory. The quick-key's key and tool are configurable via `@tcsm-quickkey` and `@tcsm-quickkey-tool`.

Optionally, users can enable a **leader key** (`@tcsm-leader`). When set, the plugin creates a custom tmux key table called `tcsm`. The leader key (bound in the `root` table) switches into this table. Each tool key is bound inside `tcsm` and calls:

```
scripts/toggle.sh <tool> '#{pane_current_path}' '#{session_name}'
```

tmux substitutes the format variables before execution, so the script receives the caller's actual working directory and session name.

### Window identification

Each managed window has two window-level options:
- `@tcsm_tool` -- tool name (e.g. `opencode`)
- `@tcsm_cwd` -- absolute path to the working directory

`toggle.sh` iterates `tmux list-windows` and checks these options to find a match. This is exact even when directories share the same basename.

### Configuration options (set in `~/.tmux.conf`)

| tmux option | Default | Description |
|---|---|---|
| `@tcsm-leader` | *(empty)* | Leader key to enter the plugin key table (disabled by default) |
| `@tcsm-quickkey` | `M-q` | Direct key to open a tool (no leader needed). Empty to disable. |
| `@tcsm-quickkey-tool` | `opencode` | Which tool the quick-key opens |
| `@tcsm-tools` | `opencode,claudecode` | Comma-separated list of tool names |
| `@tcsm-<tool>-key` | first char of tool name | Key for the tool (after leader) |
| `@tcsm-<tool>-cmd` | tool name | Shell command to launch the tool |

Built-in defaults for the two shipped tools:
- `opencode`: key `o`, command `opencode`
- `claudecode`: key `p`, command `claude`

## How to change the leader key

The leader key is disabled by default. Enable it to access multiple tools via `<leader> <tool-key>`:

Edit `~/.tmux.conf`:

```tmux
set -g @tcsm-leader 'C-space'
```

Reload: `tmux source-file ~/.tmux.conf`

## How to change or disable the quick-key

The quick-key opens a tool with a single keypress (no leader). Default: `M-q` (Alt+q) opens `opencode`.

```tmux
set -g @tcsm-quickkey 'M-o'             # change to Alt+o
set -g @tcsm-quickkey-tool 'claudecode'  # open Claude Code instead
```

To disable the quick-key entirely:

```tmux
set -g @tcsm-quickkey ''
```

## How to change a tool keybinding

```tmux
set -g @tcsm-opencode-key 'i'
set -g @tcsm-claudecode-key 'c'
```

## How to change the command a tool runs

```tmux
set -g @tcsm-opencode-cmd '/usr/local/bin/opencode'
set -g @tcsm-claudecode-cmd 'npx @anthropic/claude-code'
```

## How to add a new tool (no code changes needed)

1. Add the tool name to the tools list:

```tmux
set -g @tcsm-tools 'opencode,claudecode,aider'
```

2. Optionally set its key and command (defaults to first character / tool name):

```tmux
set -g @tcsm-aider-key 'a'
set -g @tcsm-aider-cmd 'aider'
```

3. Reload tmux config.

## Troubleshooting

### Plugin not loading
- Ensure TPM is installed and the plugin line is in `~/.tmux.conf`
- Run `tmux source-file ~/.tmux.conf`
- Check `claude-session-manager.tmux` is executable: `chmod +x claude-session-manager.tmux`

### Keybindings not working
- Check for leader key conflicts: `tmux list-keys | grep '<your-leader>'`
- Verify the key table: `tmux list-keys -T tcsm`
- Check that `scripts/toggle.sh` is executable: `chmod +x scripts/toggle.sh`

### Tool window not opening
- Run `scripts/toggle.sh <tool> /your/cwd test-session` manually to see errors
- Ensure the tool command is on `$PATH`
- Check the session: `tmux has-session -t claude-session-manager`

### Window reuse not working
- Verify window tags: `tmux show-options -wqv -t <window_id> @tcsm_tool`
- Paths must match exactly (no trailing slash differences)

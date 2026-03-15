#!/usr/bin/env bash
# toggle.sh - Toggle a tool session for the current working directory.
#
# Usage: toggle.sh <tool> <cwd> <session>
#
# If the caller is already in the manager session, switches back.
# Otherwise finds or creates a window for the tool+cwd pair and switches to it.

set -euo pipefail

SESSION_NAME="claude-session-manager"

TOOL_NAME="${1:?Usage: toggle.sh <tool> <cwd> <session>}"
CURRENT_CWD="${2:?Usage: toggle.sh <tool> <cwd> <session>}"
CURRENT_SESSION="${3:?Usage: toggle.sh <tool> <cwd> <session>}"

# -------------------------------------------------------------------
# If already in the manager session, go back to the previous session.
# -------------------------------------------------------------------
if [ "$CURRENT_SESSION" = "$SESSION_NAME" ]; then
    tmux switch-client -l
    exit 0
fi

# -------------------------------------------------------------------
# Ensure the management session exists.
# -------------------------------------------------------------------
if ! tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
    tmux new-session -d -s "$SESSION_NAME"
fi

# -------------------------------------------------------------------
# Look for an existing window matching this tool + working directory.
# Each managed window is tagged with @tcsm_tool and @tcsm_cwd options.
# -------------------------------------------------------------------
target_window=""
window_ids=$(tmux list-windows -t "$SESSION_NAME" -F '#{window_id}' 2>/dev/null || true)

for window_id in $window_ids; do
    w_tool=$(tmux show-options -wqv -t "$window_id" @tcsm_tool 2>/dev/null || true)
    w_cwd=$(tmux show-options -wqv -t "$window_id" @tcsm_cwd 2>/dev/null || true)
    if [ "$w_tool" = "$TOOL_NAME" ] && [ "$w_cwd" = "$CURRENT_CWD" ]; then
        target_window="$window_id"
        break
    fi
done

# -------------------------------------------------------------------
# Create a new window if none was found.
# -------------------------------------------------------------------
if [ -z "$target_window" ]; then
    # Resolve the shell command for this tool.
    tool_cmd=$(tmux show-options -gqv "@tcsm-${TOOL_NAME}-cmd" 2>/dev/null || true)
    if [ -z "$tool_cmd" ]; then
        case "$TOOL_NAME" in
            opencode)   tool_cmd="opencode" ;;
            claudecode) tool_cmd="claude" ;;
            *)          tool_cmd="$TOOL_NAME" ;;
        esac
    fi

    base=$(basename "$CURRENT_CWD")
    target_window=$(tmux new-window -t "$SESSION_NAME" \
        -n "${TOOL_NAME}:${base}" \
        -c "$CURRENT_CWD" \
        -d -P -F '#{window_id}' \
        "$tool_cmd")

    # Tag the window for later lookup.
    tmux set-option -w -t "$target_window" @tcsm_tool "$TOOL_NAME"
    tmux set-option -w -t "$target_window" @tcsm_cwd "$CURRENT_CWD"
fi

# -------------------------------------------------------------------
# Focus the target window and switch the client to the manager session.
# -------------------------------------------------------------------
tmux select-window -t "$target_window"
tmux switch-client -t "$SESSION_NAME"

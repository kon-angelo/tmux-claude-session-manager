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
# If already in the manager session, go back to the source session.
# Use the explicitly stored @tcsm_source_session rather than
# switch-client -l, which is unreliable from run-shell context.
# Try to select the window in the target session whose CWD matches
# the current managed window, so the user lands in the right context.
# -------------------------------------------------------------------
if [ "$CURRENT_SESSION" = "$SESSION_NAME" ]; then
    # Get the CWD and source session associated with this managed window.
    current_win_id=$(tmux display-message -p '#{window_id}')
    target_cwd=$(tmux show-options -wqv -t "$current_win_id" @tcsm_cwd 2>/dev/null || true)
    : "${target_cwd:=$CURRENT_CWD}"
    source_session=$(tmux show-options -wqv -t "$current_win_id" @tcsm_source_session 2>/dev/null || true)

    # Fall back to tmux's last-session tracking (requires tmux >= 3.1).
    if [ -z "$source_session" ]; then
        source_session=$(tmux display-message -p '#{client_last_session}')
    fi

    if [ -z "$source_session" ]; then
        # Nothing to return to.
        exit 0
    fi

    # Find a window in the target session with a pane matching this CWD.
    if [ -n "$target_cwd" ]; then
        match=$(tmux list-panes -s -t "$source_session" \
            -F '#{window_id} #{pane_current_path}' 2>/dev/null | \
            while IFS= read -r line; do
                win_id="${line%% *}"
                pane_path="${line#* }"
                if [ "$pane_path" = "$target_cwd" ]; then
                    echo "$win_id"
                    break
                fi
            done)

        if [ -n "$match" ]; then
            tmux select-window -t "$match"
        fi
    fi

    tmux switch-client -t "$source_session"
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
#
# First try an exact CWD match.  If none is found, fall back to the
# most specific (longest path) parent directory that already has a
# window for this tool — so calling tcsm from a subdirectory of an
# existing session reuses that session instead of creating a new one.
# -------------------------------------------------------------------
target_window=""
best_parent_window=""
best_parent_cwd=""
window_ids=$(tmux list-windows -t "$SESSION_NAME" -F '#{window_id}' 2>/dev/null || true)

for window_id in $window_ids; do
    w_tool=$(tmux show-options -wqv -t "$window_id" @tcsm_tool 2>/dev/null || true)
    w_cwd=$(tmux show-options -wqv -t "$window_id" @tcsm_cwd 2>/dev/null || true)
    if [ "$w_tool" = "$TOOL_NAME" ]; then
        if [ "$w_cwd" = "$CURRENT_CWD" ]; then
            target_window="$window_id"
            break
        fi
        # Check if CWD is a subdirectory of this window's directory.
        case "$CURRENT_CWD" in
            "$w_cwd"/*)
                if [ -z "$best_parent_cwd" ] || [ ${#w_cwd} -gt ${#best_parent_cwd} ]; then
                    best_parent_window="$window_id"
                    best_parent_cwd="$w_cwd"
                fi
                ;;
        esac
    fi
done

# Fall back to the most specific parent directory match.
if [ -z "$target_window" ] && [ -n "$best_parent_window" ]; then
    target_window="$best_parent_window"
fi

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
    # Create window with a shell (not the tool directly) so that job
    # control works — Ctrl-Z can suspend the tool and return to the shell.
    target_window=$(tmux new-window -t "$SESSION_NAME" \
        -n "${TOOL_NAME}:${base}" \
        -c "$CURRENT_CWD" \
        -d -P -F '#{window_id}')
    tmux send-keys -t "$target_window" "$tool_cmd" Enter

    # Tag the window for later lookup.
    tmux set-option -w -t "$target_window" @tcsm_tool "$TOOL_NAME"
    tmux set-option -w -t "$target_window" @tcsm_cwd "$CURRENT_CWD"
fi

# -------------------------------------------------------------------
# Remember which session (and window) we came from so the toggle-back
# can return to the right place without relying on switch-client -l.
# -------------------------------------------------------------------
tmux set-option -w -t "$target_window" @tcsm_source_session "$CURRENT_SESSION"

# -------------------------------------------------------------------
# Focus the target window and switch the client to the manager session.
# -------------------------------------------------------------------
tmux select-window -t "$target_window"
tmux switch-client -t "$SESSION_NAME"

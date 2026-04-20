#!/usr/bin/env bash
# retag.sh - Re-tag windows in management sessions after tmux server restart.
#
# Session restore plugins (tmux-resurrect, tmux-continuum) restore windows and
# their names but NOT custom window options (@tcsm_tool, @tcsm_cwd).  This
# script scans every window in each management session and re-applies the tags
# by parsing the window name (format "tool:basename") and reading the pane's
# current working directory.
#
# Called once from claude-session-manager.tmux at plugin load time.
# Idempotent: windows that are already tagged are skipped.

set -euo pipefail

DEFAULT_SESSION="claude-session-manager"

# -----------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------
get_tmux_option() {
    local option="$1"
    local default="$2"
    local value
    value=$(tmux show-options -gqv "$option" 2>/dev/null || true)
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

default_session_for() {
    case "$1" in
        nvim) echo "nvim-session-manager" ;;
        *)    echo "$DEFAULT_SESSION" ;;
    esac
}

# -----------------------------------------------------------------
# Collect every unique management session name (same logic as the
# main plugin file).
# -----------------------------------------------------------------
declare -A sessions_to_scan

add_session() {
    local tool="$1"
    local session
    session=$(get_tmux_option "@tcsm-${tool}-session" "$(default_session_for "$tool")")
    sessions_to_scan["$session"]=1
}

# Well-known defaults.
sessions_to_scan["claude-session-manager"]=1
sessions_to_scan["nvim-session-manager"]=1

# Configured tools.
configured_tools=$(get_tmux_option "@tcsm-tools" "opencode,claudecode")
IFS=',' read -ra tool_list <<< "$configured_tools"
for t in "${tool_list[@]}"; do
    t=$(echo "$t" | tr -d ' ')
    [ -n "$t" ] && add_session "$t"
done

# Quick-key tool.
qk_tool=$(get_tmux_option "@tcsm-quickkey-tool" "opencode")
add_session "$qk_tool"

# Extra quick-key tools.
extra_qk=$(get_tmux_option "@tcsm-extra-quickkeys" "")
if [ -n "$extra_qk" ]; then
    IFS=',' read -ra eq_list <<< "$extra_qk"
    for pair in "${eq_list[@]}"; do
        pair=$(echo "$pair" | tr -d ' ')
        eq_tool="${pair%%:*}"
        [ -n "$eq_tool" ] && add_session "$eq_tool"
    done
fi

# -----------------------------------------------------------------
# Scan each management session and re-tag untagged windows.
# -----------------------------------------------------------------
for session in "${!sessions_to_scan[@]}"; do
    tmux has-session -t "$session" 2>/dev/null || continue

    window_data=$(tmux list-windows -t "$session" \
        -F '#{window_id} #{window_name}' 2>/dev/null || true)
    [ -z "$window_data" ] && continue

    while IFS= read -r line; do
        win_id="${line%% *}"
        win_name="${line#* }"

        # Skip windows that are already tagged.
        existing_tool=$(tmux show-options -wqv -t "$win_id" @tcsm_tool 2>/dev/null || true)
        if [ -n "$existing_tool" ]; then
            continue
        fi

        # Parse the window name.  Expected format: "tool:basename"
        # (e.g. "opencode:my-project").  Skip windows that don't match.
        case "$win_name" in
            *:*)
                tool_name="${win_name%%:*}"
                ;;
            *)
                continue
                ;;
        esac

        [ -z "$tool_name" ] && continue

        # Read the pane's actual current working directory.
        pane_cwd=$(tmux display-message -t "$win_id" -p '#{pane_current_path}' 2>/dev/null || true)
        [ -z "$pane_cwd" ] && continue

        # Re-apply the tags.
        tmux set-option -w -t "$win_id" @tcsm_tool "$tool_name"
        tmux set-option -w -t "$win_id" @tcsm_cwd "$pane_cwd"
    done <<< "$window_data"
done

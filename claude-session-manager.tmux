#!/usr/bin/env bash
# claude-session-manager.tmux - TPM entry point.
#
# Sourced by TPM on tmux startup. Sets up the management session(s) and
# keybindings. No build step required -- pure shell.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOGGLE="$CURRENT_DIR/scripts/toggle.sh"

# -----------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------

# Read a tmux user option, returning a default if unset.
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

# Return the default key for a built-in tool name.
default_key_for() {
    case "$1" in
        opencode)   echo "o" ;;
        claudecode) echo "p" ;;
        nvim)       echo "v" ;;
        *)          echo "${1:0:1}" ;;  # first character
    esac
}

# Return the default command for a built-in tool name.
default_cmd_for() {
    case "$1" in
        opencode)   echo "opencode" ;;
        claudecode) echo "claude" ;;
        nvim)       echo "nvim" ;;
        *)          echo "$1" ;;
    esac
}

# Return the default session name for a built-in tool name.
default_session_for() {
    case "$1" in
        nvim) echo "nvim-session-manager" ;;
        *)    echo "claude-session-manager" ;;
    esac
}

# -----------------------------------------------------------------
# Read configuration
# -----------------------------------------------------------------

leader=$(get_tmux_option "@tcsm-leader" '')
tools=$(get_tmux_option "@tcsm-tools" "opencode,claudecode")

# Quick-key: a single key in the root table that opens a tool directly
# (no leader required). This is the primary keybinding registered by default.
# Set to empty string to disable.
quickkey=$(get_tmux_option "@tcsm-quickkey" 'M-t')
# Which tool the quick-key opens (defaults to opencode).
quickkey_tool=$(get_tmux_option "@tcsm-quickkey-tool" "opencode")

# Additional quick-keys: comma-separated list of tool:key pairs.
# Example: "nvim:M-v,aider:M-a"
# These are bound in addition to the single @tcsm-quickkey above.
extra_quickkeys=$(get_tmux_option "@tcsm-extra-quickkeys" '')

# -----------------------------------------------------------------
# Ensure the background management sessions exist.
# Each tool can use its own session via @tcsm-<tool>-session.
# -----------------------------------------------------------------

# Collect all unique session names that need to exist.
declare -A seen_sessions
all_tools="$tools"

# Include the quickkey tool and any extra-quickkey tools in the session list.
ensure_session() {
    local tool="$1"
    local session
    session=$(get_tmux_option "@tcsm-${tool}-session" "$(default_session_for "$tool")")
    if [ -z "${seen_sessions[$session]+_}" ]; then
        seen_sessions["$session"]=1
        if ! tmux has-session -t "$session" 2>/dev/null; then
            tmux new-session -d -s "$session"
        fi
    fi
}

# Ensure sessions for all configured tools.
IFS=',' read -ra tool_list <<< "$all_tools"
for tool in "${tool_list[@]}"; do
    tool=$(echo "$tool" | tr -d ' ')
    [ -z "$tool" ] && continue
    ensure_session "$tool"
done

# Ensure session for the quickkey tool.
if [ -n "$quickkey" ] && [ -n "$quickkey_tool" ]; then
    ensure_session "$quickkey_tool"
fi

# Ensure sessions for extra quickkey tools.
if [ -n "$extra_quickkeys" ]; then
    IFS=',' read -ra eq_list <<< "$extra_quickkeys"
    for pair in "${eq_list[@]}"; do
        pair=$(echo "$pair" | tr -d ' ')
        eq_tool="${pair%%:*}"
        [ -n "$eq_tool" ] && ensure_session "$eq_tool"
    done
fi

# -----------------------------------------------------------------
# Re-tag windows that lost their @tcsm_* options after a tmux server
# restart (e.g. tmux-resurrect/tmux-continuum restore).
# -----------------------------------------------------------------
"$CURRENT_DIR/scripts/retag.sh"

# -----------------------------------------------------------------
# Clean up any previous bindings from this plugin.
# Remove all keys in the tcsm table and any root-table key that
# pointed at the tcsm table (handles leader key changes on reload).
# -----------------------------------------------------------------

while IFS= read -r line; do
    # Each line looks like: bind-key -T root <key> switch-client -T tcsm
    # list-keys double-escapes backslashes (C-\\ instead of C-\), so unescape.
    key=$(echo "$line" | awk '{print $4}' | sed 's/\\\\/\\/g')
    [ -n "$key" ] && tmux unbind-key -T root "$key" 2>/dev/null || true
done < <(tmux list-keys -T root 2>/dev/null | grep 'switch-client -T tcsm')

# Remove root-table quick-key bindings (those that call toggle.sh directly).
while IFS= read -r line; do
    key=$(echo "$line" | awk '{print $4}' | sed 's/\\\\/\\/g')
    [ -n "$key" ] && tmux unbind-key -T root "$key" 2>/dev/null || true
done < <(tmux list-keys -T root 2>/dev/null | grep "toggle\.sh")

# Wipe the entire tcsm key table so stale tool bindings don't linger.
while IFS= read -r line; do
    key=$(echo "$line" | awk '{print $4}' | sed 's/\\\\/\\/g')
    [ -n "$key" ] && tmux unbind-key -T tcsm "$key" 2>/dev/null || true
done < <(tmux list-keys -T tcsm 2>/dev/null)

# -----------------------------------------------------------------
# Bind the leader key to enter the plugin key table (optional).
# The leader key is not registered by default. Set @tcsm-leader to
# enable it (e.g. C-o). When enabled, per-tool keys are bound in
# the tcsm key table so that <leader> <key> opens a tool.
# -----------------------------------------------------------------

if [ -n "$leader" ]; then
    tmux bind-key -T root "$leader" switch-client -T tcsm

    # For each tool, bind its key in the tcsm key table.
    IFS=',' read -ra tool_list <<< "$tools"
    for tool in "${tool_list[@]}"; do
        tool=$(echo "$tool" | tr -d ' ')   # trim whitespace
        [ -z "$tool" ] && continue

        key=$(get_tmux_option "@tcsm-${tool}-key" "$(default_key_for "$tool")")

        tmux bind-key -T tcsm "$key" \
            run-shell "$TOGGLE $tool '#{pane_current_path}' '#{session_name}'"
    done
fi

# -----------------------------------------------------------------
# Bind the quick-key directly in the root table (no leader needed)
# -----------------------------------------------------------------

if [ -n "$quickkey" ]; then
    tmux bind-key -T root "$quickkey" \
        run-shell "$TOGGLE $quickkey_tool '#{pane_current_path}' '#{session_name}'"
fi

# -----------------------------------------------------------------
# Bind extra quick-keys directly in the root table.
# Format: "tool:key,tool:key,..."  e.g. "nvim:M-v,aider:M-a"
# -----------------------------------------------------------------

if [ -n "$extra_quickkeys" ]; then
    IFS=',' read -ra eq_list <<< "$extra_quickkeys"
    for pair in "${eq_list[@]}"; do
        pair=$(echo "$pair" | tr -d ' ')
        [ -z "$pair" ] && continue
        eq_tool="${pair%%:*}"
        eq_key="${pair#*:}"
        [ -z "$eq_tool" ] || [ -z "$eq_key" ] && continue

        tmux bind-key -T root "$eq_key" \
            run-shell "$TOGGLE $eq_tool '#{pane_current_path}' '#{session_name}'"
    done
fi

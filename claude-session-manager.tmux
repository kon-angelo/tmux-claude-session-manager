#!/usr/bin/env bash
# claude-session-manager.tmux - TPM entry point.
#
# Sourced by TPM on tmux startup. Sets up the management session and
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
        *)          echo "${1:0:1}" ;;  # first character
    esac
}

# Return the default command for a built-in tool name.
default_cmd_for() {
    case "$1" in
        opencode)   echo "opencode" ;;
        claudecode) echo "claude" ;;
        *)          echo "$1" ;;
    esac
}

# -----------------------------------------------------------------
# Read configuration
# -----------------------------------------------------------------

leader=$(get_tmux_option "@tcsm-leader" 'C-o')
tools=$(get_tmux_option "@tcsm-tools" "opencode,claudecode")

# -----------------------------------------------------------------
# Ensure the background management session exists
# -----------------------------------------------------------------

if ! tmux has-session -t "claude-session-manager" 2>/dev/null; then
    tmux new-session -d -s "claude-session-manager"
fi

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

# Wipe the entire tcsm key table so stale tool bindings don't linger.
while IFS= read -r line; do
    key=$(echo "$line" | awk '{print $4}' | sed 's/\\\\/\\/g')
    [ -n "$key" ] && tmux unbind-key -T tcsm "$key" 2>/dev/null || true
done < <(tmux list-keys -T tcsm 2>/dev/null)

# -----------------------------------------------------------------
# Bind the leader key to enter the plugin key table
# -----------------------------------------------------------------

tmux bind-key -T root "$leader" switch-client -T tcsm

# -----------------------------------------------------------------
# For each tool, bind its key in the tcsm key table
# -----------------------------------------------------------------

IFS=',' read -ra tool_list <<< "$tools"
for tool in "${tool_list[@]}"; do
    tool=$(echo "$tool" | tr -d ' ')   # trim whitespace
    [ -z "$tool" ] && continue

    key=$(get_tmux_option "@tcsm-${tool}-key" "$(default_key_for "$tool")")

    tmux bind-key -T tcsm "$key" \
        run-shell "$TOGGLE $tool '#{pane_current_path}' '#{session_name}'"
done

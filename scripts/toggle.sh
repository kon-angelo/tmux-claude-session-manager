#!/usr/bin/env bash
# toggle.sh - Toggle a tool session for the current working directory.
#
# Usage: toggle.sh <tool> <cwd> <session>
#
# If the caller is already in a managed session, switches back.
# Otherwise finds or creates a window for the tool+cwd pair and switches to it.
#
# Each tool can use its own tmux session via the @tcsm-<tool>-session option.
# Tools without a custom session use "claude-session-manager" by default.

set -euo pipefail

DEFAULT_SESSION="claude-session-manager"

TOOL_NAME="${1:?Usage: toggle.sh <tool> <cwd> <session>}"
CURRENT_CWD="${2:?Usage: toggle.sh <tool> <cwd> <session>}"
CURRENT_SESSION="${3:?Usage: toggle.sh <tool> <cwd> <session>}"

# -------------------------------------------------------------------
# Resolve the session name for this tool.
# -------------------------------------------------------------------
default_session_for() {
    case "$1" in
        nvim) echo "nvim-session-manager" ;;
        *)    echo "$DEFAULT_SESSION" ;;
    esac
}

SESSION_NAME=$(tmux show-options -gqv "@tcsm-${TOOL_NAME}-session" 2>/dev/null || true)
if [ -z "$SESSION_NAME" ]; then
    SESSION_NAME=$(default_session_for "$TOOL_NAME")
fi

# -------------------------------------------------------------------
# Collect all managed session names so we can distinguish them from
# normal user sessions.  This is used to skip over managed sessions
# when resolving the "back" target.
# -------------------------------------------------------------------
declare -A MANAGED_SESSIONS
collect_managed_session() {
    local tool="$1"
    local s
    s=$(tmux show-options -gqv "@tcsm-${tool}-session" 2>/dev/null || true)
    [ -z "$s" ] && s=$(default_session_for "$tool")
    MANAGED_SESSIONS["$s"]=1
}

# Always include the well-known defaults.
MANAGED_SESSIONS["claude-session-manager"]=1
MANAGED_SESSIONS["nvim-session-manager"]=1

# Include sessions for all configured tools.
configured_tools=$(tmux show-options -gqv "@tcsm-tools" 2>/dev/null || true)
: "${configured_tools:=opencode,claudecode}"
IFS=',' read -ra _tool_list <<< "$configured_tools"
for _t in "${_tool_list[@]}"; do
    _t=$(echo "$_t" | tr -d ' ')
    [ -n "$_t" ] && collect_managed_session "$_t"
done

# Include the quickkey tool.
qk_tool=$(tmux show-options -gqv "@tcsm-quickkey-tool" 2>/dev/null || true)
: "${qk_tool:=opencode}"
collect_managed_session "$qk_tool"

# Include extra-quickkey tools.
extra_qk=$(tmux show-options -gqv "@tcsm-extra-quickkeys" 2>/dev/null || true)
if [ -n "$extra_qk" ]; then
    IFS=',' read -ra _eq_list <<< "$extra_qk"
    for _pair in "${_eq_list[@]}"; do
        _pair=$(echo "$_pair" | tr -d ' ')
        _eq_tool="${_pair%%:*}"
        [ -n "$_eq_tool" ] && collect_managed_session "$_eq_tool"
    done
fi

is_managed_session() {
    [ -n "${MANAGED_SESSIONS[$1]+_}" ]
}

# -------------------------------------------------------------------
# If already in the target managed session, go back to the source
# session. Use the explicitly stored @tcsm_source_session rather than
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

    # Follow the source-session chain past any managed sessions so we
    # always land in a normal user session, not another tool session.
    _depth=0
    while is_managed_session "$source_session" && [ $_depth -lt 10 ]; do
        _depth=$((_depth + 1))
        # Find the source session stored on the active window of that
        # managed session.
        _active_win=$(tmux display-message -t "$source_session" -p '#{window_id}' 2>/dev/null || true)
        _next=""
        if [ -n "$_active_win" ]; then
            _next=$(tmux show-options -wqv -t "$_active_win" @tcsm_source_session 2>/dev/null || true)
        fi
        if [ -z "$_next" ] || [ "$_next" = "$source_session" ]; then
            break  # avoid infinite loops; use what we have
        fi
        source_session="$_next"
    done

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
            nvim)       tool_cmd="nvim" ;;
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
#
# If we are switching from one managed session to another, propagate
# the original non-managed source session instead of storing the
# intermediate managed session.
# -------------------------------------------------------------------
resolved_source="$CURRENT_SESSION"
if is_managed_session "$resolved_source"; then
    # We are in a managed session — look up its stored source to find
    # the original user session.
    _src_win=$(tmux display-message -p '#{window_id}' 2>/dev/null || true)
    _depth=0
    while is_managed_session "$resolved_source" && [ $_depth -lt 10 ]; do
        _depth=$((_depth + 1))
        _prev=""
        if [ -n "$_src_win" ]; then
            _prev=$(tmux show-options -wqv -t "$_src_win" @tcsm_source_session 2>/dev/null || true)
        fi
        if [ -z "$_prev" ] || [ "$_prev" = "$resolved_source" ]; then
            break
        fi
        # Before following the chain, resolve the active window of the
        # next session so we can read its source.
        _src_win=$(tmux display-message -t "$_prev" -p '#{window_id}' 2>/dev/null || true)
        resolved_source="$_prev"
    done
fi
tmux set-option -w -t "$target_window" @tcsm_source_session "$resolved_source"

# -------------------------------------------------------------------
# Focus the target window and switch the client to the manager session.
# -------------------------------------------------------------------
tmux select-window -t "$target_window"
tmux switch-client -t "$SESSION_NAME"

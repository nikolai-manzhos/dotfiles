#!/bin/sh
# Records the state of the coding agent running in this tmux pane as the pane
# option @agent_state, which agent-status.conf renders in the status bar.
# Called by Claude Code hooks and the opencode plugin.
#
# Usage: agent-state.sh idle|working|waiting|done|settle|clear

[ -n "$TMUX_PANE" ] || exit 0

pane="$TMUX_PANE"

case "$1" in
  idle|working|waiting)
    tmux set -p -t "$pane" @agent_state "$1"
    ;;
  done)
    # Only mark the run as unseen when the pane isn't already in front of you.
    tmux if -F -t "$pane" '#{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}}' \
      "set -p -t $pane @agent_state idle" \
      "set -p -t $pane @agent_state done"
    ;;
  settle)
    # Recovers from interrupted runs without hiding an unseen done/waiting.
    tmux if -F -t "$pane" '#{==:#{@agent_state},working}' \
      "set -p -t $pane @agent_state idle"
    ;;
  clear)
    tmux set -pu -t "$pane" @agent_state
    ;;
esac 2>/dev/null

exit 0

#!/bin/sh
# Records the state of the coding agent running in this tmux pane as the pane
# option @agent_state, which agent-status.conf renders in the status bar.
# Called by Claude Code hooks and the opencode plugin.
#
# Usage: agent-state.sh idle|working|waiting|done|failed|settle|clear
#        agent-state.sh prompt   (Claude Code UserPromptSubmit; hook JSON on stdin)

[ -n "$TMUX_PANE" ] || exit 0

pane="$TMUX_PANE"
end_turn="set -pu -t $pane @agent_turn"

size() {
  if [ -f "$1" ]; then wc -c <"$1"; else echo 0; fi
}

# Claude Code runs no hook when you interrupt it, so this polls once a second
# while the turn (@agent_turn) lasts:
#   - Once Claude has started replying, an interrupt writes a marker to the
#     transcript (also when you press Esc at a permission prompt or question).
#   - Before that, it leaves no trace, but its spinner stops: a "working" pane
#     whose screen hasn't changed for 3 seconds was interrupted.
watch_turn() {
  transcript="$1"
  turn="$2"
  # Checked again inside tmux, so a hook that ends the turn meanwhile wins; the
  # loop then exits once the turn is over.
  interrupted="set -p -t $pane @agent_state idle ; set -pu -t $pane @agent_turn"
  # A transcript entry of its own; copies inside logged API requests don't count.
  marker='"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user'
  offset=$(($(size "$transcript")))
  screen=""
  still=0
  while :; do
    set -- $(tmux display -p -t "$pane" '#{@agent_turn} #{@agent_state}')
    [ "$1" = "$turn" ] || return

    now=$(($(size "$transcript")))
    if [ "$now" -gt "$offset" ]; then
      if tail -c +"$((offset + 1))" "$transcript" | grep -qF "$marker"; then
        tmux if -F -t "$pane" "#{==:#{@agent_turn},$turn}" "$interrupted"
        continue
      fi
      # Overlap reads so a marker written across two polls isn't missed.
      offset=$((now - 64))
    fi

    if [ "$2" = working ]; then
      last="$screen"
      screen="$(tmux capture-pane -p -t "$pane" | cksum)"
      if [ "$screen" = "$last" ]; then still=$((still + 1)); else still=0; fi
      if [ "$still" -ge 3 ]; then
        tmux if -F -t "$pane" "#{&&:#{==:#{@agent_turn},$turn},#{==:#{@agent_state},working}}" "$interrupted"
        continue
      fi
    else
      screen=""
      still=0
    fi
    sleep 1
  done
}

case "$1" in
  idle|working|waiting)
    tmux set -p -t "$pane" @agent_state "$1"
    ;;
  prompt)
    transcript="$(sed -n 's/.*"transcript_path" *: *"\([^"]*\)".*/\1/p')"
    turn="$$.$(date +%s)"
    tmux set -p -t "$pane" @agent_state working \; set -p -t "$pane" @agent_turn "$turn"
    if [ -n "$transcript" ]; then
      watch_turn "$transcript" "$turn" </dev/null >/dev/null 2>&1 &
    fi
    ;;
  done)
    # Only mark the run as seen when the pane is in a focused tmux client. An
    # attached client may still be in a background terminal window.
    tmux if -F -t "$pane" '#{&&:#{pane_active},#{&&:#{window_active},#{&&:#{session_attached},#{m:*focused*,#{client_flags}}}}}' \
      "set -p -t $pane @agent_state idle" \
      "set -p -t $pane @agent_state done" \; $end_turn
    ;;
  failed)
    tmux set -p -t "$pane" @agent_state waiting \; $end_turn
    ;;
  settle)
    # Recovers from interrupted runs without hiding an unseen done/waiting.
    tmux if -F -t "$pane" '#{==:#{@agent_state},working}' \
      "set -p -t $pane @agent_state idle" \; $end_turn
    ;;
  clear)
    tmux set -pu -t "$pane" @agent_state \; $end_turn
    ;;
esac 2>/dev/null

exit 0

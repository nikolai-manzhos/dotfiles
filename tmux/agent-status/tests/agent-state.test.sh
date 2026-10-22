#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

setup_agent_panes

for value in idle working waiting; do
  set_state "$back" "$value"
  check "$value sets @agent_state" "$value" "$(state "$back")"
done

set_state "$back" done
check "done is kept while the session is detached" done "$(state "$back")"

set_state "$back" settle
check "settle keeps done" done "$(state "$back")"
set_state "$back" waiting
set_state "$back" settle
check "settle keeps waiting" waiting "$(state "$back")"
set_state "$back" working
set_state "$back" settle
check "settle turns working into idle" idle "$(state "$back")"

set_state "$back" bogus
check "unknown states are ignored" idle "$(state "$back")"

env -u TMUX_PANE "$root/agent-state.sh" working
check "no-op outside tmux" idle "$(state "$back")"

set_state "$back" clear
check "clear unsets @agent_state" "" "$(state "$back")"

# Stand in for Claude Code's spinner: change the screen while the flag exists.
cat >"$tmp/spinner" <<'EOF'
#!/bin/sh
i=0
while :; do
  if [ -e "$1" ]; then i=$((i + 1)); printf '\r%s' "$i"; fi
  sleep 0.2
done
EOF
chmod +x "$tmp/spinner"
spinning="$tmp/spinning"
touch "$spinning"
t new-session -d -s turns -x 80 -y 10 "$tmp/spinner" "$spinning"
agent="$(t display -p -t turns:0.0 '#{pane_id}')"

transcript="$tmp/session.jsonl"
interrupt "$transcript" # An interrupt from an earlier turn must be ignored.
prompt "$agent" "$transcript"
check "prompt sets working" working "$(state "$agent")"
check "prompt starts a turn" yes "$([[ -n "$(turn "$agent")" ]] && echo yes || echo no)"
cat >>"$transcript" <<'EOF'
{"type":"api-request-blob","messages":[{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]\n"},{"type":"text","text":"next prompt"}]}]}
{"type":"assistant","message":{"content":[{"type":"text","text":"Esc writes [Request interrupted by user] to the transcript"},{"type":"tool_use","input":{"command":"grep -F '\"text\":\"[Request interrupted by user' t.jsonl"}}]}}
EOF
sleep 4
check "busy screens and old or quoted interrupts keep working" working "$(state "$agent")"
interrupt "$transcript"
check "an interrupt sets idle" idle "$(wait_state "$agent" idle)"
check "an interrupt ends the turn" "" "$(turn "$agent")"

prompt "$agent" "$transcript"
rm "$spinning"
check "a stopped spinner sets idle" idle "$(wait_state "$agent" idle 8)"
check "a stopped spinner ends the turn" "" "$(turn "$agent")"

prompt "$agent" "$transcript"
set_state "$agent" waiting
sleep 4.5
check "a still screen at a permission prompt stays waiting" waiting "$(state "$agent")"
interrupt "$transcript"
check "interrupting a permission prompt sets idle" idle "$(wait_state "$agent" idle)"
touch "$spinning"

prompt "$agent" "$transcript"
set_state "$agent" done
check "done ends the turn" "" "$(turn "$agent")"
interrupt "$transcript"
sleep 1.5
check "interrupts after the turn ended are ignored" done "$(state "$agent")"

prompt "$agent" "$transcript"
set_state "$agent" failed
check "failed sets waiting and ends the turn" "waiting:" "$(state "$agent"):$(turn "$agent")"

prompt "$agent" "$transcript"
set_state "$agent" clear
check "clear ends the turn" "" "$(turn "$agent")"

prompt "$agent" "$tmp/new-session.jsonl"
sleep 1.2
interrupt "$tmp/new-session.jsonl"
check "a transcript created after the prompt is watched" idle "$(wait_state "$agent" idle)"
t kill-session -t turns

if command -v python3 >/dev/null 2>&1; then
  t set -g focus-events on
  start_tmux_client unfocused
  set_state "$front" done
  check "an unfocused pane keeps done unseen" done "$(state "$front")"
  stop_tmux_client

  start_tmux_client focused
  set_state "$front" done
  check "a focused pane marks done seen" idle "$(state "$front")"
else
  printf 'skip python3 not found; focus checks disabled\n'
fi

set_state "$back" done
check "a background pane keeps done unseen" done "$(state "$back")"

finish

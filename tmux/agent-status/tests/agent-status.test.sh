#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

setup_agent_panes

# Terminal titles as Claude Code and OpenCode set them. side keeps its default.
t select-pane -t "$front" -T '✳ fix-login-bug'
t select-pane -t "$back" -T 'OC | Refactor parser'
t set-hook -g pane-focus-in[7] 'set -g @other_focus_hook preserved'
t source-file "$root/agent-status.conf"

check "rose-pine prepend section" '#{E:@agent_status}' \
  "$(t show -gv @rose_pine_status_right_prepend_section)"
check "keeps other pane-focus hooks" yes \
  "$(t show-hooks -g pane-focus-in | grep -q '^pane-focus-in\[7\] ' && echo yes || echo no)"
check "uses a stable pane-focus hook index" yes \
  "$(t show-hooks -g pane-focus-in | grep -q '^pane-focus-in\[100\] ' && echo yes || echo no)"

set_state "$front" working
set_state "$back" waiting
set_state "$shell" done
set_state "$side" idle
check "groups agents by window and skips shell panes" \
  "api ● fix-login-bug │ web ! Refactor parser · ○ p2" "$(render)"

raw="$(t display -p -t test:0 '#{E:@agent_status}')"
check "window names are bold iris" yes \
  "$([[ "$raw" == *'#[fg=#c4a7e7 bold]api#[nobold] '*'#[fg=#c4a7e7 bold]web#[nobold] '* ]] && echo yes || echo no)"
check "the selected agent is bold white" yes \
  "$([[ "$raw" == *'#[fg=#e0def4 bold]fix-login-bug#[nobold]'* ]] && echo yes || echo no)"
check "the selected agent differs from the working glyph" yes \
  "$([[ "$raw" == *'#[fg=#f6c177 bold]●#[nobold] #[fg=#e0def4 bold]fix-login-bug'* && "$raw" != *'#[fg=#f6c177 bold]fix-login-bug'* ]] && echo yes || echo no)"
check "agents in other panes are high contrast and not bold" yes \
  "$([[ "$raw" == *'#[fg=#e0def4]Refactor parser#[nobold]'* ]] && echo yes || echo no)"

set_state "$back" done
set_state "$front" idle
t select-pane -t "$front" -T '✳ Claude Code'
t select-pane -t "$back" -T 'OC | Rewrite the whole status bar module'
check "renders states, pane numbers, and truncated names" \
  "api ○ claude │ web ✓ Rewrite the whol… · ○ p2" "$(render)"

set_state "$front" clear
check "widens names when fewer agents are visible" \
  "web ✓ Rewrite the whole status… · ○ p2" "$(render)"

# An agent can exit back to its shell without calling the state hook. Its
# lingering @agent_state must not keep the other names at the narrower tier.
t select-pane -t "$shell" -T 'OC | Temporary agent'
t send-keys -t "$shell" 'sleep 60' Enter
for _ in {1..30}; do
  [[ "$(t display -p -t "$shell" '#{pane_current_command}')" == sleep ]] && break
  sleep 0.1
done
check "agent process is running in the shell pane" sleep \
  "$(t display -p -t "$shell" '#{pane_current_command}')"
t set -p -t "$shell" @agent_state working
check "running agent narrows other labels" \
  "web ✓ Rewrite the whol… · ● Temporary agent · ○ p2" "$(render)"
t send-keys -t "$shell" C-c
for _ in {1..30}; do
  [[ "$(t display -p -t "$shell" '#{pane_current_command}')" == *sh ]] && break
  sleep 0.1
done
check "agent returned to its shell without a hook" yes \
  "$([[ "$(t display -p -t "$shell" '#{pane_current_command}')" == *sh && "$(state "$shell")" == working ]] && echo yes || echo no)"
check "exited agent is hidden and other labels widen immediately" \
  "web ✓ Rewrite the whole status… · ○ p2" "$(render)"

t select-pane -t "$back" -T 'OpenCode'
check "uses the agent kind before a session is named" \
  "web ✓ opencode · ○ p2" "$(render)"
t select-pane -t "$back" -T 'OC | Rewrite the whole status bar module'

if command -v python3 >/dev/null 2>&1; then
  start_tmux_client focused
  t select-window -t test:1
  t select-pane -t "$back"
  check "focusing a done pane marks it seen" idle "$(state "$back")"
  check "other pane-focus hooks still run" preserved "$(t show -gv @other_focus_hook)"
  stop_tmux_client

  # Put agent status after a window range to verify non-agent clicks too.
  t set -g mouse on
  t set -g 'status-format[0]' '#[range=window|0]<<#[norange] #{E:@agent_status}'
  status() { printf '<< %s' "$(render)"; }
  where() { t display -p -t test '#{window_index}.#{pane_id}'; }

  t select-pane -t "$side"
  t select-window -t test:0
  set_state "$back" done
  click_status "$(status)" "Rewrite"
  check "clicking another window's agent switches panes" "1.$back" "$(where)"
  check "clicking a done agent marks it seen" idle "$(state "$back")"
  click_status "$(status)" "○ p2"
  check "clicking this window's agent switches panes" "1.$side" "$(where)"
  t select-window -t test:1
  click_status "$(status)" "<<"
  check "other status ranges keep tmux's default click" "0.$front" "$(where)"
else
  printf 'skip python3 not found; focus and mouse checks disabled\n'
fi

set_state "$back" clear
set_state "$side" clear
check "renders nothing without agents" "" "$(render)"

finish

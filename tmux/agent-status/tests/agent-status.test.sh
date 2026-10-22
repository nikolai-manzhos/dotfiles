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
  "api: fix-login-bug ●  web: Refactor parser ✋ 2 ○" "$(render)"

raw="$(t display -p -t test:0 '#{E:@agent_status}')"
check "window names are iris" yes \
  "$([[ "$raw" == *'#[fg=#c4a7e7]api#[fg=#908caa]: '*'#[fg=#c4a7e7]web#[fg=#908caa]: '* ]] && echo yes || echo no)"
check "the selected agent is bold white" yes \
  "$([[ "$raw" == *'#[fg=#e0def4 bold]fix-login-bug#[nobold] '* ]] && echo yes || echo no)"
check "the selected agent differs from the working glyph" yes \
  "$([[ "$raw" == *'#[nobold] #[fg=#f6c177]●'* && "$raw" != *'#[fg=#f6c177]fix-login-bug'* ]] && echo yes || echo no)"
check "agents in other panes are grey and not bold" yes \
  "$([[ "$raw" == *'#[fg=#908caa]Refactor parser#[nobold] '* ]] && echo yes || echo no)"

set_state "$back" done
set_state "$front" idle
t select-pane -t "$front" -T '✳ Claude Code'
t select-pane -t "$back" -T 'OC | Rewrite the whole status bar module'
check "renders states, pane numbers, and truncated names" \
  "api: 0 ○  web: Rewrite the whole st… ✓ 2 ○" "$(render)"

set_state "$front" clear
check "leaves out windows without agents" "web: Rewrite the whole st… ✓ 2 ○" "$(render)"

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
  click_status "$(status)" "2 ○"
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

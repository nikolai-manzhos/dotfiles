#!/usr/bin/env bash
# Tests for agent-state.sh, agent-status.conf, install.sh and the opencode plugin.
# Everything runs against a throwaway tmux server and temp dirs, so your real
# tmux session and agent configs are never touched.

set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
socket="agent-status-test-$$"
tmp="$(mktemp -d)"
failures=0

t() { tmux -L "$socket" -f /dev/null "$@"; }

cleanup() {
  t kill-server 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

check() {
  if [[ "$2" == "$3" ]]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3"
    failures=$((failures + 1))
  fi
}

state() { t display -p -t "$1" '#{@agent_state}'; }
set_state() { TMUX_PANE="$1" "$dir/agent-state.sh" "$2"; }
render() { t display -p -t test:0 '#{E:@agent_status}' | sed 's/#\[[^]]*\]//g'; }

# Window "api": an "agent" pane. Window "web": an "agent" pane and a pane at a shell prompt.
t new-session -d -s test -n api -x 120 -y 40 'sleep 600'
t new-window -d -t test:1 -n web 'sleep 600'
t split-window -d -t test:1 'sh'
export TMUX="$(t display -p '#{socket_path}'),0,0"
front="$(t display -p -t test:0.0 '#{pane_id}')"
back="$(t display -p -t test:1.0 '#{pane_id}')"
shell="$(t display -p -t test:1.1 '#{pane_id}')"

printf '# agent-state.sh\n'
for s in idle working waiting; do
  set_state "$back" "$s"
  check "$s sets @agent_state" "$s" "$(state "$back")"
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

env -u TMUX_PANE "$dir/agent-state.sh" working
check "no-op outside tmux" idle "$(state "$back")"

set_state "$back" clear
check "clear unsets @agent_state" "" "$(state "$back")"

# A control-mode client makes the session attached with window 0 in front.
(sleep 30) | t -C attach -t test >/dev/null &
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ "$(t display -p -t test '#{session_attached}')" == 1 ]] && break
  sleep 0.1
done
set_state "$front" done
check "done on the visible pane becomes idle" idle "$(state "$front")"
set_state "$back" done
check "done on a background pane stays done" done "$(state "$back")"

printf '# agent-status.conf\n'
t source-file "$dir/agent-status.conf"
check "rose-pine prepend section" '#{E:@agent_status}' "$(t show -gv @rose_pine_status_right_prepend_section)"

set_state "$front" working
set_state "$back" waiting
set_state "$shell" done
check "renders agent panes as window:pane and skips shell panes" "api:0 ● web:0 ✋ " "$(render)"

set_state "$back" done
set_state "$front" idle
check "renders done and idle" "api:0 ○ web:0 ✓ " "$(render)"

t select-window -t test:1
t select-pane -t "$back"
check "focusing a done pane marks it seen" idle "$(state "$back")"

set_state "$front" clear
set_state "$back" clear
check "renders nothing without agents" "" "$(render)"

printf '# install.sh\n'
settings="$tmp/claude/settings.json"
mkdir -p "$tmp/claude" "$tmp/opencode"
cat >"$settings" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "say done || true" }] }],
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/other-agent-state.sh session" }] }],
    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "audit-log", "async": true }] }]
  }
}
EOF
install() {
  CLAUDE_CONFIG_DIR="$tmp/claude" OPENCODE_CONFIG_DIR="$tmp/opencode" "$dir/install.sh" >/dev/null
}

install
check "other settings are kept" opus "$(jq -r .model "$settings")"
check "existing hooks are kept first" "say done || true" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$settings")"
check "hooks use the absolute script path" "\"$dir/agent-state.sh\" done" \
  "$(jq -r '.hooks.Stop[-1].hooks[0].command' "$settings")"
check "other tools' similarly named hooks are kept" "bash ~/.claude/hooks/other-agent-state.sh session" \
  "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$settings")"
check "every hook from claude-hooks.json is installed" \
  "$(jq '[.[][].hooks[]] | length' "$dir/claude-hooks.json")" \
  "$(jq --arg s "$dir/agent-state.sh" '[.hooks[][].hooks[] | select(.command | contains($s))] | length' "$settings")"
check "matchers are kept" "idle_prompt" "$(jq -r '.hooks.Notification[-1].matcher' "$settings")"

cmd="$(jq -r '.hooks.PermissionRequest[-1].hooks[0].command' "$settings")"
TMUX_PANE="$back" sh -c "$cmd"
check "installed hook command runs" waiting "$(state "$back")"

check "opencode plugin file is linked" "$dir/opencode-agent-state.js" \
  "$(readlink "$tmp/opencode/plugins/tmux-agent-state.js")"
check "opencode 2.x TUI entry is linked" "$dir/opencode-agent-state.js" \
  "$(readlink "$tmp/opencode/plugins/tmux-agent-state/tui.js")"

cp "$settings" "$tmp/settings.first"
install
check "re-running leaves settings.json unchanged" same \
  "$(cmp -s "$settings" "$tmp/settings.first" && echo same || echo changed)"

CLAUDE_CONFIG_DIR="$tmp/claude" OPENCODE_CONFIG_DIR="$tmp/missing" "$dir/install.sh" >/dev/null
check "a missing opencode config dir is skipped" absent \
  "$([[ -e "$tmp/missing" ]] && echo present || echo absent)"

printf '# opencode plugin\n'
if command -v node >/dev/null 2>&1; then
  if node --test "$dir/opencode-agent-state.test.mjs" >"$tmp/node.log" 2>&1; then
    printf 'ok   node --test opencode-agent-state.test.mjs\n'
  else
    cat "$tmp/node.log"
    printf 'FAIL node --test opencode-agent-state.test.mjs\n'
    failures=$((failures + 1))
  fi
else
  printf 'skip node not found\n'
fi

if ((failures)); then
  printf '%d failed\n' "$failures"
  exit 1
fi
printf 'all passed\n'

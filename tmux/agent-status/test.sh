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
turn() { t display -p -t "$1" '#{@agent_turn}'; }
set_state() { TMUX_PANE="$1" "$dir/agent-state.sh" "$2"; }

# The interrupt watcher polls once a second, so allow it a few seconds.
wait_state() {
  for _ in $(seq 1 $((${3:-4} * 10))); do
    [[ "$(state "$1")" == "$2" ]] && break
    sleep 0.1
  done
  state "$1"
}
prompt() {
  printf '{"session_id":"s1","transcript_path":"%s","hook_event_name":"UserPromptSubmit"}\n' "$2" |
    set_state "$1" prompt
}
interrupt() {
  printf '%s\n' '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]"}]}}' >>"$1"
}
render() { t display -p -t test:0 '#{E:@agent_status}' | sed 's/#\[[^]]*\]//g'; }

# Window "api": an "agent" pane. Window "web": two "agent" panes around a pane at a shell prompt.
t new-session -d -s test -n api -x 120 -y 40 'sleep 600'
t new-window -d -t test:1 -n web 'sleep 600'
t split-window -d -t test:1 'sh'
t split-window -d -t test:1.1 'sleep 600'
export TMUX="$(t display -p '#{socket_path}'),0,0"
front="$(t display -p -t test:0.0 '#{pane_id}')"
back="$(t display -p -t test:1.0 '#{pane_id}')"
shell="$(t display -p -t test:1.1 '#{pane_id}')"
side="$(t display -p -t test:1.2 '#{pane_id}')"
# Terminal titles as Claude Code and opencode set them; $side keeps tmux's default.
t select-pane -t "$front" -T '✳ fix-login-bug'
t select-pane -t "$back" -T 'OC | Refactor parser'

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

printf '# interrupts\n'
# Stands in for Claude Code's spinner: the screen changes while the flag file exists.
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
interrupt "$transcript" # from an earlier turn
prompt "$agent" "$transcript"
check "prompt sets working" working "$(state "$agent")"
check "prompt starts a turn" yes "$([[ -n "$(turn "$agent")" ]] && echo yes || echo no)"
cat >>"$transcript" <<'EOF'
{"type":"api-request-blob","messages":[{"role":"user","content":[{"type":"text","text":"[Request interrupted by user]\n"},{"type":"text","text":"next prompt"}]}]}
{"type":"assistant","message":{"content":[{"type":"text","text":"Esc writes [Request interrupted by user] to the transcript"},{"type":"tool_use","input":{"command":"grep -F '\"text\":\"[Request interrupted by user' t.jsonl"}}]}}
EOF
sleep 4
check "a busy screen, earlier interrupts, logged requests and mentions keep it working" working "$(state "$agent")"
interrupt "$transcript"
check "an interrupt sets idle" idle "$(wait_state "$agent" idle)"
check "an interrupt ends the turn" "" "$(turn "$agent")"

prompt "$agent" "$transcript"
rm "$spinning"
check "a screen that stops changing (cancelled before replying) sets idle" idle "$(wait_state "$agent" idle 8)"
check "a still screen ends the turn" "" "$(turn "$agent")"

prompt "$agent" "$transcript"
set_state "$agent" waiting
sleep 4.5
check "a still screen at a permission prompt stays waiting" waiting "$(state "$agent")"
interrupt "$transcript"
check "an interrupt at a permission prompt or question sets idle" idle "$(wait_state "$agent" idle)"
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
set_state "$side" idle
check "groups agents by window, skips shell panes, untitled panes as the pane number" \
  "api: fix-login-bug ●  web: Refactor parser ✋ 2 ○" "$(render)"
raw="$(t display -p -t test:0 '#{E:@agent_status}')"
check "window names are iris" yes \
  "$([[ "$raw" == *'#[fg=#c4a7e7]api#[fg=#908caa]: '*'#[fg=#c4a7e7]web#[fg=#908caa]: '* ]] && echo yes || echo no)"
check "the agent in the selected pane is bold white" yes "$([[ "$raw" == *'#[fg=#e0def4 bold]fix-login-bug#[nobold] '* ]] && echo yes || echo no)"
check "the selected agent's colour differs from the working glyph" yes \
  "$([[ "$raw" == *'#[nobold] #[fg=#f6c177]●'* && "$raw" != *'#[fg=#f6c177]fix-login-bug'* ]] && echo yes || echo no)"
check "agents in other panes are grey and not bold" yes "$([[ "$raw" == *'#[fg=#908caa]Refactor parser#[nobold] '* ]] && echo yes || echo no)"

set_state "$back" done
set_state "$front" idle
t select-pane -t "$front" -T '✳ Claude Code'
t select-pane -t "$back" -T 'OC | Rewrite the whole status bar module'
check "renders done and idle, unnamed sessions as the pane number, long names cut" \
  "api: 0 ○  web: Rewrite the whole st… ✓ 2 ○" "$(render)"

set_state "$front" clear
check "windows without agents are left out" "web: Rewrite the whole st… ✓ 2 ○" "$(render)"

t select-window -t test:1
t select-pane -t "$back"
check "focusing a done pane marks it seen" idle "$(state "$back")"

printf '# mouse clicks\n'
if command -v python3 >/dev/null 2>&1; then
  # Attaches a client on a pty and clicks the status line where $3 starts in $2,
  # its plain text (no wide characters before $3).
  cat >"$tmp/click" <<'EOF'
import fcntl, os, pty, select, signal, struct, sys, termios, time
socket, text, target = sys.argv[1:4]
pid, fd = pty.fork()
if pid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.execvp("tmux", ["tmux", "-L", socket, "attach", "-t", "test"])
fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", 24, 80, 0, 0))
def drain(quiet):
    end = time.time() + 3
    while time.time() < end:
        if not select.select([fd], [], [], quiet)[0]:
            return
        try:
            os.read(fd, 65536)
        except OSError:
            return
drain(0.3)
col = text.index(target) + 1
os.write(fd, f"\x1b[<0;{col};24M\x1b[<0;{col};24m".encode())
drain(0.3)
os.kill(pid, signal.SIGTERM)
os.waitpid(pid, 0)
EOF
  # Only the agent status, after a window range to check other clicks still work.
  t set -g mouse on
  t set -g 'status-format[0]' '#[range=window|0]<<#[norange] #{E:@agent_status}'
  status() { printf '<< %s' "$(render)"; }
  click() { python3 "$tmp/click" "$socket" "$(status)" "$1"; }
  where() { t display -p -t test '#{window_index}.#{pane_id}'; }

  t select-pane -t "$side"
  t select-window -t test:0
  set_state "$back" done
  click "Rewrite"
  check "clicking an agent in another window switches to its pane" "1.$back" "$(where)"
  check "clicking a done agent marks it seen" idle "$(state "$back")"
  click "2 ○"
  check "clicking an agent in the current window selects its pane" "1.$side" "$(where)"
  t select-window -t test:1
  click "<<"
  check "other status ranges keep tmux's default click" "0.$front" "$(where)"
else
  printf 'skip python3 not found\n'
fi

set_state "$back" clear
set_state "$side" clear
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

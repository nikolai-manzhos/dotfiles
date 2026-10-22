# Shared shell-test harness. Each suite gets its own tmux server and temp dir.

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
socket="agent-status-$(basename "$0" .test.sh)-$$"
tmp="$(mktemp -d)"
failures=0
client_pid=""
client_hold=""

t() { tmux -L "$socket" -f /dev/null "$@"; }

stop_tmux_client() {
  rm -f "$client_hold"
  if [[ -n "$client_pid" ]]; then
    wait "$client_pid" 2>/dev/null || true
  fi
  client_pid=""
  client_hold=""
}

cleanup() {
  stop_tmux_client
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

finish() {
  if ((failures)); then
    printf '%d failed\n' "$failures"
    exit 1
  fi
  printf 'passed\n'
}

# Window "api" has one agent. Window "web" has two agents around a shell pane.
setup_agent_panes() {
  t new-session -d -s test -n api -x 120 -y 40 'sleep 600'
  t new-window -d -t test:1 -n web 'sleep 600'
  t split-window -d -t test:1 'sh'
  t split-window -d -t test:1.1 'sleep 600'
  export TMUX="$(t display -p '#{socket_path}'),0,0"

  front="$(t display -p -t test:0.0 '#{pane_id}')"
  back="$(t display -p -t test:1.0 '#{pane_id}')"
  shell="$(t display -p -t test:1.1 '#{pane_id}')"
  side="$(t display -p -t test:1.2 '#{pane_id}')"
}

state() { t display -p -t "$1" '#{@agent_state}'; }
turn() { t display -p -t "$1" '#{@agent_turn}'; }
set_state() { TMUX_PANE="$1" "$root/agent-state.sh" "$2"; }
render() { t display -p -t test:0 '#{E:@agent_status}' | sed 's/#\[[^]]*\]//g'; }

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

start_tmux_client() {
  local focus="$1"
  local flags=""

  client_hold="$tmp/tmux-client.hold"
  touch "$client_hold"
  python3 "$root/tests/tmux-client.py" hold "$socket" test "$client_hold" "$focus" &
  client_pid=$!

  for _ in $(seq 1 30); do
    flags="$(t list-clients -F '#{client_flags}' 2>/dev/null || true)"
    if [[ "$focus" == focused && "$flags" == *focused* ]] ||
       [[ "$focus" == unfocused && -n "$flags" && "$flags" != *focused* ]]; then
      return
    fi
    sleep 0.1
  done

  printf 'tmux client did not become %s (flags: %s)\n' "$focus" "$flags" >&2
  return 1
}

click_status() {
  python3 "$root/tests/tmux-client.py" click "$socket" test "$1" "$2"
}

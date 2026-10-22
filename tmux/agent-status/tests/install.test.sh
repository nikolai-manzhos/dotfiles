#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

t new-session -d -s test 'sleep 600'
export TMUX="$(t display -p '#{socket_path}'),0,0"
pane="$(t display -p -t test:0.0 '#{pane_id}')"

settings="$tmp/claude/settings.json"
mkdir -p "$tmp/claude" "$tmp/opencode"
cat >"$settings" <<'EOF'
{
  "model": "opus",
  "hooks": {
    "Stop": [{ "hooks": [{ "type": "command", "command": "say done || true" }] }],
    "SessionStart": [{ "hooks": [{ "type": "command", "command": "bash ~/.claude/hooks/other-agent-state.sh session" }] }],
    "PreToolUse": [{ "hooks": [{ "type": "command", "command": "audit-log", "async": true }] }],
    "PostToolUse": [{ "hooks": [{ "type": "command", "command": "\"/old/tmux/agent-status/agent-state.sh\" working" }] }]
  }
}
EOF

install() {
  CLAUDE_CONFIG_DIR="$tmp/claude" OPENCODE_CONFIG_DIR="$tmp/opencode" "$root/install.sh" >/dev/null
}

install
check "keeps other settings" opus "$(jq -r .model "$settings")"
check "keeps existing hooks first" "say done || true" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$settings")"
check "uses the absolute script path" "\"$root/agent-state.sh\" done" \
  "$(jq -r '.hooks.Stop[-1].hooks[0].command' "$settings")"
check "keeps similarly named hooks from other tools" \
  "bash ~/.claude/hooks/other-agent-state.sh session" \
  "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$settings")"
check "installs every hook from claude-hooks.json" \
  "$(jq '[.[][].hooks[]] | length' "$root/claude-hooks.json")" \
  "$(jq --arg s "$root/agent-state.sh" '[.hooks[][].hooks[] | select(.command | contains($s))] | length' "$settings")"
check "keeps matchers" idle_prompt "$(jq -r '.hooks.Notification[-1].matcher' "$settings")"
check "resumes working after the complete tool batch" "\"$root/agent-state.sh\" working" \
  "$(jq -r '.hooks.PostToolBatch[-1].hooks[0].command' "$settings")"
check "removes the old per-tool completion hook" 0 \
  "$(jq '[.hooks.PostToolUse[]?.hooks[]? | select(.command | contains("tmux/agent-status/agent-state.sh"))] | length' "$settings")"

command="$(jq -r '.hooks.PermissionRequest[-1].hooks[0].command' "$settings")"
TMUX_PANE="$pane" sh -c "$command"
check "installed permission hook runs" waiting "$(state "$pane")"
command="$(jq -r '.hooks.PostToolBatch[-1].hooks[0].command' "$settings")"
TMUX_PANE="$pane" sh -c "$command"
check "complete tool batches clear waiting" working "$(state "$pane")"

check "links the OpenCode plugin" "$root/opencode-agent-state.js" \
  "$(readlink "$tmp/opencode/plugins/tmux-agent-state.js")"
check "links the OpenCode 2.x TUI entry" "$root/opencode-agent-state.js" \
  "$(readlink "$tmp/opencode/plugins/tmux-agent-state/tui.js")"

cp "$settings" "$tmp/settings.first"
install
check "re-running leaves settings.json unchanged" same \
  "$(cmp -s "$settings" "$tmp/settings.first" && echo same || echo changed)"

CLAUDE_CONFIG_DIR="$tmp/claude" OPENCODE_CONFIG_DIR="$tmp/missing" "$root/install.sh" >/dev/null
check "skips a missing OpenCode config directory" absent \
  "$([[ -e "$tmp/missing" ]] && echo present || echo absent)"

finish

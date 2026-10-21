#!/usr/bin/env bash
# Wires agent-state.sh into Claude Code. Safe to re-run.
# Honours CLAUDE_CONFIG_DIR for a non-default config dir.

set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"
claude_settings="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

if ! command -v jq >/dev/null 2>&1; then
  printf 'jq is required: brew install jq\n' >&2
  exit 1
fi

# Claude Code: drop hooks from previous installs, then append claude-hooks.json
# with the absolute script path. Hooks managed by other tools are left alone.
mkdir -p "$(dirname "$claude_settings")"
[[ -f "$claude_settings" ]] || printf '{}\n' >"$claude_settings"
cp "$claude_settings" "$claude_settings.agent-status.bak"
tmp="$(mktemp)"
jq --arg cmd "\"$dir/agent-state.sh\"" \
  --slurpfile frag "$dir/claude-hooks.json" '
  def strip:
    map(.hooks |= map(select((.command // "") | contains("tmux/agent-status/agent-state.sh") | not)))
    | map(select(.hooks | length > 0));
  def ours:
    $frag[0] | map_values(map(.hooks |= map(.command |= sub("^agent-state\\.sh"; $cmd))));
  .hooks = (
    reduce (ours | to_entries[]) as $e
      ((.hooks // {}) | map_values(strip); .[$e.key] = ((.[$e.key] // []) + $e.value))
    | with_entries(select(.value | length > 0))
  )' "$claude_settings" >"$tmp"
# Written through the existing file to keep its inode, in case it's a symlink.
cat "$tmp" >"$claude_settings"
rm -f "$tmp"
printf 'Claude Code hooks installed in %s\n' "$claude_settings"

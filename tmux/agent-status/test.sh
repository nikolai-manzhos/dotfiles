#!/usr/bin/env bash
# Runs the agent-status shell and Node test suites.

set -euo pipefail

dir="$(cd "$(dirname "$0")" && pwd)"

for test in "$dir"/tests/*.test.sh; do
  printf '## %s\n' "$(basename "$test")"
  bash "$test"
done

printf '## opencode-agent-state.test.mjs\n'
if command -v node >/dev/null 2>&1; then
  if output="$(node --test "$dir/opencode-agent-state.test.mjs" 2>&1)"; then
    printf 'ok   node --test opencode-agent-state.test.mjs\n'
  else
    printf '%s\n' "$output"
    exit 1
  fi
else
  printf 'skip node not found\n'
fi

printf 'all passed\n'

#!/usr/bin/env bash
# Claude Code event sequences, routed through claude-hooks.json.

set -euo pipefail
source "$(dirname "$0")/test-lib.sh"

setup_agent_panes
start_spinner
transcript="$tmp/session.jsonl"

# Claude Code's hooks around a compaction. Depending on the code path,
# SessionStart runs before or after PostCompact.
compact() {
  fire PreCompact "$1" "$2" "$transcript"
  fire SessionStart compact "$2" "$transcript"
  fire PostCompact "$1" "$2" "$transcript"
}

for source in startup resume clear fork; do
  set_state "$back" working
  fire SessionStart "$source" "$back"
  check "SessionStart $source sets idle" idle "$(state "$back")"
done

set_state "$back" done
compact auto "$back"
check "compacting while idle keeps an unseen done" done "$(state "$back")"

fire UserPromptSubmit "" "$agent" "$transcript"
compact auto "$agent"
check "auto-compacting mid-turn keeps working" working "$(state "$agent")"
interrupt "$transcript"
check "an interrupt after auto-compacting still sets idle" idle "$(wait_state "$agent" idle)"

check "/compact's PreCompact hook prints nothing" "" \
  "$(fire PreCompact manual "$agent" "$transcript")"
check "/compact sets working and starts a turn" working:yes \
  "$(state "$agent"):$([[ -n "$(turn "$agent")" ]] && echo yes || echo no)"
fire SessionStart compact "$agent" "$transcript"
check "/compact keeps working until it finishes" working "$(state "$agent")"
fire PostCompact manual "$agent" "$transcript"
check "a finished /compact sets done and ends the turn" "done:" "$(state "$agent"):$(turn "$agent")"

fire PreCompact manual "$agent" "$transcript"
rm "$spinning"
check "a cancelled /compact sets idle once the spinner stops" idle "$(wait_state "$agent" idle 8)"

finish

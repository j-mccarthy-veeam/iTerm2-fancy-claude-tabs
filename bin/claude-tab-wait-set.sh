#!/usr/bin/env bash
# claude-tab-wait-set.sh — Stop hook. Marks the session as idle/waiting so the
# tab turns purple on the next updater poll.
#
# Claude Code calls this (via stdin JSON) whenever it finishes responding.
# The updater script reads the sentinel and overrides the color to purple while
# the session is idle, giving a visual cue that Claude is done and may be
# waiting for you or an external system (CI, code review, etc.).
set -u

INPUT=$(cat 2>/dev/null || true)

if command -v jq >/dev/null 2>&1; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
else
  SESSION_ID=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("session_id",""))' 2>/dev/null)
fi

[ -z "$SESSION_ID" ] && exit 0

STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR"
touch "$STATE_DIR/${SESSION_ID}.waiting_external"

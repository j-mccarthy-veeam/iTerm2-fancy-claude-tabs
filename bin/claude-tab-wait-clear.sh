#!/usr/bin/env bash
# claude-tab-wait-clear.sh — UserPromptSubmit hook. Clears the idle/waiting
# sentinel when the user sends a new prompt so the tab returns to normal.
#
# Claude Code calls this (via stdin JSON) whenever the user submits a prompt.
# Removing the sentinel lets the updater script show green (idle) before Claude
# picks up the turn, then yellow once Claude starts working.
set -u

INPUT=$(cat 2>/dev/null || true)

if command -v jq >/dev/null 2>&1; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
else
  SESSION_ID=$(printf '%s' "$INPUT" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("session_id",""))' 2>/dev/null)
fi

[ -z "$SESSION_ID" ] && exit 0

STATE_DIR="$HOME/.claude/state"
rm -f "$STATE_DIR/${SESSION_ID}.waiting_external"

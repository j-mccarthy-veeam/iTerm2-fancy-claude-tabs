#!/usr/bin/env bash
# claude-tab-wait-clear.sh — clear the external-wait sentinel so the tab
# returns to its normal status-driven color (green/yellow/blue).
#
# Usage:
#   claude-tab-wait-clear.sh               # auto-detect session_id from parent pid
#   claude-tab-wait-clear.sh <session_id>  # explicit session_id
set -u

STATE_DIR="$HOME/.claude/state"
SESSIONS_DIR="$HOME/.claude/sessions"

SESSION_ID="${1:-}"

# Auto-detect: pick the most recently updated session file. The currently
# active session updates its file each second (status, updatedAt), so it wins
# `ls -t`. ps-based pid-walking is unreliable under Claude Code's sandbox.
if [ -z "$SESSION_ID" ] && command -v jq >/dev/null 2>&1; then
  latest=$(ls -t "$SESSIONS_DIR"/*.json 2>/dev/null | head -1)
  [ -n "$latest" ] && SESSION_ID=$(jq -r '.sessionId // empty' "$latest" 2>/dev/null)
fi

if [ -z "$SESSION_ID" ]; then
  echo "claude-tab-wait-clear: could not determine session_id" >&2
  exit 1
fi

rm -f "$STATE_DIR/${SESSION_ID}.waiting_external"

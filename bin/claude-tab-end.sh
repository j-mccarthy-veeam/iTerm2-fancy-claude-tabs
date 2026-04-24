#!/usr/bin/env bash
# claude-tab-end.sh — SessionEnd hook. Kills watcher, resets iTerm2 tab.
set -u

STATE_DIR="$HOME/.claude/state"
INPUT=$(cat 2>/dev/null || true)

SESSION_ID=""
if command -v jq >/dev/null 2>&1; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
fi
[ -z "$SESSION_ID" ] && exit 0

PIDFILE="$STATE_DIR/${SESSION_ID}.watcher.pid"
if [ -f "$PIDFILE" ]; then
  WPID=$(cat "$PIDFILE" 2>/dev/null)
  [ -n "$WPID" ] && kill "$WPID" 2>/dev/null || true
  rm -f "$PIDFILE"
fi

# Reset tab color + title on the parent Claude process's controlling TTY.
TTY=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
if [ -n "$TTY" ] && [ "$TTY" != "??" ]; then
  TTY_PATH="/dev/$TTY"
  if [ -w "$TTY_PATH" ]; then
    {
      printf '\033]6;1;bg;*;default\a'
      printf '\033]0;\a'
    } > "$TTY_PATH" 2>/dev/null || true
  fi
fi

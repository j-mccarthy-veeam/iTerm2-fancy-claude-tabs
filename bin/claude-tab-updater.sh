#!/usr/bin/env bash
# claude-tab-updater.sh — iTerm2 tab color + title watcher for Claude Code sessions.
#
# Usage: claude-tab-updater.sh <session_id> <tty>
# Spawned by SessionStart hook; exits when session file disappears or TTY write fails.

set -u

SESSION_ID="${1:-}"
TTY="${2:-}"
[ -z "$SESSION_ID" ] && exit 0
[ -z "$TTY" ] && exit 0
[ ! -w "$TTY" ] && exit 0

SESSIONS_DIR="$HOME/.claude/sessions"
STATE_DIR="$HOME/.claude/state"
mkdir -p "$STATE_DIR"

PIDFILE="$STATE_DIR/${SESSION_ID}.watcher.pid"
WAITFILE="$STATE_DIR/${SESSION_ID}.waiting_external"
echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"' EXIT

POLL_SEC="${CLAUDE_TAB_POLL_SEC:-1}"

# Self-reload: if the script on disk is replaced (e.g. by install.sh), re-exec
# so long-lived watchers pick up the new code instead of running stale logic
# from when bash first sourced the file.
SCRIPT_PATH="$0"
SELF_MTIME=$(stat -f %m "$SCRIPT_PATH" 2>/dev/null || stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo 0)

find_session_file() {
  for f in "$SESSIONS_DIR"/*.json; do
    [ -e "$f" ] || continue
    if grep -q "\"sessionId\":\"$SESSION_ID\"" "$f" 2>/dev/null; then
      echo "$f"
      return 0
    fi
  done
  return 1
}

write_tab() {
  # $1=r $2=g $3=b $4=title
  local r="$1" g="$2" b="$3" title="$4"
  {
    printf '\033]6;1;bg;red;brightness;%s\a' "$r"
    printf '\033]6;1;bg;green;brightness;%s\a' "$g"
    printf '\033]6;1;bg;blue;brightness;%s\a' "$b"
    printf '\033]0;%s\a' "$title"
  } > "$TTY" 2>/dev/null || return 1
  return 0
}

# Wait up to 10s for session file to materialize.
SESSION_FILE=""
for _ in $(seq 1 20); do
  SESSION_FILE="$(find_session_file)" && [ -n "$SESSION_FILE" ] && break
  sleep 0.5
done
[ -z "$SESSION_FILE" ] && exit 0

LAST_KEY=""
while [ -f "$SESSION_FILE" ]; do
  # Parse fields with jq if available, else fallback grep.
  if command -v jq >/dev/null 2>&1; then
    DATA=$(jq -r '[.status // "idle", .name // "", .cwd // ""] | @tsv' < "$SESSION_FILE" 2>/dev/null)
  else
    DATA=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print("\t".join([d.get("status","idle"),d.get("name","") or "",d.get("cwd","") or ""]))' "$SESSION_FILE" 2>/dev/null)
  fi
  [ -z "$DATA" ] && { sleep "$POLL_SEC"; continue; }

  STATUS=$(printf '%s' "$DATA" | awk -F '\t' '{print $1}')
  NAME=$(printf '%s' "$DATA" | awk -F '\t' '{print $2}')
  CWD=$(printf '%s' "$DATA" | awk -F '\t' '{print $3}')

  if [ -z "$NAME" ]; then
    LABEL="claude: $(basename "$CWD")"
  else
    LABEL="claude: $NAME"
  fi

  case "$STATUS" in
    idle)    R=0;   G=200; B=0   ;;  # green
    waiting) R=0;   G=120; B=220 ;;  # blue
    busy)    R=220; G=190; B=0   ;;  # yellow
    *)       R=128; G=128; B=128 ;;  # grey unknown
  esac

  # Sentinel signals an external-system wait (CI, deploy, AI review polling).
  # Override to purple regardless of busy/idle so polling loops stay purple.
  # Skip when status="waiting" — permission prompts must remain blue.
  if [ -f "$WAITFILE" ] && [ "$STATUS" != "waiting" ]; then
    R=160; G=32; B=240  # purple
  fi

  KEY="$R:$G:$B:$LABEL"
  if [ "$KEY" != "$LAST_KEY" ]; then
    write_tab "$R" "$G" "$B" "$LABEL" || exit 0
    LAST_KEY="$KEY"
  fi

  sleep "$POLL_SEC"

  CUR_MTIME=$(stat -f %m "$SCRIPT_PATH" 2>/dev/null || stat -c %Y "$SCRIPT_PATH" 2>/dev/null || echo 0)
  if [ "$CUR_MTIME" != "$SELF_MTIME" ] && [ "$CUR_MTIME" != 0 ]; then
    exec "$SCRIPT_PATH" "$SESSION_ID" "$TTY"
  fi
done

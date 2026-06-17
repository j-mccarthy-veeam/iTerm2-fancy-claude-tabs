#!/usr/bin/env bash
# install.sh — set up Claude Code SessionStart/SessionEnd hooks that color iTerm2
# tabs by session status and label them with the current /rename name.
#
# Idempotent: safe to re-run; patches ~/.claude/settings.json with jq.
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
BIN_DIR="$CLAUDE_DIR/bin"
STATE_DIR="$CLAUDE_DIR/state"
SETTINGS="$CLAUDE_DIR/settings.json"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq required (brew install jq)" >&2
  exit 1
fi

mkdir -p "$BIN_DIR" "$STATE_DIR"

install -m 0755 "$REPO_ROOT/bin/claude-tab-updater.sh" "$BIN_DIR/claude-tab-updater.sh"
install -m 0755 "$REPO_ROOT/bin/claude-tab-end.sh"     "$BIN_DIR/claude-tab-end.sh"
echo "installed scripts to $BIN_DIR/"

# Upgrade cleanup: remove files from the old manual-purple sentinel mechanism.
rm -f "$BIN_DIR/claude-tab-wait-set.sh" "$BIN_DIR/claude-tab-wait-clear.sh" \
  || echo "warning: could not remove old wait scripts (check permissions on $BIN_DIR)" >&2
rm -rf "${CLAUDE_DIR}/skills/iterm-tab-external-wait" \
  || echo "warning: could not remove old skill dir (check permissions on ${CLAUDE_DIR}/skills)" >&2
rm -f "$STATE_DIR"/*.waiting_external \
  || echo "warning: could not remove .waiting_external files in $STATE_DIR" >&2
echo "removed old manual-purple files (if any)"

# Watchers from before self-reload landed hold the old script in memory and
# keep running stale logic (e.g. the removed "stuck" red branch). Kill them so
# the next SessionStart respawns with current code. Watchers installed after
# this version self-reload via exec when the script file changes.
for pidfile in "$STATE_DIR"/*.watcher.pid; do
  [ -e "$pidfile" ] || continue
  pid=$(cat "$pidfile" 2>/dev/null) || continue
  [ -z "$pid" ] && continue
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null && echo "killed stale watcher pid=$pid"
  fi
  rm -f "$pidfile"
done

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"

SESSION_START_CMD="bash -c 'INPUT=\$(cat); SID=\$(printf \"%s\" \"\$INPUT\" | jq -r .session_id 2>/dev/null); [ -z \"\$SID\" ] && exit 0; TTY=\$(ps -o tty= -p \$PPID 2>/dev/null | tr -d \" \"); [ -z \"\$TTY\" ] || [ \"\$TTY\" = \"??\" ] && exit 0; nohup bash $BIN_DIR/claude-tab-updater.sh \"\$SID\" \"/dev/\$TTY\" >/dev/null 2>&1 & disown'"
SESSION_END_CMD="bash $BIN_DIR/claude-tab-end.sh"

TMP="$(mktemp)"
jq \
  --arg start_cmd "$SESSION_START_CMD" \
  --arg end_cmd   "$SESSION_END_CMD" '
  .hooks //= {}
  | .hooks.SessionStart = (
      ((.hooks.SessionStart // []) | map(select(
        (.hooks // []) | all(.command != $start_cmd)
      ))) + [{
        "hooks": [{"type":"command","command":$start_cmd}]
      }]
    )
  | .hooks.SessionEnd = (
      ((.hooks.SessionEnd // []) | map(select(
        (.hooks // []) | all(.command != $end_cmd)
      ))) + [{
        "hooks": [{"type":"command","command":$end_cmd}]
      }]
    )
  | .hooks.Stop = ((.hooks.Stop // []) | map(select((.hooks // []) | all((.command // "") | test("claude-tab-wait") | not))))
  | (if ((.hooks.Stop // []) | length) == 0 then del(.hooks.Stop) else . end)
  | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select((.hooks // []) | all((.command // "") | test("claude-tab-wait") | not))))
  | (if ((.hooks.UserPromptSubmit // []) | length) == 0 then del(.hooks.UserPromptSubmit) else . end)
' "$SETTINGS" > "$TMP"

mv "$TMP" "$SETTINGS"
echo "patched $SETTINGS (backup written alongside)"
echo
echo "done. open a new iTerm2 tab and run 'claude -n demo' to try it."

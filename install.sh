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
' "$SETTINGS" > "$TMP"

mv "$TMP" "$SETTINGS"
echo "patched $SETTINGS (backup written alongside)"
echo
echo "done. open a new iTerm2 tab and run 'claude -n demo' to try it."

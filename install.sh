#!/usr/bin/env bash
# install.sh — set up Claude Code SessionStart/SessionEnd hooks that color iTerm2
# tabs by session status, label them with the current /rename name, and install
# the iterm-tab-external-wait skill that lets Claude flip the tab purple while
# polling external systems.
#
# Idempotent: safe to re-run; patches ~/.claude/settings.json with jq.
set -euo pipefail

CLAUDE_DIR="$HOME/.claude"
BIN_DIR="$CLAUDE_DIR/bin"
STATE_DIR="$CLAUDE_DIR/state"
SKILLS_DIR="$CLAUDE_DIR/skills"
SETTINGS="$CLAUDE_DIR/settings.json"
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq required (brew install jq)" >&2
  exit 1
fi

mkdir -p "$BIN_DIR" "$STATE_DIR" "$SKILLS_DIR"

install -m 0755 "$REPO_ROOT/bin/claude-tab-updater.sh"    "$BIN_DIR/claude-tab-updater.sh"
install -m 0755 "$REPO_ROOT/bin/claude-tab-end.sh"        "$BIN_DIR/claude-tab-end.sh"
install -m 0755 "$REPO_ROOT/bin/claude-tab-wait-set.sh"   "$BIN_DIR/claude-tab-wait-set.sh"
install -m 0755 "$REPO_ROOT/bin/claude-tab-wait-clear.sh" "$BIN_DIR/claude-tab-wait-clear.sh"
echo "installed scripts to $BIN_DIR/"

SKILL_SRC="$REPO_ROOT/skills/iterm-tab-external-wait"
SKILL_DST="$SKILLS_DIR/iterm-tab-external-wait"
if [ -d "$SKILL_SRC" ]; then
  mkdir -p "$SKILL_DST"
  install -m 0644 "$SKILL_SRC/SKILL.md" "$SKILL_DST/SKILL.md"
  echo "installed skill to $SKILL_DST/"
fi

if [ ! -f "$SETTINGS" ]; then
  echo '{}' > "$SETTINGS"
fi

cp "$SETTINGS" "$SETTINGS.bak.$(date +%s)"

SESSION_START_CMD="bash -c 'INPUT=\$(cat); SID=\$(printf \"%s\" \"\$INPUT\" | jq -r .session_id 2>/dev/null); [ -z \"\$SID\" ] && exit 0; TTY=\$(ps -o tty= -p \$PPID 2>/dev/null | tr -d \" \"); [ -z \"\$TTY\" ] || [ \"\$TTY\" = \"??\" ] && exit 0; nohup bash $BIN_DIR/claude-tab-updater.sh \"\$SID\" \"/dev/\$TTY\" >/dev/null 2>&1 & disown'"
SESSION_END_CMD="bash $BIN_DIR/claude-tab-end.sh"
WAIT_SET_CMD="bash $BIN_DIR/claude-tab-wait-set.sh"
WAIT_CLEAR_CMD="bash $BIN_DIR/claude-tab-wait-clear.sh"

TMP="$(mktemp)"
jq \
  --arg start_cmd      "$SESSION_START_CMD" \
  --arg end_cmd        "$SESSION_END_CMD" \
  --arg wait_set_cmd   "$WAIT_SET_CMD" \
  --arg wait_clear_cmd "$WAIT_CLEAR_CMD" '
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
  | .hooks.Stop = ((.hooks.Stop // []) | map(select((.hooks // []) | all(.command != $wait_set_cmd))))
  | (if ((.hooks.Stop // []) | length) == 0 then del(.hooks.Stop) else . end)
  | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) | map(select((.hooks // []) | all(.command != $wait_clear_cmd))))
  | (if ((.hooks.UserPromptSubmit // []) | length) == 0 then del(.hooks.UserPromptSubmit) else . end)
' "$SETTINGS" > "$TMP"

mv "$TMP" "$SETTINGS"
echo "patched $SETTINGS (backup written alongside)"
echo
echo "done. open a new iTerm2 tab and run 'claude -n demo' to try it."

# iTerm2 fancy Claude tabs

Color iTerm2 tabs by your Claude Code session's live status, and set the tab
title to the name you give the session with `/rename` (or `claude -n <name>`).

| Color  | Claude status | Meaning |
|--------|---------------|---------|
| 🟢 Green | `idle`     | Ready — waiting for your next prompt |
| 🟡 Yellow | `busy`    | Claude is thinking / running tools |
| 🔵 Blue  | `waiting`  | Claude needs input (permission prompt, plan approval, etc.) |
| 🟣 Purple | `shell`   | Claude is parked on a background shell it started (e.g. a long `run_in_background` command) |

Tab title is `claude: <name>` (from `-n` or `/rename`), falling back to the
project directory name.

## How it works

Claude Code writes its live session state (status, name, cwd, updatedAt) to
`~/.claude/sessions/<pid>.json`. The installer wires two hooks:

- `SessionStart` — spawns a tiny background watcher (`bin/claude-tab-updater.sh`)
  that polls the session file once per second and emits iTerm2 OSC 0 (title)
  and OSC 6 (tab color) escapes to the session's controlling TTY.
- `SessionEnd` — `bin/claude-tab-end.sh` kills the watcher and resets the tab.

No slash-command hook is needed for `/rename`: the new name lands in the
session file on disk, and the watcher picks it up on its next poll (~1s).

### Purple tabs — automatic, no setup

Claude Code emits a fourth status value, `shell`, when the session is otherwise
idle but has a background shell (`local_bash`) still running. The watcher maps
that directly to purple. No skill, sentinel file, or manual steps required.

To get a purple tab for a long external wait (CI polling, deployment watch,
etc.), run it via `run_in_background`:

> Ask Claude to start the long-running command with `run_in_background`. While
> Claude is parked waiting for it, the session file reads `shell` and the tab
> goes purple automatically.

**Note:** background *agents* (Task/subagents) are typed `local_agent` in
Claude's internal state, not `local_bash`, so they do not trigger `shell` status
— the tab stays green while a background agent runs.

## Requirements

- macOS + iTerm2 (OSC 6 tab color is iTerm2-only; title still works elsewhere)
- Claude Code CLI
- `jq` (used by the installer and hook): `brew install jq`

## Install

```bash
git clone git@github.com:j-mccarthy-veeam/iTerm2-fancy-claude-tabs.git
cd iTerm2-fancy-claude-tabs
./install.sh
```

The installer:

1. Copies the scripts to `~/.claude/bin/`.
2. Backs up `~/.claude/settings.json` and adds `SessionStart` / `SessionEnd`
   hook entries (merges — existing hooks are preserved). Removes any
   `Stop` / `UserPromptSubmit` hook entries left over from earlier versions.
3. Removes old manual-purple files (`claude-tab-wait-*.sh`,
   `~/.claude/skills/iterm-tab-external-wait/`, any leftover sentinel files)
   so upgraders are cleaned up automatically.
4. Is idempotent — safe to re-run after pulling updates.

Open a fresh iTerm2 tab and run:

```bash
claude -n demo
```

The tab should turn green with the title `claude: demo`. Ask Claude to run a
bash command and watch it go yellow → green. Trigger a permission prompt for
blue. Ask Claude to run `sleep 60` with `run_in_background` and watch it turn
purple while it waits.

## Configuration

Override via env vars (set in your shell before launching Claude):

| Env var | Default | Description |
|---|---|---|
| `CLAUDE_TAB_POLL_SEC`  | `1`  | Session-file poll interval |

## Uninstall

1. Remove the `SessionStart` and `SessionEnd` entries added by the installer
   from `~/.claude/settings.json`.
2. Delete `~/.claude/bin/claude-tab-*.sh`.

## Non-iTerm2 terminals

Tab title works on any terminal that respects OSC 0 (Terminal.app, Ghostty,
Alacritty, WezTerm, tmux). Tab color is iTerm2-specific — non-iTerm2 terminals
will silently ignore the OSC 6 escapes.

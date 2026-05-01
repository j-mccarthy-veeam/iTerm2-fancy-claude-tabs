# iTerm2 fancy Claude tabs

Color iTerm2 tabs by your Claude Code session's live status, and set the tab
title to the name you give the session with `/rename` (or `claude -n <name>`).

| Color  | Claude status | Meaning |
|--------|---------------|---------|
| 🟢 Green | `idle`     | Ready — waiting for your next prompt |
| 🟡 Yellow | `busy`    | Claude is thinking / running tools |
| 🔵 Blue  | `waiting`  | Claude needs input (permission prompt, plan approval, etc.) |
| 🟣 Purple | sentinel file present | Claude is parked on an external system (CI, deploy, AI review) — explicitly opt-in via the `iterm-tab-external-wait` skill |

Tab title is `claude: <name>` (from `-n` or `/rename`), falling back to the
project directory name.

## How it works

Claude Code writes its live session state (status, name, cwd, updatedAt) to
`~/.claude/sessions/<pid>.json`. The installer wires two hooks plus a skill:

- `SessionStart` — spawns a tiny background watcher (`bin/claude-tab-updater.sh`)
  that polls the session file once per second and emits iTerm2 OSC 0 (title)
  and OSC 6 (tab color) escapes to the session's controlling TTY.
- `SessionEnd` — `bin/claude-tab-end.sh` kills the watcher, resets the tab,
  and cleans up any leftover state files.
- `iterm-tab-external-wait` skill — installs to `~/.claude/skills/`. Claude
  invokes the skill before/after long external waits to flip the tab purple
  while polling and clear it when done. Calls `bin/claude-tab-wait-set.sh`
  / `bin/claude-tab-wait-clear.sh`, which touch / remove a sentinel file the
  watcher reads each second.

No slash-command hook is needed for `/rename`: the new name lands in the
session file on disk, and the watcher picks it up on its next poll (~1s).

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
2. Copies the `iterm-tab-external-wait` skill to `~/.claude/skills/`.
3. Backs up `~/.claude/settings.json` and adds `SessionStart` / `SessionEnd`
   hook entries (merges — existing hooks are preserved). Removes any
   `Stop` / `UserPromptSubmit` hook entries left over from earlier versions
   that drove purple automatically.
4. Is idempotent — safe to re-run after pulling updates.

Open a fresh iTerm2 tab and run:

```bash
claude -n demo
```

The tab should turn green with the title `claude: demo`. Ask Claude to run a
bash command and watch it go yellow → green. Trigger a permission prompt for
blue. Run `/rename something-else` and the title updates within ~1s.

## Configuration

Override via env vars (set in your shell before launching Claude):

| Env var | Default | Description |
|---|---|---|
| `CLAUDE_TAB_POLL_SEC`  | `1`  | Session-file poll interval |

## Purple tab — the `iterm-tab-external-wait` skill

Purple is **opt-in**. It only fires when something creates the sentinel file
`~/.claude/state/<session_id>.waiting_external`. The watcher overrides the tab
to purple whenever that file exists, except when status is `waiting`
(permission prompt) — those stay blue so input prompts stay visible.

The repo ships a Claude Code skill, `iterm-tab-external-wait`, that teaches
Claude *when* to flip the sentinel:

- Set purple before polling for CI / build completion, watching a deployment
  roll out, waiting on an AI / human code review, or any long sleep-and-recheck
  loop where Claude is parked on an external system.
- Clear purple as soon as the wait returns.

### How the skill is installed

`./install.sh` copies `skills/iterm-tab-external-wait/SKILL.md` from this repo
into `~/.claude/skills/iterm-tab-external-wait/SKILL.md` (creating the
directory if needed). No extra step is required — re-running the installer
also updates the skill in place.

Claude Code auto-discovers every skill under `~/.claude/skills/` at session
start and exposes it to the model via the skill's frontmatter `description`.
The description is written in `ALWAYS use this skill BEFORE...` form so Claude
invokes it whenever it's about to enter a long external wait.

Verify the skill is installed:

```bash
ls ~/.claude/skills/iterm-tab-external-wait/SKILL.md
```

In a fresh Claude session, `/skills` should list `iterm-tab-external-wait`.

### How the skill drives the tab

The skill calls these two helpers (auto-detect the active session by picking
the most recently updated `~/.claude/sessions/*.json`):

```bash
bash ~/.claude/bin/claude-tab-wait-set.sh    # touch sentinel — tab goes purple
bash ~/.claude/bin/claude-tab-wait-clear.sh  # remove sentinel — tab returns to normal
```

You can drive them by hand for debugging:

```bash
touch ~/.claude/state/<session_id>.waiting_external   # force purple
rm    ~/.claude/state/<session_id>.waiting_external   # force normal
```

The `SessionEnd` hook clears the sentinel automatically, so a forgotten clear
will not leak across sessions.

## Uninstall

1. Remove the `SessionStart` and `SessionEnd` entries added by the installer
   from `~/.claude/settings.json`.
2. Delete `~/.claude/bin/claude-tab-*.sh`.
3. Delete `~/.claude/skills/iterm-tab-external-wait/`.

## Non-iTerm2 terminals

Tab title works on any terminal that respects OSC 0 (Terminal.app, Ghostty,
Alacritty, WezTerm, tmux). Tab color is iTerm2-specific — non-iTerm2 terminals
will silently ignore the OSC 6 escapes.

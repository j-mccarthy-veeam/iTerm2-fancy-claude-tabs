# iTerm2 fancy Claude tabs

Color iTerm2 tabs by your Claude Code session's live status, and set the tab
title to the name you give the session with `/rename` (or `claude -n <name>`).

| Color  | Claude status | Meaning |
|--------|---------------|---------|
| 🟢 Green | `idle`     | Ready — waiting for your next prompt |
| 🟡 Yellow | `busy`    | Claude is thinking / running tools |
| 🔵 Blue  | `waiting`  | Claude needs input (permission prompt, plan approval, etc.) |
| 🟣 Purple | `idle` + sentinel file | Waiting on an external system (CI, code review, etc.) — see [Waiting on an external system](#waiting-on-an-external-system-purple-tab) |

Tab title is `claude: <name>` (from `-n` or `/rename`), falling back to the
project directory name.

## How it works

Claude Code writes its live session state (status, name, cwd, updatedAt) to
`~/.claude/sessions/<pid>.json`. We install two hooks:

- `SessionStart` — spawns a tiny background watcher (`bin/claude-tab-updater.sh`)
  that polls the session file once per second and emits iTerm2 OSC 0 (title)
  and OSC 6 (tab color) escapes to the session's controlling TTY.
- `SessionEnd` — `bin/claude-tab-end.sh` kills the watcher and resets the tab.

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
2. Backs up `~/.claude/settings.json` and adds `SessionStart` + `SessionEnd`
   hook entries (merges — existing hooks are preserved).
3. Is idempotent — safe to re-run after pulling updates.

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

## Waiting on an external system (purple tab)

Claude Code reports `idle` status whenever it is paused — whether genuinely
waiting for your next prompt or sitting idle while you wait for a CI run or an
AI code review to complete. Because there is no built-in status to distinguish
the two, the watcher uses a **sentinel file** as an out-of-band signal.

While Claude is waiting on something external, touch the file for that session:

```bash
# turn the tab purple  (replace <SID> with the actual session id)
touch ~/.claude/state/<SID>.waiting_external
```

When the external task finishes and you're ready to continue, remove the file:

```bash
rm ~/.claude/state/<SID>.waiting_external
```

The tab reverts to green on the next poll (~1 s).

**Tip — helper aliases** — add something like this to your shell profile so you
can quickly toggle the state for the current session:

```bash
# Usage: claude-wait <session-id>  /  claude-resume <session-id>
alias claude-wait='f(){ touch "$HOME/.claude/state/$1.waiting_external"; }; f'
alias claude-resume='f(){ rm -f "$HOME/.claude/state/$1.waiting_external"; }; f'
```

The session id is printed by `claude --version` or visible in the session file
name under `~/.claude/sessions/`.

## Uninstall

Remove the `SessionStart` / `SessionEnd` entries added by the installer from
`~/.claude/settings.json` and delete `~/.claude/bin/claude-tab-*.sh`.

## Non-iTerm2 terminals

Tab title works on any terminal that respects OSC 0 (Terminal.app, Ghostty,
Alacritty, WezTerm, tmux). Tab color is iTerm2-specific — non-iTerm2 terminals
will silently ignore the OSC 6 escapes.

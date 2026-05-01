---
name: iterm-tab-external-wait
description: Color the user's iTerm2 tab purple while Claude is blocked on an external system — CI builds, deployment rollouts, AI review polling, long `gh pr checks --watch` / `kubectl wait` / cron-like polling loops, scheduled-agent waits, or any sleep-and-recheck loop that takes more than ~30 seconds. ALWAYS use this skill BEFORE starting such a wait so the tab visibly indicates Claude is parked on someone else, and AGAIN AFTER the wait finishes to clear the color. Do NOT use for normal in-session work, short tool calls, or waiting on the user's next prompt — green/yellow/blue already cover those.
---

# iterm-tab-external-wait

Flip the iTerm2 tab purple while Claude is blocked on an external system, and clear it when the wait ends. Lets the user glance at the tab strip and see which sessions are actually parked vs. actively working.

## When to invoke

Set purple **before** any of these:

- Polling for CI / build completion (`gh pr checks --watch`, `gh run watch`, repeated `gh pr view --json statusCheckRollup`)
- Watching a deployment roll out (`kubectl rollout status`, `kubectl wait`, `pulumi up` long-running, Argo / Flux sync polling)
- Waiting on an AI / human code review to finish (CodeRabbit, Copilot review, polling for new PR comments)
- Running long-running async work the user kicked off (queued jobs, scheduled agents, `/loop` ticks waiting for an event)
- Any explicit poll-with-sleep loop where Claude is the one polling and the wait is longer than ~30 s

Clear purple **after** the wait returns, before continuing other work.

Do NOT invoke for:

- Short bash commands (compile, test run, npm install) — those are normal busy work; yellow already covers them.
- Waiting for the user's next prompt — that's idle/green by design.
- Permission prompts or plan approvals — those are blue (status="waiting"); the watcher already keeps blue and ignores the sentinel during it.

## How to use

Two scripts, no arguments needed (they auto-detect the current Claude session by picking the most recently updated `~/.claude/sessions/<pid>.json` — the live session updates its file each second):

```bash
# Mark the tab purple — call right before the wait begins.
bash ~/.claude/bin/claude-tab-wait-set.sh

# Clear purple — call as soon as the wait completes (success OR failure).
bash ~/.claude/bin/claude-tab-wait-clear.sh
```

Wrap the wait so the clear runs even on error:

```bash
bash ~/.claude/bin/claude-tab-wait-set.sh
trap 'bash ~/.claude/bin/claude-tab-wait-clear.sh' EXIT
gh pr checks 1234 --watch
```

Or, for multi-step Claude flows, call `wait-set` before issuing the first poll and `wait-clear` once the polling loop exits — regardless of which tool call did the polling.

## What it does

`wait-set` touches `~/.claude/state/<session_id>.waiting_external`. The background watcher (`claude-tab-updater.sh`) sees the sentinel each second and overrides the tab color to purple, except when Claude's status is `waiting` (permission prompt) — those stay blue so the user knows input is needed.

`wait-clear` removes the sentinel; the tab returns to its normal status-driven color on the next poll (~1 s).

The sentinel is also cleaned up automatically at session end (`SessionEnd` hook), so a forgotten clear won't leak across sessions.

## Manual override

The user can also touch / remove the sentinel by hand:

```bash
touch  ~/.claude/state/<session_id>.waiting_external   # force purple
rm -f  ~/.claude/state/<session_id>.waiting_external   # force normal
```

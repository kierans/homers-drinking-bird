# agent-status-call

A Claude Code plugin providing a custom status line and subagent status line:
context-window usage, git/hg branch, Claude.ai rate-limit windows, and
per-subagent model/effort rows in the agent panel.

## What it does

**`scripts/status-line.sh`** — renders the main status line:

```
Model [effort] | [██░░░░░░░░] 30% | branch | ⏱ 42% (in 3h) · 18% (in 2d)
```

- **Model** — the session's display name (or model ID), followed by the
  reasoning effort in brackets (`.effort.level`, or `auto` when that field is
  absent — e.g. the model doesn't support the effort parameter).
- **Context** — a 10-block usage bar with percentage.
- **Git/Hg branch** — read-only lookup against the session's working directory;
  omitted outside a repo or when there's no resolvable branch/bookmark.
- **Rate limits** — Claude.ai 5-hour and 7-day window usage with a countdown to
  reset. The 7-day window also flags pace overruns (a `!` after the percentage)
  against a daily budget, so you can see at a glance if you're burning the
  weekly allowance faster than a steady pace would allow.

**`scripts/subagent-status-line.sh`** — overrides each row in the agent panel
to add that subagent's own resolved model and effort in front of the
existing `name · description · token count` row, instead of just the main
session's model. Claude Code's default row for a running subagent looks like:

```
code-reviewer · Reviewing the diff for bugs · 12.4k tokens
```

With this plugin active, the same row becomes:

```
[Opus 5:high] · code-reviewer · Reviewing the diff for bugs · 12.4k tokens
```

— prepending the model/effort that subagent is actually running on, which
the main status line can't show you (it only ever sees the top-level
session's model). `name`, `description`, and the token count are each
omitted if the underlying field is absent, and `effort` defaults to `auto`
when the subagent inherits the session's effort level. Different subagents
in the panel get their own row:

```
[Haiku 4.5:auto] · quick-check · Checking imports · 850 tokens
[Opus 5:high] · code-reviewer · Reviewing the diff for bugs · 12.4k tokens
```

Both scripts require `jq`. `status-line.sh` targets macOS's BSD `date`.

## Installation

This repo is a plugin and, via its own `.claude-plugin/marketplace.json`
(`source: "./"`), also a single-plugin marketplace, so it installs straight
from GitHub — no separate marketplace repo needed.

From inside a Claude Code session, run:

```
/plugin marketplace add kierans/agent-status-call
/plugin install agent-status-call@agent-status-call
```

If the install summary says `Run /reload-plugins to activate.`, run:

```
/reload-plugins
```

Verify it loaded with `/plugin list` or `claude plugin details agent-status-call@agent-status-call`.

### Subagent status line

Wired up automatically: this plugin ships a `settings.json` with a
`subagentStatusLine` default, which Claude Code applies once the plugin is
installed and active. No further configuration needed.

### Main status line

Claude Code plugins can't yet auto-wire the top-level `statusLine` setting —
only `subagentStatusLine` and `agent` are supported in a plugin's
`settings.json`, so wire this one up yourself.

`/plugin install` puts the script at:

```
~/.claude/plugins/cache/agent-status-call/agent-status-call/<version>/scripts/status-line.sh
```

`<version>` changes every time the plugin updates, so don't point
`statusLine` straight at that path — point it at a symlink instead, and
re-point the symlink after each update:

```bash
ln -sf ~/.claude/plugins/cache/agent-status-call/agent-status-call/1.0.0/scripts/status-line.sh \
  ~/.claude/scripts/status-line.sh
```

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/scripts/status-line.sh"
  }
}
```

## Testing

Both scripts read a JSON payload from stdin. Test either one directly:

```bash
echo '{"model":{"display_name":"Opus"},"context_window":{"used_percentage":30},"effort":{"level":"high"}}' \
  | ./scripts/status-line.sh

echo '{"tasks":[{"id":"t1","model":"claude-opus-5","effort":"high","name":"code-reviewer","description":"Reviewing the diff for bugs","tokenCount":12400}]}' \
  | ./scripts/subagent-status-line.sh
```

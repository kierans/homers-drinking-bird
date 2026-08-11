# homers-drinking-bird

[Kieran Simpson's](https://github.com/kierans) Claude Code plugin marketplace.

## Installation

From inside a Claude Code session:

```
/plugin marketplace add kierans/homers-drinking-bird
```

Then install any plugin listed below:

```
/plugin install <plugin-name>@homers-drinking-bird
```

## Plugins

- [agent-status-call](plugins/agent-status-call/README.md) — custom status
  line and subagent status line: context-window usage bar, git/hg branch,
  Claude.ai rate-limit windows, and per-subagent model/effort rows.

## Adding a plugin

Each plugin lives under `plugins/<name>/` with its own
`.claude-plugin/plugin.json`, `README.md`, and `CLAUDE.md`. 

Add a matching entry to the root `.claude-plugin/marketplace.json` pointing
`source` at `./plugins/<name>`. 

See the root `CLAUDE.md` for details.

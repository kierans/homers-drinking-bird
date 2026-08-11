# homers-drinking-bird

A Claude Code plugin marketplace owned by [Kieran Simpson](https://github.com/kierans). The root
`.claude-plugin/marketplace.json` lists every published plugin; each plugin lives in its own
directory under `plugins/`.

## Conventions

- Each plugin is self-contained under `plugins/<plugin-name>/`: its own
  `.claude-plugin/plugin.json`, its own `README.md`, and its own `CLAUDE.md`
  for language/tool-specific conventions. This root `CLAUDE.md` only covers
  marketplace-wide rules; read the plugin's own `CLAUDE.md` before editing
  its code.
- To add a new plugin: create `plugins/<name>/.claude-plugin/plugin.json`,
  then add a matching entry to the root `marketplace.json` with
  `"source": "./plugins/<name>"`.
- Plugins version independently via their own `plugin.json`. The
  marketplace itself has no separate version.
- Don't move shared tooling or scripts into the root — if two plugins need
  the same thing, that's a signal to reconsider the split, not a place to
  add root-level shared code.

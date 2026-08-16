# agent-status-call

A Claude Code plugin: a main status line script and a subagent status line
script. See README.md for what each one renders and how to install/wire them.

## Conventions

- Pure bash, no external runtime beyond `jq` (and `hg` if present, checked
  optionally). Don't introduce a language runtime or package manager for this.
- `status-line.sh` supports both BSD `date` (macOS) and GNU `date` (Linux) for
  timestamp parsing. Don't call `date -j`/`date -d` directly outside
  `parse_timestamp_bsd`/`parse_timestamp_gnu` — add new date-parsing behavior to
  both of those and let the `date --version` detection keep picking the right
  one for `parse_timestamp`, rather than branching inline at each call site.
- Both scripts read one JSON payload from stdin and must never write anything
  but the intended output to stdout — Claude Code renders stdout verbatim.
  Diagnostics, if any, go to stderr.
- Keep failure modes silent and non-fatal: missing `jq` degrades to a plain
  message (status-line.sh) or a no-op exit (subagent-status-line.sh) rather
  than an error. Missing/malformed fields in the input JSON should drop that
  segment, not crash the script.
- No comments explaining *what* a line does. The existing header comment
  blocks in each script document behavior (output shape, field precedence,
  timestamp parsing rules); update those blocks when the behavior they
  describe changes, since they're the spec for anyone editing this later.
- Test changes by piping representative JSON into the script directly (see
  README.md's Testing section) rather than reloading Claude Code between
  every edit.

## Updating the changelog

When asked to update or generate `CHANGELOG.md` for a version bump:

- Find the revision that last changed `.claude-plugin/plugin.json`'s
  `version` field to the prior release, then walk the log over this
  plugin's directory between that revision and the new version-bump
  commit to see what changed. Check the repo root for `.hg` vs `.git`
  (CLAUDE.md/AGENTS.md at the root usually says which) and use the
  matching commands:
  - Mercurial: `hg log --template '{node|short} {desc|firstline}\n' --
    .claude-plugin/plugin.json` to find the prior bump, then
    `hg log -v -r <prior>::<new>` over the plugin's directory.
  - Git: `git log --oneline -- .claude-plugin/plugin.json` to find the
    prior bump, then `git log -p <prior>..<new> --
    plugins/agent-status-call/` over the plugin's directory.
- Group entries under the new version by type — Added / Changed / Fixed /
  Documentation / Removed — using each commit's Conventional Commits type
  (`feat`, `fix`, `docs`, `refactor`, etc.) as a guide, not a literal
  mapping. Skip the version-bump commit itself.
- Write entries from the user's perspective (what changed about the
  plugin's behavior or docs), not a copy of the commit log.
- Follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/):
  newest version first, `## [x.y.z] - YYYY-MM-DD` headings using the date
  of the version-bump commit, reference-style links for the format/semver
  footnotes.

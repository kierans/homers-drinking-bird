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

## Claude Code inputs and outputs are never assumed

Both scripts sit on a contract owned by Claude Code: the JSON each one receives
on stdin, and how Claude Code renders what each one prints. Neither half of
that contract may be reasoned about from memory, from what the current code
appears to do, or from the other script. Check it against the status line
documentation first — [`statusLine` and `subagentStatusLine` are both covered
there][1] — and only then write the change.

This applies to, at least:

- field names, including whether a field is snake_case or camelCase;
- whether a field is guaranteed present, and the minimum Claude Code version
  that introduced it;
- what each payload actually contains — the two are different objects, and the
  subagent payload's per-task fields are not the session's fields;
- how stdout is rendered: ANSI escapes, OSC 8 links, truncation, and how the
  usable width is determined;
- the row-override protocol for subagent rows.

Then:

- **If the docs answer it**, record the answer in that script's header comment
  block, so the next edit inherits the finding instead of re-deriving it.
- **If the docs don't answer it**, test it against a running Claude Code
  session and write down what was observed, how, and the version it was
  observed on. The README's note on plugin-declared `subagentStatusLine` never
  being read is the model: it states the test, the method, and the version.
- **If it can be neither validated nor observed**, don't make the change that
  depends on it. A plausible-looking guess about someone else's contract is the
  one kind of change this plugin should not ship.
- **Never carry a finding across from the other script.** The two consume
  different inputs and are rendered by different surfaces; a resemblance
  between them proves nothing about either.

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

[1]: https://code.claude.com/docs/en/statusline

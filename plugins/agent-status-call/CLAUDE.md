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

# Changelog

All notable changes to this plugin are documented in this file.

The format is based on [Keep a Changelog][1], and this project adheres to
[Semantic Versioning][2].

## [1.1.1] - 2026-08-21

### Documentation

- Added this `CHANGELOG.md`, tracking notable changes to the plugin release
  by release, following Keep a Changelog.
- README describes each status line's fields in general terms (model/effort,
  status, context usage, name, description, token count) instead of walking
  through one specific example, and refreshes the example screenshot to
  match.

## [1.1.0] - 2026-08-15

### Added

- `subagent-status-line.sh` now shows each task's `.status` right after the
  model/effort bracket, so a task's state is visible at a glance without
  switching to the main statusline.
- `subagent-status-line.sh` replaces the bare token count with a
  context-usage bar built from `tokenCount` and `contextWindowSize`,
  matching `status-line.sh`'s bar style. Falls back to the old bare token
  count when `contextWindowSize` isn't available.

### Documentation

- README documents the minimum Claude Code version required for each task
  field, per the official statusline docs.
- README shows an example screenshot of the status-line and agent-panel
  output, with a caption tying each line back to the script that produced
  it.

## [1.0.0] - 2026-08-11

Initial release as part of the `homers-drinking-bird` multi-plugin
marketplace.

[1]: https://keepachangelog.com/en/1.1.0/
[2]: https://semver.org/spec/v2.0.0.html

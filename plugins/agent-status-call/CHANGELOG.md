# Changelog

All notable changes to this plugin are documented in this file.

The format is based on [Keep a Changelog][1], and this project adheres to
[Semantic Versioning][2].

## [1.2.0] - 2026-08-22

### Added

- Both status lines are now coloured: model, effort, and branch/bookmark
  each get their own colour, and every percentage (context usage, the
  5-hour and 7-day rate-limit windows, the subagent context bar) carries a
  green/yellow/red severity ramp, so a status line that needs attention
  looks different from one that doesn't. Colour uses 16-colour ANSI codes
  only, chosen to stay legible across terminal themes without needing
  truecolor support.
- Set [`NO_COLOR`][3] to any non-empty value to disable colour in both
  scripts; with it set, output is unchanged from before this release.

### Changed

- `status-line.sh` no longer spawns `hg` when the working directory isn't a
  Mercurial repository, removing a delay (previously ~0.3-0.5s per refresh)
  from every git repo and every directory outside any repo.

### Documentation

- README describes the colour scheme (field colours, ramp thresholds,
  `NO_COLOR`) and adds a "Testing colour" section with byte-stripping and
  JSON-validity checks for both scripts.

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
[3]: https://no-color.org

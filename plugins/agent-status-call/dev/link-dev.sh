#!/bin/bash
# Dev tool, not part of the published plugin: points
# ~/.claude/scripts/status-line.sh and ~/.claude/scripts/subagent-status-line.sh
# at this checkout's scripts/, so Claude Code picks up local edits without a
# plugin reinstall.
#
# Usage:
#   dev/link-dev.sh on       # point both symlinks at this checkout (default)
#   dev/link-dev.sh off      # restore whatever they pointed at before `on`
#   dev/link-dev.sh status   # show what each symlink currently points at
#
# `on` records each symlink's prior target (if any) before overwriting it, so
# `off` restores it exactly -- including a specific versioned
# plugin-cache path from a real install, or "absent" if nothing was linked
# yet. Refuses to run `on` again while already on, so the recorded prior
# target is never itself a dev pointer.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$HOME/.claude/scripts"
STATE_DIR="$TARGET_DIR/.agent-status-call-dev-state"

STATUS_LINK="$TARGET_DIR/status-line.sh"
SUBAGENT_LINK="$TARGET_DIR/subagent-status-line.sh"
DEV_STATUS="$SCRIPT_DIR/scripts/status-line.sh"
DEV_SUBAGENT="$SCRIPT_DIR/scripts/subagent-status-line.sh"

mode="${1:-on}"

save_prior() {
  local link="$1" name="$2"

  if [ -L "$link" ]; then
    readlink "$link" > "$STATE_DIR/$name"
  elif [ -e "$link" ]; then
    echo "error: $link exists and is not a symlink -- refusing to touch it" >&2
    exit 1
  fi
}

restore_prior() {
  local link="$1" name="$2"

  if [ -f "$STATE_DIR/$name" ]; then
    ln -sf "$(cat "$STATE_DIR/$name")" "$link"
  else
    rm -f "$link"
  fi
}

show_link() {
  local link="$1"

  if [ -L "$link" ]; then
    echo "$link -> $(readlink "$link")"
  elif [ -e "$link" ]; then
    echo "$link (exists, not a symlink)"
  else
    echo "$link (absent)"
  fi
}

case "$mode" in
  on)
    if [ -d "$STATE_DIR" ]; then
      echo "error: dev links already active ($STATE_DIR exists) -- run 'off' first" >&2
      exit 1
    fi

    mkdir -p "$TARGET_DIR" "$STATE_DIR"
    trap 'rm -rf "$STATE_DIR"' EXIT

    save_prior "$STATUS_LINK" status-line.sh
    save_prior "$SUBAGENT_LINK" subagent-status-line.sh

    ln -sf "$DEV_STATUS" "$STATUS_LINK"
    ln -sf "$DEV_SUBAGENT" "$SUBAGENT_LINK"

    trap - EXIT

    show_link "$STATUS_LINK"
    show_link "$SUBAGENT_LINK"
    ;;
  off)
    if [ ! -d "$STATE_DIR" ]; then
      echo "error: no dev links active ($STATE_DIR not found)" >&2
      exit 1
    fi

    restore_prior "$STATUS_LINK" status-line.sh
    restore_prior "$SUBAGENT_LINK" subagent-status-line.sh
    rm -rf "$STATE_DIR"

    show_link "$STATUS_LINK"
    show_link "$SUBAGENT_LINK"
    ;;
  status)
    show_link "$STATUS_LINK"
    show_link "$SUBAGENT_LINK"
    ;;
  *)
    echo "usage: $(basename "$0") [on|off|status]" >&2
    exit 1
    ;;
esac

#!/bin/bash
# Claude Code statusline: shows model, context-window usage, git/hg branch, and
# Claude.ai rate-limit windows.
#
# Claude Code invokes this script once per refresh with a JSON object describing the
# current session on stdin, and renders whatever this script prints to stdout as the
# top-of-screen status line.
#
# Requires jq. If jq is not on PATH, prints "jq not present on system" and exits —
# there is no fallback parser.
#
# Output shape:
#   Model [effort] | [██░░░░░░░░] 30% | branch | ⏱ 42% (in 3h) · 18% (in 2d)
#
# Segments (always separated by " | ", only emitted when their data is present):
#   1. Model    - .model.display_name, falling back to .model.id, then "Unknown",
#                 followed by the reasoning effort in brackets: .effort.level, or
#                 "auto" when that field is absent (the current model doesn't
#                 support the effort parameter, or an older Claude Code version).
#                 Always shown, e.g. "Opus 5 [high]".
#   2. Context  - .context_window.used_percentage rounded to an integer and rendered
#                 as a 10-block bar. Shows "[░░░░░░░░░░] --%" when the field is
#                 missing, so the slot always renders. Always shown.
#   3. Git/Hg   - .cwd (falling back to .workspace.current_dir) is checked for a git
#                 or hg repo. Branch comes from `git --no-optional-locks rev-parse
#                 --abbrev-ref HEAD` (the --no-optional-locks flag keeps this
#                 read-only statusline from ever touching the index lock) or `hg
#                 activebookmark`. Omitted if the cwd isn't a repo, or if the repo
#                 has no resolvable branch/bookmark (e.g. no active hg bookmark).
#   4. Rate     - .rate_limits.five_hour / .rate_limits.seven_day used_percentage +
#      limits     resets_at. The API has been seen using both snake_case
#                 (five_hour/seven_day/resets_at) and camelCase
#                 (fiveHour/sevenDay/resetsAt) for this object, so each window is
#                 looked up snake_case-first then camelCase, and resets_at/resetsAt
#                 is resolved the same way inside whichever window object was found.
#                 Omitted entirely when .rate_limits is absent (it only appears
#                 after the first API response in a Claude.ai session) or when
#                 neither window has a used_percentage. A window with a percentage
#                 but no usable resets_at is shown as a bare percentage.
#
#                 The seven-day window also gets a daily pace check: each of the
#                 first 6 days of the week gets a 14.25% budget (so day N's
#                 cumulative cap is N * 14.25%), and the 7th day is uncapped
#                 (100%) so the whole remaining balance can be spent. "Day" is
#                 computed from how much of the 7-day window has elapsed, derived
#                 from resets_at (elapsed = 7d - time-until-reset). If the
#                 seven-day used_percentage exceeds its current day's cap, a "!"
#                 is appended right after the "%" (e.g. "28.5%!" on day 2), so
#                 pace overruns are visible at a glance. Skipped whenever
#                 resets_at is missing/unparseable, same as the countdown itself.
#
# Timestamp parsing (resets_at):
#   Three accepted shapes: ISO 8601 with a "Z" suffix, ISO 8601 with a "+HH:MM"
#   offset, and a plain Unix epoch in seconds or milliseconds (13+ digits is treated
#   as milliseconds). Unparseable timestamps are treated as missing, which drops the
#   countdown but keeps the bare percentage.
#
#   This runs under both BSD date (macOS) and GNU date (Linux), which take the ISO
#   forms differently — BSD's `-f` needs an exact format match with no timezone
#   suffix, GNU's `-d` accepts the ISO string as-is. Rather than branch on every
#   call, the script picks once at startup: `parse_timestamp_bsd` and
#   `parse_timestamp_gnu` each implement the full parse for their flavor, and
#   whichever one applies (detected via `date --version`, which GNU date supports
#   and BSD date doesn't) is aliased to `parse_timestamp` as a wrapper function
#   (see "OS detection" below). Everything downstream — `render_window`, in
#   particular — calls plain `parse_timestamp` and never checks which OS it's on.
#
# Countdown rounding:
#   Both windows round to the nearest unit rather than flooring, since flooring
#   would show "in 1d" for a reset that's actually 41h away. The 5-hour window
#   counts down in minutes under 1h, hours otherwise. The 7-day window counts down
#   in hours under 1d, days otherwise.

set -uo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not present on system"
  exit 0
fi

input=$(cat)

jqr() {
  printf '%s' "$input" | jq -r "$1" 2>/dev/null
}

# Converts a bare Unix epoch string (seconds, or milliseconds at 13+ digits) to
# seconds. Returns 1 with no output if $1 isn't purely digits, so callers fall
# through to their OS-specific ISO 8601 parsing. Shared by both parse_timestamp_*
# functions below since this part doesn't touch `date` and has no OS split.
epoch_from_numeric() {
  local ts="$1"

  [[ "$ts" =~ ^[0-9]+$ ]] || return 1

  if [ "${#ts}" -ge 13 ]; then
    echo $(( ts / 1000 ))
  else
    echo "$ts"
  fi
}

# BSD date (macOS): -f requires an exact format match and rejects a trailing
# timezone suffix outright, so the "Z" or "+HH:MM" offset and any fractional
# seconds are stripped first and what's left is treated as a bare UTC timestamp.
# Prints nothing and returns non-zero if $1 can't be parsed.
parse_timestamp_bsd() {
  local ts="$1" epoch stripped

  epoch_from_numeric "$ts" && return 0

  stripped=$(printf '%s' "$ts" | sed -E 's/\.[0-9]+//; s/(Z|[+-][0-9]{2}:?[0-9]{2})$//')
  epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$stripped" "+%s" 2>/dev/null)
  if [ -n "$epoch" ]; then
    echo "$epoch"
    return 0
  fi

  return 1
}

# GNU date (Linux): -d parses ISO 8601 directly — "Z" suffix, "+HH:MM" offset, and
# fractional seconds are all handled natively, so the string is passed through
# unmodified. Prints nothing and returns non-zero if $1 can't be parsed.
parse_timestamp_gnu() {
  local ts="$1" epoch

  epoch_from_numeric "$ts" && return 0

  epoch=$(date -u -d "$ts" "+%s" 2>/dev/null)
  if [ -n "$epoch" ]; then
    echo "$epoch"
    return 0
  fi

  return 1
}

# OS detection: GNU date supports --version (and prints "date (GNU coreutils)...");
# BSD date treats it as a bad option and exits non-zero. Picked once at startup and
# aliased to parse_timestamp as a wrapper function — a plain `alias` doesn't
# reliably apply in non-interactive scripts, so a function is used instead. Every
# caller below uses parse_timestamp and is unaware which OS it resolved to.
if date --version >/dev/null 2>&1; then
  parse_timestamp() { parse_timestamp_gnu "$@"; }
else
  parse_timestamp() { parse_timestamp_bsd "$@"; }
fi

# Formats a countdown in seconds as e.g. "3h" or "42m", rounded to the nearest unit.
# mode is "5h" (minutes under 1h, else hours) or "7d" (hours under 1d, else days).
format_countdown() {
  local diff="$1" mode="$2" value unit

  if [ "$mode" = "5h" ]; then
    if [ "$diff" -lt 3600 ]; then
      value=$(awk -v d="$diff" 'BEGIN { printf "%.0f", d / 60 }')
      unit="m"
    else
      value=$(awk -v d="$diff" 'BEGIN { printf "%.0f", d / 3600 }')
      unit="h"
    fi
  else
    if [ "$diff" -lt 86400 ]; then
      value=$(awk -v d="$diff" 'BEGIN { printf "%.0f", d / 3600 }')
      unit="h"
    else
      value=$(awk -v d="$diff" 'BEGIN { printf "%.0f", d / 86400 }')
      unit="d"
    fi
  fi

  echo "${value}${unit}"
}

# Renders one rate-limit window ("42% (in 3h)" or, without a usable reset, "42%").
# For the 7d window, also flags pace overruns against the daily budget (see header
# comment) with a trailing "!" right after the "%", e.g. "28.5%! (in 5d)".
# Prints nothing if pct is empty.
render_window() {
  local pct="$1" reset="$2" mode="$3" pct_int out epoch now diff exceeded

  [ -z "$pct" ] && return 0

  pct_int=$(awk -v p="$pct" 'BEGIN { printf "%.0f", p }')
  out="${pct_int}%"

  if [ -n "$reset" ]; then
    if epoch=$(parse_timestamp "$reset"); then
      now=$(date -u +%s)
      diff=$(( epoch - now ))

      if [ "$mode" = "7d" ]; then
        exceeded=$(awk -v p="$pct" -v diff="$diff" 'BEGIN {
          elapsed = 7 * 86400 - diff
          if (elapsed < 0) elapsed = 0
          if (elapsed >= 7 * 86400) elapsed = 7 * 86400 - 1
          day = int(elapsed / 86400) + 1
          cap = (day >= 7) ? 100 : day * 14.25
          print (p > cap) ? 1 : 0
        }')
        [ "$exceeded" = "1" ] && out="${out}!"
      fi

      [ "$diff" -lt 0 ] && diff=0
      out="${out} (in $(format_countdown "$diff" "$mode"))"
    fi
  fi

  echo "$out"
}

# Rounds a percentage string to the nearest integer, half rounding up (0.5 -> 1,
# not 0) to match the context-window path's existing behavior.
round_pct() {
  awk -v p="$1" 'BEGIN { printf "%d", int(p + 0.5) }'
}

# Renders a 10-block usage bar for an integer percentage (0-100), e.g.
# "[███░░░░░░░]" (bar fill is floor(pct / 10), so percentages under 10% show no
# filled blocks).
render_bar() {
  local pct="$1" filled empty bar

  filled=$(( pct * 10 / 100 ))
  empty=$(( 10 - filled ))
  bar=""
  [ "$filled" -gt 0 ] && bar="$(printf '█%.0s' $(seq 1 "$filled"))"
  [ "$empty" -gt 0 ] && bar="${bar}$(printf '░%.0s' $(seq 1 "$empty"))"
  echo "[${bar}]"
}

# Joins the non-empty arguments after SEP with SEP, dropping empty ones — so a
# missing segment doesn't leave a stray separator behind.
join_by() {
  local sep="$1" out="" part
  shift

  for part in "$@"; do
    [ -z "$part" ] && continue
    if [ -z "$out" ]; then
      out="$part"
    else
      out="${out}${sep}${part}"
    fi
  done

  echo "$out"
}

# Walks up from CWD looking for a .hg or .git marker and asks only that VCS for
# a branch/bookmark — stops at the first marker found, so a directory nested in
# both (which doesn't occur in practice) is never arbitrated between them. This
# avoids spawning hg in every directory, including git repos and non-repos,
# where it always failed after ~0.34s.
detect_branch() {
  local cwd="$1" dir="$1" vcs=""

  while :; do
    if [ -e "$dir/.hg" ]; then
      vcs="hg"
      break
    elif [ -e "$dir/.git" ]; then
      vcs="git"
      break
    elif [ "$dir" = "/" ]; then
      break
    fi
    dir=$(dirname "$dir")
  done

  case "$vcs" in
    hg)
      command -v hg >/dev/null 2>&1 && hg --cwd "$cwd" activebookmark 2>/dev/null
      ;;
    git)
      git --no-optional-locks -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null
      ;;
  esac
}

# --- Segment 1: model ---

MODEL=$(jqr '.model.display_name // .model.id // "Unknown"')
EFFORT=$(jqr '.effort.level // "auto"')

# --- Segment 2: context battery ---

CTX_PCT_RAW=$(jqr '.context_window.used_percentage // empty')

if [ -z "$CTX_PCT_RAW" ]; then
  CTX_SEGMENT="$(render_bar 0) --%"
else
  CTX_PCT=$(round_pct "$CTX_PCT_RAW")
  [ "$CTX_PCT" -lt 0 ] && CTX_PCT=0
  [ "$CTX_PCT" -gt 100 ] && CTX_PCT=100

  CTX_SEGMENT="$(render_bar "$CTX_PCT") ${CTX_PCT}%"
fi

# --- Segment 3: git/hg branch ---

CWD=$(jqr '.cwd // .workspace.current_dir // empty')
GIT_SEGMENT=""

if [ -n "$CWD" ] && [ -d "$CWD" ]; then
  GIT_SEGMENT=$(detect_branch "$CWD")
fi

# --- Segment 4: Claude.ai rate limits ---

FIVE_HOUR_PCT=$(jqr '(.rate_limits.five_hour // .rate_limits.fiveHour // {}) | .used_percentage // empty')
FIVE_HOUR_RESET=$(jqr '(.rate_limits.five_hour // .rate_limits.fiveHour // {}) | (.resets_at // .resetsAt) // empty')
SEVEN_DAY_PCT=$(jqr '(.rate_limits.seven_day // .rate_limits.sevenDay // {}) | .used_percentage // empty')
SEVEN_DAY_RESET=$(jqr '(.rate_limits.seven_day // .rate_limits.sevenDay // {}) | (.resets_at // .resetsAt) // empty')

FIVE_HOUR_RENDERED=$(render_window "$FIVE_HOUR_PCT" "$FIVE_HOUR_RESET" "5h")
SEVEN_DAY_RENDERED=$(render_window "$SEVEN_DAY_PCT" "$SEVEN_DAY_RESET" "7d")

RATE_JOINED=$(join_by " · " "$FIVE_HOUR_RENDERED" "$SEVEN_DAY_RENDERED")
RATE_SEGMENT=""
[ -n "$RATE_JOINED" ] && RATE_SEGMENT="⏱ ${RATE_JOINED}"

# --- Composition ---

OUTPUT=$(join_by " | " "${MODEL} [${EFFORT}]" "$CTX_SEGMENT" "$GIT_SEGMENT" "$RATE_SEGMENT")

echo "$OUTPUT"

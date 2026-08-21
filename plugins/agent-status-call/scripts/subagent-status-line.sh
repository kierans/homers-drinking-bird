#!/bin/bash
# Claude Code subagent statusline: overrides each row in the agent panel to show
# that subagent's own resolved model/effort alongside its name, description, and
# token usage — Claude Code's default row only shows "name · description · token
# count" and the top-level statusLine only ever sees the main session's model.
# Requires jq; without it, default row rendering is left untouched.
#
# Claude Code invokes this script once per refresh with a JSON object on stdin
# containing a "tasks" array, one entry per subagent currently shown in the panel.
# For each task this script wants to override, it writes one JSON line to stdout in
# the form {"id": "<task id>", "content": "<row text>"}; tasks it doesn't emit a line
# for keep Claude Code's default row rendering.
#
# Row shape:
#   [Model:effort] · status · name · description · [██░░░░░░░░] 6% (12.4k tokens)
#
# - [Model:effort] - .model prettified (see prettify_model below), and .effort,
#   defaulting to "auto" when absent (task inherits the session's effort level, or
#   the field predates Claude Code v2.1.214). Always shown.
# - status         - .status, tostring. Omitted when absent.
# - name           - .name. Omitted when absent.
# - description    - .description. Omitted when absent.
# - context/tokens - built from .tokenCount and .contextWindowSize (both require
#   Claude Code v2.1.205 or later; contextWindowSize is that task's model's context
#   window in tokens):
#     - both present and contextWindowSize > 0: a 10-block usage bar (same style as
#       status-line.sh's context bar) plus the percentage (tokenCount /
#       contextWindowSize, rounded to the nearest integer, clamped to 0-100),
#       followed by the token count in parentheses, e.g.
#       "[░░░░░░░░░░] 6% (12.4k tokens)" (bar fill is floor(pct / 10), so
#       percentages under 10% show no filled blocks).
#     - tokenCount present but contextWindowSize missing or non-positive (e.g.
#       Claude Code older than v2.1.205): falls back to the bare "12.4k tokens"
#       form.
#     - tokenCount absent (task's model isn't resolved yet): segment omitted
#       entirely.
#   Token counts are formatted as "12.4k tokens" above 1000 (one decimal place,
#   floored) or a bare count below.
#
# Colour:
#   16-colour (4-bit) ANSI codes only, never 256-colour or truecolor — same
#   rule as status-line.sh, chosen independently since the two scripts don't
#   share an implementation. Model is cyan (36), effort is dim cyan (2;36),
#   name is bold with no colour (1), status is green (32), description is dim
#   (2). The context bar and its percentage carry the severity ramp: green
#   (32) under 50%, yellow (33) at 50-79%, red (31) at 80% and over, with the
#   bar's filled run and the percentage sharing the same ramp colour.
#   Brackets, ":", "·", and the token count are dim (2) chrome. NO_COLOR
#   (https://no-color.org, any non-empty value, not just "1") disables colour
#   entirely; with it set, this script emits exactly the bytes it emitted
#   before colour was added.
#
#   The row text is embedded inside a JSON string, so the escapes are built by
#   the jq program itself (an ANSI escape control byte opening a "[" + code +
#   "m" span, closed the same way), and the colour flag is passed in as
#   --argjson colour (0 or 1, from NO_COLOR) rather than read from an
#   environment variable inside jq. Verified that jq -c re-encodes the
#   embedded escape byte as a valid \u sequence in its JSON output, and that
#   decoding that string back out (jq -r .content) yields the real escape byte
#   again. Whether Claude Code's own decode matches was not directly
#   observable, but the subagent status line docs state that `content` "is
#   rendered as-is, including ANSI colors and OSC 8 hyperlinks".
#
# Example input (stdin):
#   {
#     "tasks": [
#       {
#         "id": "t1",
#         "model": "claude-opus-5",
#         "effort": "high",
#         "status": "running",
#         "name": "code-reviewer",
#         "description": "Reviewing the diff for bugs",
#         "tokenCount": 12400,
#         "contextWindowSize": 200000
#       }
#     ]
#   }
#
# Example output (stdout, one JSON line per task):
#   {"id":"t1","content":"[Opus 5:high] · running · code-reviewer · Reviewing the diff for bugs · [░░░░░░░░░░] 6% (12.4k tokens)"}

input=$(cat)

command -v jq >/dev/null 2>&1 || exit 0

# NO_COLOR (https://no-color.org): any non-empty value disables colour, so the
# test is emptiness, never a string comparison against "1" or similar. Passed
# into jq as --argjson since the row text is built entirely inside the program.
if [ -n "${NO_COLOR:-}" ]; then
  USE_COLOUR=0
else
  USE_COLOUR=1
fi

printf '%s' "$input" | jq -c --argjson colour "$USE_COLOUR" '
  def prettify_model:
    if . == null or . == "" then "unknown"
    else
      sub("^claude-"; "")
      | split("-")
      | map(select(test("^[0-9]{8}$") | not))
      | if length == 0 then "unknown"
        else
          (.[0][0:1] | ascii_upcase) + .[0][1:] as $name
          | (.[1:]) as $version
          | if ($version | length) > 0 then
              $name + " " + ($version | join("."))
            else
              $name
            end
        end
    end;

  def format_tokens:
    if . == null then null
    elif . >= 1000 then
      (((. / 1000 * 10 | floor) / 10 | tostring) + "k")
    else
      (. | tostring)
    end;

  # Wraps $s in the given SGR $c, resetting after. A no-op when colour is off or
  # $s is empty/null — painting an empty string would otherwise produce a
  # non-empty run of bare escapes, turning an absent segment into a rendered
  # one. This is also what makes "█" * 0 safe: it is null on jq 1.6 and "" on
  # jq 1.7+, and paint treats both the same.
  def paint($c; $s):
    ($s // "") as $t
    | if $colour == 1 and $t != "" then "[" + $c + "m" + $t + "[0m" else $t end;

  # The severity ramp shared by every percentage this script renders: green
  # under 50%, yellow 50-79%, red 80% and over.
  def pct_colour($p):
    if $p >= 80 then "31" elif $p >= 50 then "33" else "32" end;

  # A 10-block usage bar for an integer percentage (0-100). The fill takes the
  # severity ramp colour, the empty run is dim chrome.
  def bar($pct):
    ($pct / 10 | floor) as $filled
    | paint(pct_colour($pct); "█" * $filled) + paint("2"; "░" * (10 - $filled));

  def context_segment(tokenCount; contextWindowSize):
    if tokenCount == null then null
    elif contextWindowSize == null or contextWindowSize <= 0 then
      paint("2"; (tokenCount | format_tokens) + " tokens")
    else
      ((tokenCount / contextWindowSize * 100) + 0.5 | floor) as $raw
      | (if $raw < 0 then 0 elif $raw > 100 then 100 else $raw end) as $pct
      | paint("2"; "[") + bar($pct) + paint("2"; "] ")
        + paint(pct_colour($pct); ($pct | tostring) + "%")
        + paint("2"; " (" + (tokenCount | format_tokens) + " tokens)")
    end;

  .tasks[]?
  | select(.id != null)
  | . as $t
  | context_segment($t.tokenCount; $t.contextWindowSize) as $ctx
  | (
      paint("2"; "[") + paint("36"; $t.model | prettify_model) + paint("2"; ":")
      + paint("2;36"; ($t.effort // "auto") | tostring) + paint("2"; "]")
    ) as $header
  | (if $t.status then paint("32"; $t.status | tostring) else null end) as $status
  | (if $t.name then paint("1"; $t.name) else null end) as $name
  | (if $t.description then paint("2"; $t.description) else null end) as $description
  | {
      id: $t.id,
      content: (
        [$header, $status, $name, $description, $ctx]
        | map(select(. != null and . != ""))
        | join(paint("2"; " · "))
      )
    }
'

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

printf '%s' "$input" | jq -c '
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

  def context_segment(tokenCount; contextWindowSize):
    if tokenCount == null then null
    elif contextWindowSize == null or contextWindowSize <= 0 then
      (tokenCount | format_tokens) + " tokens"
    else
      ((tokenCount / contextWindowSize * 100) + 0.5 | floor) as $raw
      | (if $raw < 0 then 0 elif $raw > 100 then 100 else $raw end) as $pct
      | ($pct / 10 | floor) as $filled
      | (10 - $filled) as $empty
      | ((if $filled > 0 then "█" * $filled else "" end) + (if $empty > 0 then "░" * $empty else "" end)) as $bar
      | "[" + $bar + "] " + ($pct | tostring) + "% (" + (tokenCount | format_tokens) + " tokens)"
    end;

  .tasks[]?
  | select(.id != null)
  | . as $t
  | context_segment($t.tokenCount; $t.contextWindowSize) as $ctx
  | {
      id: $t.id,
      content: (
        "[" + ($t.model | prettify_model) + ":" + (($t.effort // "auto") | tostring) + "]"
        + (if $t.status then " · " + ($t.status | tostring) else "" end)
        + (if $t.name then " · " + $t.name else "" end)
        + (if $t.description then " · " + $t.description else "" end)
        + (if $ctx then " · " + $ctx else "" end)
      )
    }
'

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
#   [Model:effort] · name · description · tokenCount tokens
#
# - [Model:effort] - .model prettified (see prettify_model below), and .effort,
#   defaulting to "auto" when absent (task inherits the session's effort level, or
#   the field predates Claude Code v2.1.214). Always shown.
# - name           - .name. Omitted when absent.
# - description    - .description. Omitted when absent.
# - tokenCount      - .tokenCount, formatted as "12.4k tokens" above 1000 (one
#   decimal place, floored) or a bare count below. Omitted when absent, e.g. for a
#   task whose model isn't resolved yet.
#
# Example input (stdin):
#   {
#     "tasks": [
#       {
#         "id": "t1",
#         "model": "claude-opus-5",
#         "effort": "high",
#         "name": "code-reviewer",
#         "description": "Reviewing the diff for bugs",
#         "tokenCount": 12400
#       }
#     ]
#   }
#
# Example output (stdout, one JSON line per task):
#   {"id":"t1","content":"[Opus 5:high] · code-reviewer · Reviewing the diff for bugs · 12.4k tokens"}

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

  .tasks[]?
  | select(.id != null)
  | {
      id: .id,
      content: (
        "[" + (.model | prettify_model) + ":" + ((.effort // "auto") | tostring) + "]"
        + (if .name then " · " + .name else "" end)
        + (if .description then " · " + .description else "" end)
        + (if .tokenCount then " · " + (.tokenCount | format_tokens) + " tokens" else "" end)
      )
    }
'

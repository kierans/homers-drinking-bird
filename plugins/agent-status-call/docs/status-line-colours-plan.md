# Plan: colour for both status lines

Status: proposed · Target version: 1.2.0

Add ANSI colour to `scripts/status-line.sh` and `scripts/subagent-status-line.sh`
so the model, effort, branch and every percentage are distinguishable at a glance, and so a
status line that needs attention *looks* different from one that doesn't. Colour is emitted with
the 16-colour (4-bit) codes only, ramps green → yellow → red with load, and is suppressed
entirely by [`NO_COLOR`][1].

## Goals

- The four identity fields (model, effort, branch, subagent name) read as distinct from the
  chrome around them.
- Every percentage the plugin renders carries a severity colour, so peripheral vision catches a
  full context window or a rate-limit window running hot.
- The plugin looks native on whatever terminal theme the user already runs.
- Colour is fully removable, and removing it changes nothing but the escapes.

## Non-goals

- Truecolor / 24-bit output. Considered and rejected for this change: it fixes hues chosen for a
  dark ground, washes out on light profiles, needs explicit tmux configuration, and costs 19
  bytes per span against 5. A `COLORTERM` upgrade path stays open (see "Later, if wanted").
- 256-colour codes. Same objection, less benefit.
- Any change to which segments render, in what order, or to their text. This change is escapes
  only.
- A plugin-specific opt-out variable. `NO_COLOR` is the whole opt-out.

## Decisions

### Colour model

16-colour codes (`30`–`37`) plus the `2` (dim) attribute. Deliberately **not**
used:

| Avoided                | Why                                                                                                                                                                        |
|------------------------|----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `90`–`97` (bright)     | On Solarized Dark, ANSI 8 is `#002b36` — the background. Separators in `90` vanish.                                                                                        |
| `1;3x` (bold + colour) | Where the terminal renders bold as bright, Solarized maps bright green/cyan onto its `base01`/`base1` greys and bright red onto orange. A bold cyan model name reads grey. |

`2` (dim) is used for all chrome instead. The terminal computes it from the live foreground
colour, so it stays legible on every theme rather than resolving to a fixed palette slot.

Gruvbox Dark keeps its punchy colours in the bright slots, so plain `31` there is the restrained
`#cc241d`. The ramp still reads correctly; it is simply quieter on that theme. Accepted.

### The field → code contract

| Field                                             | Code                | Notes                                                                             |
|---------------------------------------------------|---------------------|-----------------------------------------------------------------------------------|
| Model name                                        | `36` cyan           | Both scripts. Weight (`1`) may be applied separately where it already reads well. |
| Effort                                            | `2;36` dim cyan     | Subordinate to the model it qualifies.                                            |
| Branch / bookmark                                 | `32` green          | Main line only.                                                                   |
| Subagent name                                     | `1` bold, no colour | Inherits the theme foreground; the panel already carries a lot of hue.            |
| Subagent status                                   | `32` green          |                                                                                   |
| Subagent description                              | `2` dim             |                                                                                   |
| Context bar — filled                              | ramp                | Same colour as the percentage beside it.                                          |
| Context bar — empty                               | `2` dim             |                                                                                   |
| Brackets, `\|`, `·`, `⏱`, countdowns, token count | `2` dim             | Chrome recedes.                                                                   |
| Every percentage                                  | ramp                | See below.                                                                        |
| 7-day pace flag `!`                               | `31` red            | Independent of the percentage's own ramp.                                         |

### The severity ramp

One threshold function, four call sites: the context bar, the 5-hour window, the 7-day window,
and the subagent token bar.

| Load         | Code | Colour |
|--------------|------|--------|
| under 50%    | `32` | green  |
| 50–79%       | `33` | yellow |
| 80% and over | `31` | red    |

The pace flag keeps its own signal. At 61% on day 2 the 7-day figure is still yellow (it is
under 80%) while the trailing `!` is red (it is ahead of its daily budget). Two independent
facts, two independent colours; folding them together would lose one.

The `--%` placeholder shown when `.context_window.used_percentage` is absent is dim, not
ramped — there is no load to report.

### The opt-out

`NO_COLOR` set to **any non-empty value** disables colour in both scripts. That is the
convention's rule — presence, not `=1` — so the test is emptiness, never a string comparison:

```bash
if [ -n "${NO_COLOR:-}" ]; then USE_COLOUR=0; else USE_COLOUR=1; fi
```

With colour off, both scripts emit the exact bytes they emit today. That is the acceptance
criterion, and it is testable (see Testing).

## Structure: what to extract

Measured on this repo before any change, 20 runs each:

| Case                       | Per refresh | Dominated by                                             |
|----------------------------|-------------|----------------------------------------------------------|
| `status-line.sh`, hg repo  | ~1.15 s     | two `hg` spawns — `root` 0.34 s, `activebookmark` 0.65 s |
| `status-line.sh`, git repo | ~0.47 s     | an `hg root` that always fails                           |
| `status-line.sh`, no repo  | ~0.48 s     | the same failing `hg root`                               |
| `subagent-status-line.sh`  | ~0.03 s     | one `jq`                                                 |

Colour is not what costs anything here: 400 command substitutions measure ~0.29 s, so ~20 
`paint` calls add ~15 ms per refresh. Choosing between a `paint` function and pre-resolved 
colour variables is therefore a readability decision, not a performance one, and this plan 
keeps `paint` — a single wrapper means the `\033[0m` reset cannot be forgotten at a call site.

### `detect_branch CWD` — segment 3, extracted

Segment 3 is currently ten inline lines that spawn `hg` in **every** directory, including git
repos and non-repos, where it always fails after ~0.34 s. Extract it, and have it decide which
VCS to ask by walking up from `CWD` for a `.hg` or `.git` marker — a bash loop over directory 
names, no subprocess — before spawning anything. That removes the wasted `hg` call from every 
git and non-repo session and is the single largest improvement available to this script.

A directory inside both an hg and a git repo does not occur in practice, so the function does
not arbitrate between them: the walk stops at the first `.hg` or `.git` it finds and asks that
VCS only. That also disposes of the current code's accidental behaviour, where the hg block —
not being an `elif` — overwrites whatever git returned.

### `round_pct VALUE` — one rounding rule

The two percentage paths round differently today, and it is a real divergence:

| Input | `render_window` (`awk "%.0f"`) | context bar (`. + 0.5 \| floor`) |
|-------|--------------------------------|----------------------------------|
| 42.5  | 42                             | 43                               |
| 0.5   | 0                              | 1                                |

`awk`'s `%.0f` rounds half to even; the context path rounds half up. A single `round_pct` 
helper used by both makes the ramp key off one rule, which matters once a colour boundary sits 
at exactly 50 or 80. Round half up, matching the existing context behaviour and the documented 
output.

### `render_bar PCT` — the 10-block bar

Built inline today across six lines with a `seq`-driven `printf`. Colour adds a painted fill
run, a painted empty run and painted brackets, which would make it the longest thing in the
script. Extract it and both the normal and the `[░░░░░░░░░░] --%` fallback branch stay one 
line each.

### `join_by SEP PARTS...` — composition, three sites

The same "join what is present, skip what is not" logic is hand-rolled three times: the final
`OUTPUT` assembly with two conditional appends, the two-window rate join with its nested `if`,
and — in `jq` — the subagent row's four `(if $t.X then " · " + … else "" end)` clauses.

All three collapse to one helper that takes a separator and a list, drops the empty entries, and
joins the rest. Beyond being shorter, it is what makes colour tractable: the ` | ` and ` · `
separators get painted **once**, in the helper, instead of at seven call sites where one will
eventually be missed.

In `jq` the same shape is native:

```
[ $header, $status, $t.name, $t.description, $ctx ]
| map(select(. != null and . != ""))
| join(paint("2"; " · "))
```

Note the ordering trap: `$t.status | tostring` on an absent field yields the string `"null"`, so
the `select` has to happen before any `tostring`.

### `paint CODE TEXT` and `pct_colour PCT`

As described above. One rule governs every call site:

> **Never paint before testing for emptiness.** Painting `""` yields a
> 9-character string, so `[ -n "$X" ]` becomes true and an absent segment
> renders as bare escapes. Every `-n` guard and every `jq` `select` must see
> the raw value; painting happens at composition time only.

This is the one way the colour change can break existing behaviour, and it is why segments are
painted where they are joined rather than where they are extracted.

### The jq programs

Both scripts run `jq`: `status-line.sh` makes nine separate one-line calls, and
`subagent-status-line.sh` runs a single program with three `def`s. Each was reviewed on its own
terms — the two scripts consume different inputs and produce different outputs, so nothing here
proposes a shared implementation or a shared name between them.

**Within `status-line.sh`, four of the nine filters are one shape.** Each rate-limit window is
looked up snake_case-first then camelCase, written out once for the percentage and again for the
reset timestamp — four filters carrying the same fallback:

```
def window($snake; $camel): .rate_limits[$snake] // .rate_limits[$camel] // {};
```

One `def`, four call sites, and the snake/camel rule stated once instead of four times. Two more
of the nine read `.context_window.used_percentage` twice — once to test presence, once to round
it — which a single call returning either the rounded value or `empty` collapses to one.

Both only pay off if the nine calls become one program, which is deferred (see *Not extracted*),
so they are recorded here and deferred with it. Neither changes any output.

**Within `subagent-status-line.sh`, the clamp and the round are inline.** The program computes
`((tokenCount / contextWindowSize * 100) + 0.5 | floor)` and then clamps it with a three-branch
`if`, all inside `context_segment`, which also builds the bar and assembles the text. Splitting
`round_pct`, `clamp_pct` and `bar` out leaves `context_segment` doing one job, and gives the
colour change somewhere to attach that is not the middle of a string concatenation.

**A correction to this plan's own `bar` def.** The version sketched below paints the fill and
empty runs unconditionally, which breaks at the ends of the range: `paint("32"; "█" * 0)` emits
`\u001b[32m\u001b[0m` — a colour escape wrapping nothing, on every row under 10%. jq versions
differ here too: `"█" * 0` is `""` on jq 1.7+ but `null` on 1.6, and the plugin pins no version,
which is exactly what the existing `if $filled > 0 then … else "" end` guards are protecting
against.

Rather than restore the guard at each call site, put it in `paint` itself, so no caller can
reintroduce the bug:

```
def paint($c; $s):
  ($s // "") as $t
  | if $colour == 1 and $t != "" then "\u001b[" + $c + "m" + $t + "\u001b[0m" else $t end;
```

That is the `jq` counterpart of the bash rule above — never paint an empty string — and it lets
`bar` stay the two-line definition it wants to be.

### Not extracted, deliberately

- **Anything spanning the two scripts.** Refactoring here is per-script. The two read different
  inputs, write different outputs, and are wired up independently; a resemblance between them is
  not evidence that one implementation would serve both, and treating it as such would couple
  two things that are free to diverge. The install story reinforces this — the README symlinks
  each script individually out of a versioned cache directory, so a sourced sibling library
  would break for anyone who symlinked only the two scripts.
- **What is common is the spec, not the code.** The ramp thresholds and the field → code table
  appear in both header blocks. Each header stays the spec for its own script, per the plugin's
  `CLAUDE.md`.
- **The nine `jqr` calls stay nine.** Collapsing them into one `jq` emitting tab-separated
  fields would save ~80 ms, which is worth having but is a separate refactor with its own test
  surface — and it is noise next to the ~990 ms the branch lookup costs. 
  Out of scope for 1.2.0; revisit once `detect_branch` lands.

## Assumptions about Claude Code, and how each was settled

This change only works if Claude Code renders what the scripts emit. Those are assumptions about
someone else's input and output contract, so each one is either validated against the
documentation or gated before any code is written.

| Assumption                                             | Status                                                                                                                                                                                                                                            |
|--------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| The main status line renders ANSI escapes              | **Validated.** The status line docs list colours as a supported feature — "use ANSI escape codes like `\033[32m` for green (terminal must support them)" — and ship a worked git-status-with-colours example.                                     |
| A subagent row renders ANSI escapes                    | **Validated.** The subagent status line docs state the `content` string "is rendered as-is, including ANSI colors and OSC 8 hyperlinks". This retires what was previously the plan's largest open risk; the subagent half of the change proceeds. |
| Escapes survive the JSON round trip                    | **Gated.** jq's encoding is verifiable locally and is test 1 below; that Claude Code decodes it back is not stated in the docs. If test 1 passes but a hand-built row renders as literal `\033[36m` text, the subagent half is dropped.           |
| The line is truncated by display width, not byte count | **Gated.** The docs say only that "long output may get truncated or wrap awkwardly". Check with a long branch name before relying on it.                                                                                                          |
| `.model.id` has a parseable shape                      | **Not relied upon.** An earlier draft proposed reformatting the `display_name` fallback; nothing is documented about that field's format, so the change is dropped rather than guessed at.                                                        |

Two further facts worth having, both from the same docs:

- **Width is supplied, not discovered.** Claude Code captures the script's output rather than
  attaching it to the terminal, so `tput cols` cannot work from inside. `COLUMNS` and `LINES` are
  set in the environment instead (v2.1.153+), and the subagent payload carries a `columns` field
  with the usable row width. If the truncation gate above turns out to matter, that is the input
  to use — not a guess.
- **Escapes are documented as occasionally fragile.** Complex escape sequences "can occasionally
  cause garbled output if they overlap with other UI updates", and multi-line status lines with
  escape codes are called out as more prone to rendering issues than single-line plain text.
  Both scripts emit a single line, which stays on the safer side of that note.

## Implementation

### `scripts/status-line.sh`

Add a colour block immediately after the `jq` guard, before `input=$(cat)`:
`USE_COLOUR` resolved from `NO_COLOR`, then `paint` and `pct_colour`. Add
`round_pct`, `render_bar`, `join_by` and `detect_branch` alongside the existing
`jqr`, `format_countdown` and `render_window` helpers.

Then, changing no logic:

1. **Segment 1 (model)** — paint `MODEL` and `[${EFFORT}]` at composition time, not at
   extraction time, so the raw values stay testable.
2. **Segment 2 (context bar)** — `render_bar "$CTX_PCT"` for both branches; the percentage takes
   `pct_colour`, the `--%` placeholder takes `2` (dim), since there is no load to report.
3. **Segment 3 (branch)** — replaced by `detect_branch "$CWD"`, painted `32` at composition time
   after the emptiness test.
4. **Segment 4 (rate limits)** — `render_window` uses `round_pct` for `pct_int`, paints the
   percentage with `pct_colour "$pct_int"`, the `!` with `31` and the countdown with `2`. It
   already computes `pct_int` before the pace-flag branch, so the ramp lookup slots in with no
   restructuring. The two-window join becomes `join_by`.
5. **Composition** — the final assembly becomes `join_by` over the four segments, with the ` | `
   separator painted once inside the helper.

### `scripts/subagent-status-line.sh`

The row text is embedded in a JSON string, so escapes must be composed *inside*
`jq` and survive JSON encoding.

- Pass the flag in: `jq -c --argjson colour "$USE_COLOUR"`.
- Add, alongside the existing `def`s:

  ```
  def paint($c; $s):
    ($s // "") as $t
    | if $colour == 1 and $t != "" then "\u001b[" + $c + "m" + $t + "\u001b[0m" else $t end;

  def pct_colour($p):
    if $p >= 80 then "31" elif $p >= 50 then "33" else "32" end;

  def bar($pct):
    ($pct / 10 | floor) as $filled
    | paint(pct_colour($pct); "█" * $filled)
      + paint("2"; "░" * (10 - $filled));
  ```

  A `\u001b` in a jq program produces a real ESC byte, and `jq -c` re-encodes it as `\u001b` on
  output — valid JSON that Claude Code decodes back to the escape. Verify this rather than
  assume it; it is the first test below.
- `context_segment` calls `bar` and paints the percentage and token count; it keeps its existing
  three-way branch on `tokenCount` / `contextWindowSize`.
- The `content` composition becomes the `map(select(…)) | join(…)` form above, with the raw
  fields tested before anything is painted or stringified.
- The existing degradation branches — `contextWindowSize` missing, `tokenCount`
  absent, `status`/`name`/`description` absent — keep their current behaviour. Colour never
  decides whether a segment renders.

## Docs to update

The plugin's `CLAUDE.md` makes the header comment blocks the spec, so they are part of this
change, not follow-up:

- `status-line.sh` header — add a colour section to the "Output shape" block:
  the field → code contract, the ramp thresholds, the `NO_COLOR` rule, and why
  `90` and `1;3x` are avoided. That last one is what stops a future edit from
  "tidying" dim chrome into bright black.
- `subagent-status-line.sh` header — the same, plus the escape-inside-JSON detail and the
  `--argjson colour` entry point.
- `README.md` — a short "Colour" subsection under **What it does** with the ramp table and the
  `NO_COLOR` line. The rendered examples there stay plain text, since a code fence cannot show
  colour; refresh `status-line-example.png` to a coloured capture instead.
- `README.md` Testing section — add the `NO_COLOR` check and the JSON-validity check from below.

## Testing

Everything here is a pipe into the script, per the plugin's testing convention — no Claude Code
reload in the loop.

**1. JSON stays valid (do this first; it gates the design):**

```bash
echo '{"tasks":[{"id":"t1","model":"claude-opus-5","effort":"high","status":"running","name":"code-reviewer","description":"Reviewing the diff","tokenCount":12400,"contextWindowSize":200000}]}' \
  | ./scripts/subagent-status-line.sh | jq -e . >/dev/null && echo "valid JSON"
```

**2. The ramp moves at both thresholds.** Three fixtures per script, chosen to sit either side
of 50 and 80:

| State   | context | 5h  | 7d              | subagent |
|---------|---------|-----|-----------------|----------|
| quiet   | 30%     | 42% | 21%             | 6%       |
| warming | 64%     | 58% | 34%             | 55%      |
| hot     | 92%     | 87% | 61% + pace flag | 88%      |

The hot fixture is the important one: it must show a red context figure, a red 5-hour figure,
and a **yellow** 7-day figure with a **red** `!`.

**3. `NO_COLOR` produces byte-identical output to today.** The strongest form of this test
compares against the pre-change script:

```bash
hg cat -r <pre-change-rev> plugins/agent-status-call/scripts/status-line.sh > /tmp/before.sh
echo "$FIXTURE" | bash /tmp/before.sh > /tmp/a
echo "$FIXTURE" | NO_COLOR=1 ./scripts/status-line.sh > /tmp/b
diff /tmp/a /tmp/b && echo "identical"
```

And the quick form, which should print no `^[`:

```bash
echo "$FIXTURE" | NO_COLOR=1 ./scripts/status-line.sh | cat -v
```

Run both ways for `subagent-status-line.sh` too.

**4. Four terminal themes.** Switch profile and eyeball the hot fixture on each. This is what
the 16-colour choice buys, and it is the only test that needs eyes:

- xterm / Terminal.app Basic — the reference
- Solarized Dark — the theme that punishes `90` and `1;3x`; confirm separators are visible and
  the model name is cyan, not grey
- Nord — confirm the ramp's yellow and red still separate at a glance
- Gruvbox Dark — confirm the muted `31` still reads as an alarm

**5. Existing behaviour is unregressed.** Re-run the README's rate-limit countdown tests against
both `date` flavours; colour must not disturb
`parse_timestamp` selection or the countdown text.

**6. Degradation.** Missing `context_window`, missing `rate_limits`, missing
`contextWindowSize`, missing `tokenCount`, non-repo cwd. Each drops its segment exactly as
before, with no stray escapes left behind.

**7. `detect_branch` across all five directory shapes**, since it is the one extraction that
changes which subprocesses run. For each, check both the rendered segment and — with `hg`
shadowed on `PATH` by a wrapper that logs its invocations — that the expected number of spawns
happened:

| cwd                         | Expected segment              | Expected `hg` spawns |
|-----------------------------|-------------------------------|----------------------|
| hg repo, active bookmark    | the bookmark                  | 1–2                  |
| hg repo, no active bookmark | omitted                       | 1–2                  |
| git repo, not under hg      | the branch                    | 0                    |
| neither                     | omitted                       | 0                    |
| detached HEAD in git        | `HEAD` (unchanged from today) | 0                    |

The third and fourth rows are the point of the change: today both spawn `hg`
and wait ~0.34 s for it to fail.

**8. `round_pct` agrees at the boundaries.** Feed 49.5, 50.5, 79.5 and 80.5 to both the context
path and a rate-limit window and confirm the two segments round the same way and land on the
same ramp colour.

## Release

- Bump `.claude-plugin/plugin.json` to **1.2.0** — new user-visible behaviour, no breaking
  change.
- `CHANGELOG.md` gets a `## [1.2.0]` section in the existing Keep a Changelog format, with
  **Added** (colour on both status lines, the severity ramp,
  `NO_COLOR` support) and **Documentation** (README colour subsection, refreshed screenshot)
  entries, written from the user's side.

## Commit sequence

Mercurial, on the `main` bookmark. This plan lands first, so the approved shape is in history
before any code moves.

1. `docs: plan colour support for both status lines` — this file.
2. `refactor: extract status line helpers` — `round_pct`, `render_bar`,
   `join_by` and `detect_branch`, with no colour and no behaviour change. Committed separately
   so the `NO_COLOR` byte-identical test in steps 3–4 has a clean baseline to diff against, and so
   the branch-lookup change can be reverted on its own if it misbehaves.
3. `feat: colour the main status line` — `status-line.sh` plus its header spec.
4. `feat: colour subagent status rows` — `subagent-status-line.sh` plus its header spec. Dropped
   entirely if the JSON round-trip gate above fails.
5. `docs: describe status line colours` — README subsection, refreshed screenshot.
6. `chore: release 1.2.0` — version bump and changelog.

Step 2 is worth its own commit for a second reason: it changes how often `hg`
is spawned, which is the kind of thing that shows up as "the status line feels different" long
after the colour change gets the blame.

## Later, if wanted

The same `paint` and `pct_colour` choke points can emit `38;2;r;g;b` when
`COLORTERM` is `truecolor` or `24bit`, falling back to these codes otherwise, with `NO_COLOR`
overriding both. That is an additive change to two functions, which is the reason for routing
every escape through them now.

[1]: https://no-color.org

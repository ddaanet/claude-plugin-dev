# Review: Item 1.3/1 test review — `session-start` external contract

**Scope**: the two new tests `session-start is silent on the copy` and
`session-start warns when the variable is unset` in tests/dogfood-test.sh, the
`session_start` stub and its routing/header in toolkit/dogfood.sh (stub
completion only), and item-1-3-s1-red.md. All uncommitted. **Date**: 2026-09-30
**Mode**: review + fix

## Summary

The warn test is red on four assertions against the inert stub, and it has no
harness errors. The silent test is a negative that passes against the stub. A
mutation of the stub proved that it reds on its own stdout assertion. The warn
test is its positive, over the same fixture. Two wrong-reason gaps were fixed.
The first: a GREEN that took the root from the payload `cwd`, falling back to
its own location, passed both tests under `</dev/null`. The second: the
variable's state for later tests depended on test order. The stub's header
column was realigned.

**Overall Assessment**: Ready

## Mechanical check

The suite was run in the foreground three times: before the fixes, after them,
and after the mutation runs were restored. Each run gave 4 failures, all from
the warn test and all `FAIL:` assertion lines, with no harness error:

- `stdout is one JSON object` … not true over stdout `''`
- `systemMessage leads with an ANSI reset and names the copy` … not true over
  `''`
- `hookEventName` … not true over `''`
- `additionalContext names the copy` … not true over `''`

The warn test's exit-code and stderr assertions pass: the stub exits 0 in
silence. The silent test passes, which is expected of a negative. All other
scenarios pass.

The suite was also run with `CLAUDE_CODE_PLUGIN_DIRS=/some/other/dist/plugin`
exported by the parent. It gave the same 4 failures, so the result does not
depend on the launching session. `shellcheck` is clean on both files.

## Discrimination of the silent test (mutation runs)

Each mutation replaced the stub body in place, from a script that asserts its
anchor matches exactly once. Each was restored by the inverse replacement. After
restoring, the stub reads `session_start() { :; }` again, and
`git diff toolkit/dogfood.sh` shows only the header realignment, the routing
line and the stub.

| Mutation | Silent test | Warn test |
|---|---|---|
| always emit the warning object (root from `root_dir`) | **red**, on `prints nothing on stdout` | green |
| sketch GREEN: silent iff the variable equals `$(root_dir)/dist/plugin` | green | green |
| root from payload `.cwd`, else `root_dir` | **red** (stdout) | **red** (systemMessage, additionalContext name `…/elsewhere/dist/plugin`) |

- **Row 1** answers check 2. The negative has a state that fails it, and it
  fails on its own assertion.
- **Row 2** shows that the pair is satisfiable together. It also shows that the
  `CLAUDE_CODE_PLUGIN_DIRS=… run_session_start` prefix reaches the child through
  both function layers.
- **Row 3** is the fixed wrong-reason gap (Major 1).

The same row-3 script was probed directly against `</dev/null`. It printed
nothing: under the old stdin that GREEN passes.

On pairing, both tests build the fixture with the same three lines
(`make_consumer`, `run_dogfood sync`, `root=…pwd -P`). They run through the same
helper, and the only input that differs is the variable. So the warn test is the
negative's positive over the same fixture, and the negative sits ahead of it. A
drift in path or wording shows up as the positive going red. A guard deleted or
widened shows up as the negative going red.

## Wrong-reason analysis

- **Env isolation.** Before this review, the warn test's `unset` ran at script
  scope and stayed in effect for every later test. Tests earlier in the file
  still ran under whatever the parent exported. Today nothing after the unset
  reads the variable, so the leak was harmless. Items 1.3/2–4 will insert more
  session-start tests, though, and a test placed before the unset would then
  depend on the launching session. Fixed by moving the unset into the preamble
  (Major 2). Every test now starts with the variable unset, and a test that
  wants it passes it as a prefix.
- **stdin.** `</dev/null` carried no payload, so any GREEN that read `.cwd` got
  nothing. A GREEN of the shape "payload cwd, else own location" then fell back
  to the right answer. That is the "fallback supplying the rule's answer" shape.
  It is also the production failure `sessionstart-resume-cwd` records: a resumed
  `SessionStart` carries the resuming process's cwd. Fixed by feeding a
  realistic `SessionStart` payload with `source:"resume"` and a decoy `cwd`
  (Major 1). The here-string is never a tty, so the hang concern behind
  `</dev/null` does not arise.
  - Residual: "stdin not read" itself is not pinned. A GREEN that drains stdin
    and ignores it is indistinguishable, and harmless. No assertion was invented
    for it.
- **`jq_holds … -s` "one JSON object".** Sound. Empty stdout slurps to `[]`, so
  `length == 1` is false. Two values give length 2. Trailing garbage is a parse
  error, and `-e` fails on it. The per-field checks that follow run without
  `-s`. They could each be satisfied by the last of several values, which is why
  the slurped check carries the one-object claim.
- **Path spelling.** The fixture sandbox is already physical: `make_consumer`
  takes `pwd -P`, so `$consumer == $root`. With the script invoked at
  `$consumer/plugin-dev/dogfood.sh`, a GREEN using logical `pwd` gets the same
  string as one using `pwd -P`. This slice therefore cannot tell them apart.
  That is by design: the symlinked and trailing-slash spellings are Item 1.3/2,
  which is OUT.
  - A GREEN that hardcodes the path cannot pass, because the sandbox path is
    random per run.
  - A GREEN comparing the unnormalised `…/plugin-dev/../dist/plugin` string reds
    the silent test.
- **Channels pinned independently.** `systemMessage` and `additionalContext`
  each carry their own `contains($p)`. Dropping either one fails its own
  assertion (see row 3, where both fail separately).
  - The ANSI reset is checked as a jq string literal `"\u001b[0m"` with
    `startswith`. It is not a BRE, so `[` is literal.
  - Residual: the wording "stated as fact that this session does not load" is
    pinned only by the path. The runbook's slice spec asks for exactly that, and
    the wording belongs to GREEN.
- **Substring acceptance** (`/other/<root>/dist/plugin`) and a variable that
  merely has some value are Items 1.3/2–3 (OUT). No gap here.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Payload `cwd` fallback passes both tests**
   - Location: tests/dogfood-test.sh, both session-start runs (`</dev/null`)
   - Problem: with no payload, a GREEN that takes the root from `.cwd` and falls
     back to its own location passes both tests. On `SessionStart(resume)` in
     production, it would name another repo's copy. Probed: silent under
     `</dev/null`, warns on `…/elsewhere/dist/plugin` with a payload.
   - Fix: a `run_session_start` helper, beside `run_pre_tool`, feeds a
     SessionStart payload whose `cwd` is `$sandbox/elsewhere`. That is the same
     decoy `run_dogfood` already gives `CLAUDE_PROJECT_DIR`. Both tests use the
     helper.
   - **Status**: FIXED
2. **Variable state depends on test order**
   - Location: tests/dogfood-test.sh, `unset CLAUDE_CODE_PLUGIN_DIRS` inside the
     warn test
   - Problem: tests before the unset inherit the parent session's value. Tests
     after it see the variable unset. A session-start test inserted by Items
     1.3/2–4 above that line would pass or fail depending on who launched the
     suite.
   - Fix: unset in the preamble, beside `unset CDPATH`, with a comment. The
     local unset was removed. The section comment says a test wanting the
     variable passes it as a prefix, and it names the warn test as the silent
     test's positive.
   - **Status**: FIXED

### Minor Issues

1. **Header comment column broken**
   - Location: toolkit/dogfood.sh:7–12
   - Note: `session-start` is wider than the 10-column name field, so its
     description started two columns right of the others.
   - Fix: every entry was realigned to a 15-column name field, and `pre-tool`'s
     description was rewrapped to stay under 80 columns.
   - **Status**: FIXED

## Fixes Applied

- tests/dogfood-test.sh preamble: `unset CLAUDE_CODE_PLUGIN_DIRS`, with a
  two-line reason.
- tests/dogfood-test.sh: new `run_session_start` helper (SessionStart payload,
  `source:"resume"`, decoy `cwd`). The silent test calls it with the variable as
  a prefix, and the warn test calls it bare. The old `</dev/null` and set/unset
  comment were replaced by one that states the prefix convention and the
  pairing.
- toolkit/dogfood.sh:7–12: the subcommand list was realigned.

## Notes for later slices

- **Item 1.3/4 (jq-less).** `run_session_start` builds its payload with jq in a
  command substitution. Under a `PATH="$sandbox/nojq"` prefix, that jq is not
  found. Build the payload before narrowing PATH and call
  `run_dogfood session-start <<<"$payload"` directly, as Item 1.2/5 did.
- **Item 1.3/2.** This fixture's logical and physical spellings coincide, so the
  symlinked-root test must place the script's invocation path, or the variable's
  spelling, under a symlink to make `pwd -P` load-bearing.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| Silent when the variable is `<root>/dist/plugin` (exit 0, empty stdout) | Satisfied | silent test; reds under always-warn mutation |
| Warn on unset: one object, `systemMessage` leads with ESC`[0m` and names the copy | Satisfied | warn test, red on assertions |
| `hookEventName` `SessionStart`, `additionalContext` names the copy | Satisfied | warn test, red on assertions |
| Root from the script's own location (D5) | Satisfied | decoy payload `cwd` and `CLAUDE_PROJECT_DIR`; payload-cwd mutation reds both |
| stdin not read | Partial (by design) | a read is harmless and unobservable; not pinned |

## Positive Observations

- The negative is placed ahead of its positive, and each has its own body.
- The one-object check is slurped, and the per-field checks run in jq with
  `--arg`, so the spaced path is compared literally.
- The stub is minimal (routed and inert), and the usage line already named
  `session-start`.

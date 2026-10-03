# Review: Item 1.1/2 test review — a failed sync at launch is attributed to the shim

**Scope**: the uncommitted change to `tests/dogfood-launcher-test.sh` and the
RED report `reports/item-1-1-s2-red.md`. `toolkit/bin/claude` mutated in place
for probes only, and restored. **Date**: 2026-10-03 **Mode**: review + fix

## Summary

The RED added one assertion: exactly one stderr line matching
`^dogfood:.*not started` in the failed-sync scenario. It fails on that assertion
and nothing errors. Probing candidate GREENs found three holes. A fixed `exit 1`
passed, because the only failure the suite provokes is a refusal that already
exits 1. The pattern did not require the word `claude`. Nothing paired the line
with a successful launch except, indirectly, the 127 scenario. All three are
fixed, and every probed wrong GREEN now reds.

**Overall Assessment**: Ready

## Mechanical check

- RED as delivered: `bash tests/dogfood-launcher-test.sh` gave 1 failure,
  `a failed sync aborts the launch: one dogfood: line says claude was not started: expected '1', got '0'`.
  That is an assertion failure. No ERROR, and every other assertion passed.
- After the fixes: 2 failures, both on assertions. Everything else passes and
  shellcheck is clean.
  - `a failed sync aborts the launch: one dogfood: line says claude was not started: expected '1', got '0'`
  - `a failed rsync keeps its status: one dogfood: line says claude was not started: expected '1', got '0'`

## Issues Found

### Major Issues

1. **A fixed exit status passes as "sync's status"**
   - Location: `tests/dogfood-launcher-test.sh`, scenario "a failed sync aborts
     the launch", assertion `rc == 1`.
   - Problem: the scenario fails sync through the manifest refusal, which exits
     1. The natural GREEN shapes `bash … sync || { echo …; exit 1; }` and
     `if ! bash … sync; then …; exit 1; fi` both pass. Yet both throw away
     rsync's status, which `dogfood.sh` documents as the script's own, and git's
     128. The assertion's label claims "the shim exits with sync's status", and
     this slice's GREEN rewrites exactly that path. Probe B (a fixed `exit 1`)
     passed the suite as delivered.
   - Fix: a new scenario, "a failed rsync keeps its status". A stub `rsync`,
     placed on PATH through a directory whose name holds a space, prints one
     line and exits 23. The scenario asserts:
     - `rc == 23`;
     - rsync's own line on stderr (`grep -qxF`);
     - exactly one not-started line;
     - the next claude did not run.
   - **Status**: FIXED

2. **The pattern does not require `claude`, and the paths it could fall back on
   spell it**
   - Location: the slice's assertion, `grep -c '^dogfood:.*not started'`.
   - Problem: the outline asks for a line saying *`claude`* was not started. The
     pattern accepts `dogfood: sync failed; not started`. A plain
     `claude.*not started` would not fix it either. Sync's lines name the root,
     and the root's path spells `claude` twice: in `.claude-plugin`, and in
     `$TMPDIR` (`/tmp/claude-1000` here). So a line like
     `dogfood: sync of $root failed, not started` would match through the path.
   - Fix:
     `not_started_re="^dogfood: (.*[[:space:]\`'])?claude[[:space:]\`'].*not
     started"` (`grep
     -E`). `claude` must be a word, delimited by whitespace or a quote or backtick. It cannot be a substring of a path component. A comment above it says why. Probes G (no `claude`) and I (`claude` only through `$root`)
     both red.
   - **Status**: FIXED

### Minor Issues

1. **A line printed on every launch was caught only by an unrelated scenario**
   - Location: "the shim syncs before exec".
   - Problem: the failed-sync assertion is a positive. Its pairing with a
     successful sync rested on the 127 scenario's exact-stderr check, which
     exists to pin the no-next-claude message. That scenario is the only thing
     that would catch an unconditional line.
   - Fix: "the shim syncs before exec" now asserts its stderr is empty. This is
     the plain successful-launch pairing. Probe E (line printed before every
     sync) reds there and in the 127 scenario.
   - **Status**: FIXED

2. **A line on both stdout and stderr would pass**
   - Location: "a failed sync aborts the launch".
   - Problem: nothing checked stdout. A GREEN that echoes the line to stdout as
     well as stderr would pass.
   - Fix: added `assert_eq "$(cat "$sandbox/stdout")" ""`. Sync writes nothing
     to stdout on refusal. Probe C reds on it.
   - **Status**: FIXED

## Wrong-reason hunt (per question in the dispatch)

| Candidate GREEN | Reds after fixes? | Where |
|---|---|---|
| A — `\|\| { status=$?; echo "…claude was not started" >&2; exit "$status"; }` | no, all green (the intended GREEN passes) | — |
| B — fixed `exit 1` | yes | rsync scenario `rc` (23 vs 1) |
| C — line on stdout | yes | count 0 (both failure scenarios), stdout not empty |
| D — line printed twice | yes | count 2 (both failure scenarios) |
| E — line printed on every launch, before sync | yes | syncs-before-exec stderr empty; 127 exact stderr |
| F — `2>/dev/null` on sync (stderr swallowed) | yes | refusal line and rsync line missing |
| G — line without the word `claude` | yes | count 0 |
| H — exits 0 | yes | `rc` in both failure scenarios |
| I — `claude` only inside `$root` | yes | count 0 |

- **The shim's line printed before sync's stderr is lost.** Probe F covers this.
  Sync's stderr is never captured, so it cannot be "lost". Both of sync's lines,
  the refusal and rsync's, are asserted present.
- **Are the assertions reached?** Yes. Every new assertion runs under `set -e`,
  with `grep -c … || true`, so a no-match yields `0` rather than an abort.
  `run_claude` brackets the launch with `set +e`.
- **The next claude never run.** Both failure scenarios assert `rec/argv` is
  absent. The refusal scenario also asserts `rec/pid` is absent.

## Mutated-SUT probes

`toolkit/bin/claude` was mutated in place once per candidate. Each run replaced
the single sync line by literal string replacement, ran the suite in the
foreground, then applied the inverse exact replacement. After all nine runs,
`git diff --stat toolkit/bin/claude` was empty. The suite copies the shim into
each fixture at `make_consumer`, so every mutation was live.

## Fixes Applied

- `tests/dogfood-launcher-test.sh`, "the shim syncs before exec": asserts stderr
  is empty.
- `tests/dogfood-launcher-test.sh`, "a failed sync aborts the launch":
  - pattern tightened to a word-delimited `claude`, shared as `not_started_re`,
    with a comment on why;
  - asserts stdout is empty.
- `tests/dogfood-launcher-test.sh`: new scenario "a failed rsync keeps its
  status" (stub rsync exiting 23).

## Requirements Validation

| Requirement (outline m3) | Status | Evidence |
|---|---|---|
| one `dogfood:` line | Pinned | count `== 1` in both failure scenarios |
| saying `claude` was not started | Pinned | `not_started_re`: word `claude`, then `not started` |
| keeping the sync's own stderr | Pinned | refusal `grep -qF`; rsync line `grep -qxF` |
| a non-zero exit | Pinned, as sync's own status | `rc == 1` (refusal), `rc == 23` (rsync) |
| claude not started | Pinned | `rec/argv` absent in both |

## Positive Observations

- The RED kept the scenario's existing assertions and added only the slice's
  claim. It ran red on the assertion against an untouched shim.
- The count-based `grep -c … || true` is correct under `set -e`, and it rejects
  both a missing line and a duplicated one.

## Recommendations

- The suite is now 422 lines, over the soft 400 cap. Before the slice it was
  393. GREEN for this slice adds no test lines. If later slices (m11, the m12
  move-out) leave it over, consider splitting at the sync/exec seam. m12's move
  of the `session-start` contract case into `dogfood-session-start-test.sh`
  takes some lines out.

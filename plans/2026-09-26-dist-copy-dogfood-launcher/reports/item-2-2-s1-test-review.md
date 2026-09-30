# Review: Item 2.2 slice 1 test review (after RED, before GREEN)

**Scope**: uncommitted diff to `tests/update-plugin-dev-test.sh`, scenario
"install.sh: wires into an existing settings.json without replacing it"
**Date**: 2026-09-30 **Mode**: review + fix

## Summary

RED is genuine: all three new assertions fail on a count mismatch, with no jq
error, and every other assertion passes. Mutation runs showed three problems.
The two "once" assertions did not pin "once". The quoting assertion only
re-counted the same exact strings. The version-guard hook's spelling was not
pinned anywhere in the suite. All three are fixed in the test. The SUT was
mutated in place for the demonstration, then restored.

**Overall Assessment**: Ready

## Mechanical check (reproduced)

`bash tests/update-plugin-dev-test.sh` against the unmodified SUT, before the
fixes:

```text
FAIL: install adds the pre-tool hook once: expected '1', got '0'
FAIL: install adds the session-start hook once: expected '1', got '0'
FAIL: the commands quote the project dir: expected '1,1', got '0,0'
3 failure(s)
```

All three FAILED on an assertion. None PASSED and none ERRORED, and there were
no other FAIL lines.

## Mutation evidence

A temporary block in `toolkit/install.sh`, inserted before the `cmp -s` line and
selected by `MUT`, post-processed the written settings to act as a plausible
GREEN or a wrong one. It was removed by the inverse exact-string replace.
`grep MUTANT` finds nothing, and `git status` shows `install.sh` clean.

| Mutant | Original test | Fixed test |
|---|---|---|
| `good`: pre-tool once under `Write\|Edit\|NotebookEdit`, session-start once with no matcher | green | green |
| `dup`: pre-tool again in a matcher-less entry | only A3 red (`2,1`); A1 green | A1 red (`… none`), A3 red (`3:3`) |
| `dupsame`: a second pre-tool hook in the same entry | only A3 red; A1 green | A1 red, A3 red |
| `sessdup`: session-start again under `matcher: "startup"` | only A3 red; A2 green | A2 red (`none matcher=startup`), A3 red |
| `sessmatcher`: the session-start entry gets `matcher: "*"` | A2 red (`0`) | A2 red (`matcher=*`) |
| `prematcher`: pre-tool under `Write\|Edit` | A1 red (`0`) | A1 red (`Write\|Edit`) |
| `unquoted`: `bash ${CLAUDE_PROJECT_DIR}/…` | all three red, all `0` | A1 and A2 red; A3 red as `2:0` |
| `expanded`: `bash "/proj/plugin-dev/…"` | all three red, all `0` | A1 and A2 red; A3 red as `2:0` |
| `vgquoted`: version-guard respelt `bash "${CLAUDE_PROJECT_DIR}/…"` | **green** | version-guard assertion red (`0`) |

## Issues Found

### Major Issues

1. **Version-guard spelling unpinned**
   - Location: `tests/update-plugin-dev-test.sh`, the version-guard assertion
     (`test("version-guard")`)
   - Problem: the runbook says version-guard keeps its unquoted spelling,
     because a respelt command would be added a second time beside the one
     consumers already have. The assertion matched any command containing
     `version-guard`. The `vgquoted` mutant passed the whole suite, and no other
     suite pins the string (checked with `grep` over `tests/`).
   - Fix: compare exactly against
     `vg_cmd='bash ${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh'`, with a
     two-line comment giving the reason.
   - **Status**: FIXED

2. **"Once" was not pinned by the assertions named "once"**
   - Location: `install adds the pre-tool hook once` and
     `install adds the session-start hook once`
   - Problem: both jq filters selected entries by matcher (or by having no
     matcher key) before counting. A copy added under any other matcher, or as a
     second hook inside the same entry, left the count at 1 (`dup`, `dupsame`
     and `sessdup` stayed green on A1/A2). Only A3's cross-entry total caught
     these, under a name about quoting.
   - Fix: each assertion now prints one word per hook that carries the command,
     naming its entry's matcher (`none` when the key is absent). The expected
     values are `Write|Edit|NotebookEdit` and `none`. A duplicate anywhere under
     the event, or a single copy under the wrong matcher, reds with a message
     that names the cause.
   - **Status**: FIXED

3. **"The commands quote the project dir" did not discriminate quoting**
   - Location: the third new assertion
   - Problem: it counted the same exact strings as A1 and A2, so it could not
     red for any reason of its own. Its only independent power was uniqueness,
     which A1 and A2 now carry. An unquoted or expanded spelling gave `0` on all
     three assertions, and none of them said "quoting".
   - Fix: it now collects every hook command containing `dogfood.sh`, under any
     event, and prints `total:quoted`, where quoted means containing the literal
     `"${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh"`. The expected value is
     `2:2`. A wrong spelling reds as `2:0`. The total acts as a non-emptiness
     guard, so the assertion is not vacuously true when there are no commands
     (RED shows `0:0`). It also catches a stray third copy under another event.
   - **Status**: FIXED

### Minor Issues

None.

## Fixes Applied

- `tests/update-plugin-dev-test.sh`, version-guard assertion: the exact `vg_cmd`
  match, and a comment giving why the spelling stays unquoted.
- `tests/update-plugin-dev-test.sh`, the pre-tool and session-start assertions:
  rewritten as one matcher word per carrying hook.
- `tests/update-plugin-dev-test.sh`, the quoting assertion: rewritten as a
  `total:quoted` count over all dogfood commands.
- Net: +23/−1 lines against HEAD, versus +13 for the RED version. The file is
  now 428 lines; the split is deferred to the phase boundary.

## Post-fix run

Unmodified SUT, `bash tests/update-plugin-dev-test.sh`:

```text
FAIL: install adds the pre-tool hook once: expected 'Write|Edit|NotebookEdit', got ''
FAIL: install adds the session-start hook once: expected 'none', got ''
FAIL: the commands quote the project dir: expected '2:2', got '0:0'
3 failure(s)
```

All three are still red on their assertions. Everything else is green, including
the tightened version-guard assertion against today's SUT. The test file passes
`shellcheck` cleanly.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D11 new entries: `PreToolUse` `Write\|Edit\|NotebookEdit` → pre-tool, once | Satisfied | A1 expects exactly one carrying hook, under that matcher |
| D11 new entries: `SessionStart`, no matcher → session-start, once | Satisfied | A2 expects exactly one carrying hook, in an entry with no `matcher` key |
| D11 quoting: literal `"${CLAUDE_PROJECT_DIR}"` | Satisfied | A3 `2:2`, plus the exact strings in A1 and A2 |
| Version-guard keeps its unquoted spelling | Satisfied | exact `vg_cmd` match |

## Deferred Items

- **Moving the install.sh scenarios to their own suite (file now 428 lines)**:
  Scope OUT, handled at the phase boundary.
- **Re-run no-op, surviving SessionStart entry, matcher-agnostic idempotency,
  fresh settings.json**: slices 2–5.

## Positive Observations

- The RED report is accurate. The failures were count mismatches, and the SUT
  was untouched.
- The commands are passed with `jq --arg` rather than spliced into the filter,
  so the quotes and `${…}` reach jq literally.
- The test sits in the scenario whose fixture already has a matcher-less
  `PreToolUse` entry, which is the case D11's idempotency rule is about.

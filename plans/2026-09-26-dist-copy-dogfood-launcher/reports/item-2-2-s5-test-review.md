# Review: Item 2.2/5 test review — a fresh settings.json carries all three hooks

**Scope**: uncommitted diff to `tests/update-plugin-dev-test.sh`, scenario
`install.sh: no ref resolves the newest dist tag`; `toolkit/install.sh` only for
temporary in-place mutation runs (verified restored). **Date**: 2026-09-30
**Mode**: review + fix (TDD test review, after RED, before GREEN)

## Summary

The RED adds an anchor (no `settings.json` before install) and two assertions
over the freshly written file: PreToolUse as `matcher=command` lines, and
SessionStart as `none|matcher=command` lines. Both red on assertion against the
current SUT, and the anchor passes. One over-constraint was fixed: the
PreToolUse check depended on entry order, which the slice does not specify. The
three command literals are now defined once and shared by both install
scenarios.

**Overall Assessment**: Ready

## Mechanical check (reproduced)

`bash tests/update-plugin-dev-test.sh`, before and after the fixes:

- `a fresh settings.json carries version-guard and the pre-tool hook under PreToolUse`:
  FAILED on assertion. It got only the `Write|Edit=<vg>` line, with no pre-tool
  line.
- `a fresh settings.json carries the session-start hook with no matcher`: FAILED
  on assertion (got `''`).
- Anchor `the no-ref fixture already has a settings.json`: passes (no FAIL
  line).
- Every other assertion in the suite passes: `2 failure(s)`, and both are the
  new ones.
- `shellcheck tests/update-plugin-dev-test.sh`: clean.

No ERROR: the jq reads a file that exists, because the current SUT writes a
version-guard-only document.

## Wrong-reason hunting (mutation runs)

Each mutation replaced the no-settings branch's `jq -n` literal in
`toolkit/install.sh` in place (exact-string replace, asserted to match once),
ran the full suite, then restored it by the inverse replace. After all four,
`git diff --quiet -- toolkit/install.sh` reported it clean.

| Mutation of the no-settings branch | Expected | Result |
|---|---|---|
| Correct GREEN: `printf '{}\n'` piped through the same three `add_hook` calls | green | suite passed |
| Correct but reordered (pre-tool call before version-guard) | green | suite passed (after fix 1) |
| Pre-tool under `Write\|Edit` | red | PreToolUse assertion FAIL, only |
| Session-start with `matcher: "startup"` | red | SessionStart assertion FAIL (`got 'matcher=…'`), only |

The current SUT covers the remaining wrong shapes: a missing hook fails both
assertions. By construction, a duplicate hook or both commands merged under one
entry adds or changes a line in the joined output. A version-guard respelt with
quotes changes its line.

Birth state: the anchor rules out a pre-existing file, so the assertions observe
what install wrote. The existing-settings branch cannot satisfy them, because
this fixture never reaches it.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **PreToolUse assertion over-constrains entry order**
   - Location: `tests/update-plugin-dev-test.sh`, the PreToolUse `assert_eq` in
     the no-ref install scenario
   - Problem: `join("\n")` over the entries in file order. A correct GREEN that
     calls `add_hook` for pre-tool before version-guard would red. The slice
     says only that `.hooks.PreToolUse` "carries" both commands, and the item
     fixes the calls, not their order.
   - Fix: `| sort |` before `join`. The expected string is already in sorted
     order (`=` sorts before `|`), and matcher scoping, duplicates and absence
     are still pinned. A comment states that order is deliberately outside the
     contract.
   - **Status**: FIXED. The reordered-GREEN mutation now passes, and both
     wrong-GREEN mutations still red.

### Minor Issues

1. **Command literals duplicated across the two install scenarios**
   - Location: `fresh_vg`/`fresh_pre`/`fresh_start` (no-ref install scenario) vs
     `vg_cmd`/`pretool_cmd`/`session_cmd` (existing-settings scenario)
   - Note: these were two copies of the same three contract strings, and they
     could drift apart.
   - Fix: define `vg_cmd`/`pretool_cmd`/`session_cmd` once, at their first use
     in the no-ref install scenario, and move the explanatory comments there
     (unquoted vg spelling; literal `${CLAUDE_PROJECT_DIR}`, with the dogfood
     commands in double quotes). The later scenario's definitions are deleted
     and it uses the shared ones. Both scenarios stay together in the planned
     install suite, so the split does not separate definition from use.
   - **Status**: FIXED

## Fixes Applied

- `tests/update-plugin-dev-test.sh`, no-ref install scenario: the `fresh_*`
  literals are replaced with the shared `vg_cmd`/`pretool_cmd`/`session_cmd`
  plus their merged rationale comment. The PreToolUse jq gains `| sort`, with a
  one-line comment on why.
- `tests/update-plugin-dev-test.sh`, existing-settings scenario: the duplicate
  definitions and their comments are removed (now defined above).
- Net: the suite is 472 lines, down from 474 at RED. It stays over 400; the
  split is Scope OUT.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| Slice 5: fresh file's PreToolUse carries version-guard and pre-tool | Pinned | PreToolUse assertion; reds on missing/mis-scoped pre-tool |
| Slice 5: fresh file's SessionStart carries session-start | Pinned | SessionStart assertion; reds on missing hook or any `matcher` key |
| Fixture has no settings.json | Pinned | anchor before install |

## Deferred Items

- **Moving install.sh's scenarios to their own suite** — Reason: Scope OUT
  (phase-boundary work, outline item 4).

## Positive Observations

- The anchor sits before install, so the no-settings precondition is checked and
  not assumed.
- The SessionStart check uses `has("matcher")`, the convention of the
  existing-settings assertion. A GREEN writing `matcher: ""` would red, as slice
  1's "no `matcher` key" requires.
- `matcher=command` lines encode scope and identity together, so one assertion
  catches absence, duplication and mis-scoping.

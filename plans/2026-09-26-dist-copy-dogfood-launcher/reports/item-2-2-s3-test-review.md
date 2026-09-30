# Review: Item 2.2/3 test review — a pre-existing SessionStart entry survives

**Scope**: uncommitted diff to `tests/update-plugin-dev-test.sh` (scenario
`install.sh: wires into an existing settings.json without replacing it`) and the
RED report `reports/item-2-2-s3-red.md`. `toolkit/install.sh` was touched only
for a temporary in-place mutation, which has been restored. **Date**: 2026-09-30
**Mode**: review + fix

## Summary

The slice adds a matcher-less `SessionStart` entry (`echo consumer-start`) to
the fixture, plus two assertions. `a pre-existing SessionStart entry survives`
does discriminate: it reds under a mutation different from the one in the RED
report. The second assertion was a duplicate of slice 1's
`install adds the session-start hook once`, which already guards the same array,
and it did not red under the RED's mutation. I dropped it and rewrote the
comment so that it says where "beside" is pinned.

**Overall Assessment**: Ready

## Mechanical check: mutation proof reproduced

The RED report's mutation was `.hooks[$event] += [` → `.hooks[$event] = [`. Mine
is a different one in the `add_hook` of `toolkit/install.sh`:
`.hooks[$event] //= [] |` → `.hooks[$event] = [] |`. This is the plausible bug
of initializing the event array instead of defaulting it. Before the mutation,
`grep -cF` found the string exactly once, and it found the mutated text once
after applying it.

Suite under mutation (3 failures):

- `a pre-existing SessionStart entry survives: expected '1', got '0'`, which is
  this slice's assertion failing on its own assertion
- `install.sh kept the consumer's own matcher-less hook: expected '1', got '0'`
- `install.sh added the version-guard hook: expected '1', got '0'`

Restore: I applied the inverse exact-string replace. `grep -cF` for the mutation
text now returns 0, `git diff --stat toolkit/install.sh` is empty, and the suite
prints `update-plugin-dev scenarios passed` with exit 0.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **The second assertion was redundant and could not discriminate**
   - Location: `tests/update-plugin-dev-test.sh`, the assertion
     `the session-start hook sits beside the consumer's SessionStart entry`
   - Problem: It counted the session-start command in `.hooks.SessionStart` and
     expected 1. Slice 1's `install adds the session-start hook once` already
     asserts exactly one entry in that same array carrying that command, and
     also that the entry has no matcher. So the new line was a strictly weaker
     copy. It stayed green under the RED's mutation, as the RED report admits,
     and no mutation reds it without also redding slice 1's assertion. It also
     added a line to a file already over 400 lines.
   - Fix: Deleted it. "Beside" is pinned by two assertions over the same
     `.hooks.SessionStart` array: slice 1's (the new hook is present exactly
     once, matcher-less) and this slice's (the consumer's hook is still there
     exactly once). Replacing the array reds the second. Writing the hook
     anywhere else reds the first.
   - **Status**: FIXED

2. **The comment claimed a check that the next line did not make**
   - Location: the comment above `a pre-existing SessionStart entry survives`
   - Problem: "must sit beside the new one, in the one array" described two
     assertions together, and one of them was the redundant line.
   - Fix: The comment now names the slice 1 assertion that carries the
     same-array half.
   - **Status**: FIXED

## Wrong-reason hunting

- **Named failing state** for `survives`: install replaces `.hooks.SessionStart`
  or clears it (count 0), or install copies the consumer's entry (count 2). The
  old stub-from-scratch fallback, which rewrote the whole file, also gives 0.
- **Bare negative?** A preservation assertion passes when nothing touches
  `SessionStart` at all. That makes it a bare negative only if nothing pairs it
  with a positive. Slice 1's `install adds the session-start hook once` is that
  positive over the same fixture and the same array, so the pair cannot go
  vacuous.
- **Birth state**: the fixture holds the entry at count 1. That is the point of
  a survival check, and it is non-vacuous because of the positive above plus the
  demonstrated mutation red.
- **Does the fixture change weaken slice 1 or slice 2?** No:
  - `install adds the session-start hook once` keeps only entries whose hooks
    carry `$session_cmd`. The consumer's matcher-less entry does not carry it,
    so it never adds a `none` to the joined output. Under a duplicating mutation
    the result is still `none none`, and under a wrong matcher it is still
    `matcher=…`.
  - `the commands quote the project dir` filters on `dogfood.sh`, so
    `echo consumer-start` stays out of both counts (`2:2`).
  - The PreToolUse assertions do not read `SessionStart`.
  - The slice 2 re-run `cmp` now also covers a mixed `SessionStart` array, which
    makes it stronger.

## Fixes Applied

- `tests/update-plugin-dev-test.sh`: removed the redundant `sits beside`
  assertion (2 lines) and rewrote the preceding comment to point at slice 1's
  assertion. The file went from 446 to 445 lines, and `shellcheck` is clean.

## Post-fix run

The suite is green against the unmutated SUT: exit 0,
`update-plugin-dev scenarios passed`. Because this slice is proven by mutation,
the "still red" check is the mutation run above: its one named test reds on its
own assertion.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Slice 3: consumer's `SessionStart` survives beside the new one | Satisfied | fixture entry `echo consumer-start`; `a pre-existing SessionStart entry survives` + slice 1's `install adds the session-start hook once` over the same array |

## Positive Observations

- The fixture extends the existing scenario rather than adding a new one, so
  both the slice 1 assertions and the slice 2 re-run `cmp` now also run against
  a consumer `SessionStart` entry.
- The survival assertion follows the pattern of the existing PreToolUse
  `kept the consumer's own matcher-less hook` assertion.

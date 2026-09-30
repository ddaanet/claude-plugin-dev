# Review: Item 2.2 slice 4 — test review (idempotency ignores the matcher)

**Scope**: the uncommitted diff to `tests/update-plugin-dev-test.sh` (scenario
`install.sh: wires into an existing settings.json without replacing it`) and the
RED report `item-2-2-s4-red.md`. `toolkit/install.sh` touched only by a
temporary in-place mutation, restored. **Date**: 2026-09-30 **Mode**: review +
fix

## Summary

The slice adds one test, `an entry under another matcher counts as present`: it
rewrites the matchers of the pre-tool and version-guard entries to `Bash`,
re-runs install, and `cmp`s `settings.json`. The setup assertion and the `cmp`
are sound, and a second mutation that differs from the RED report's reds the
test on its assertion. Two issues fixed: one wrong-reason gap (nothing proved
the third run reached step 3) and one redundant copy.

**Overall Assessment**: Ready

## Mechanical check — mutation proof reproduced

The RED report's mutation was null-or-`Write|Edit`. This review used a different
one: presence requires the entry's matcher to **equal** the one being installed.

- from:
  `([.hooks[$event][]? | .hooks[]? | select(.command == $cmd)] | length > 0)`
- to:
  `([.hooks[$event][]? | select((.matcher // "") == $matcher) | .hooks[]? | select(.command == $cmd)] | length > 0)`

Landing proof: the source string occurred once, and the target string occurred
once after the edit. Mutated run: 2 failures, both this slice's and nothing
else:

```text
FAIL: an entry under another matcher counts as present: settings.json changed
FAIL: an entry under another matcher counts as present: report: output did not contain 'already installed, nothing to do'
```

Slices 1–3 and the setup assertion held, because exact-equality presence still
finds every entry the installer wrote itself. Restore: the inverse replacement.
Proof: grep for `select((.matcher // "") == $matcher)` finds 0 hits,
`git diff --stat toolkit/install.sh` is empty, and the suite passes
(`update-plugin-dev scenarios passed`).

## Wrong-reason hunting

- **Rewrite matched nothing.** Ruled out: the setup assertion needs exactly two
  hooks carrying the pre-tool or version-guard command, both under `Bash`. An
  unchanged file would read `Write|Edit Write|Edit|NotebookEdit`.
- **Rewrite touching the consumer's `echo consumer-hook` entry.** It does not.
  The jq predicate is `any(.hooks[]?; .command == $p or .command == $v)`, which
  is false for that entry. Even if it did match, the test could not go vacuous:
  that entry carries neither command, so it never satisfies either presence
  check.
- **`cp` over `settings.json` versus the file-mode assertion.** The mode
  assertion runs earlier in the scenario, and `cp` onto an existing file keeps
  the destination's mode anyway. No ordering problem.
- **Does the re-run reach step 3?** The `cmp` alone cannot tell. An install that
  failed or exited before step 3 would leave the file byte-identical and pass.
  The mutation run shows step 3 is reached today, but nothing in the test would
  catch a later early exit. Fixed (Major 1).
- **SessionStart side of "whatever the matcher, or none".** Not added. The slice
  text names only the pre-tool and version-guard entries. Slice 2's re-run
  already covers the matcher-less SessionStart entry being found. A consumer who
  rescoped the session-start entry to e.g. `startup` would need a mutation that
  treats SessionStart apart from PreToolUse, and `add_hook` is one function for
  all three calls, so that would take a deliberate special-case. This is a
  residual gap, not a real one. It is noted here and left alone.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **`cmp` passes if install stops before step 3**
   - Location: tests/update-plugin-dev-test.sh, slice 4 block (third
     `install.sh` run)
   - Problem: neither `$rc` nor `$out` was checked. A run that errored out or
     exited before step 3 leaves `settings.json` untouched, so the `cmp` holds
     for the wrong reason.
   - Suggestion: assert the run's report, `already installed, nothing to do`.
     Only a run that got past step 3 with `changed` empty prints it, so it
     proves both that step 3 was reached and that nothing was written.
   - **Status**: FIXED

### Minor Issues

1. **Redundant snapshot copy**
   - Location: tests/update-plugin-dev-test.sh, slice 4 block
   - Note: `cp "$settings_json" "$sandbox/settings.before"` duplicated
     `$sandbox/settings.rematched`, which `settings.json` had just been copied
     from. The `cmp` now reads `settings.rematched` directly, which saves a line
     in a file already over 400 lines.
   - **Status**: FIXED

## Fixes Applied

- tests/update-plugin-dev-test.sh, slice 4 block: dropped the second
  `settings.before` copy; the `cmp` now compares against
  `$sandbox/settings.rematched`.
- tests/update-plugin-dev-test.sh, slice 4 block: added
  `assert_contains "$out" "already installed, nothing to do" "an entry under another matcher counts as present: report"`,
  with a one-line comment on why the `cmp` alone does not prove step 3 ran.
- Net: the file is 460 lines (it was 459 before the fixes). Moving the
  install.sh scenarios into their own suite is out of scope (phase boundary).

## Verification

- Unmutated SUT: `bash tests/update-plugin-dev-test.sh` passes
  (`update-plugin-dev scenarios passed`), and `shellcheck` is clean.
- Mutated SUT (above): both of this slice's assertions go red. Restore verified.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| Slice 4: re-install after rematching to `Bash` leaves `settings.json` byte-identical | Satisfied | `cmp` against `settings.rematched`; reds under two distinct matcher-sensitive mutations |
| Interfaces: present = same command under the same event, whatever the matcher | Satisfied for PreToolUse | SessionStart variant not covered (noted above; outside the slice's literal text) |

## Positive Observations

- The setup assertion pins exactly which hooks were rematched. It shows the
  rewrite landed, so the test cannot be satisfied by the state slice 2 left
  behind.
- The rewrite is keyed on command identity rather than array position, so it
  does not depend on the order in which install appended entries.

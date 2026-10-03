# Review: Item 1.1/1 test review — the shim syncs only outside a dogfood session of its own repo

**Scope**: uncommitted changes to `tests/dogfood-launcher-test.sh`, and the RED
report `reports/item-1-1-s1-red.md`. `toolkit/bin/claude` was mutated in place
for the proofs only, and restored each time. **Date**: 2026-10-03 **Mode**:
review + fix

## Summary

The RED's three scenarios are sound. Scenario 2 reds on its assertions against
the current shim, and scenarios 1 and 3 each red under an independent mutation.
Two plausible-but-forbidden implementations passed the whole suite as delivered.
One compared the variable against a logically resolved `<root>`, when the
decision names the physical one. The other matched the copy as one entry of a
`:` list, the way `session-start` does, when the decision says "equals". The fix
gives scenario 2 a symlinked shim spelling and adds one list-valued scenario.
Each of those mutants now dies, and the decision's own implementation turns the
whole suite green.

**Overall Assessment**: Ready

## Mechanical check

The current shim (unchanged), with the suite as fixed, fails only on scenario
2's two assertions:

- `FAIL: a variable equal to this copy skips the sync: no copy made: '…/my consumer/dist' exists`
- `FAIL: a variable equal to this copy skips the sync: no copy as the next claude started: expected 'absent', got 'present'`

There were no ERRORs and no other FAILs. All 15 scenario headers printed, so no
early exit happened.

## Mutation proofs (in place, each restored by inverse exact replacement)

All mutations replace line 19, `bash "$root/plugin-dev/dogfood.sh" sync`.

| Mutant | Shim behaviour | Result |
|---|---|---|
| A | syncs only when `CLAUDE_CODE_PLUGIN_DIRS` is non-empty | Scenario 1 reds: `copy … expected 'present', got 'absent'` and `plugin.json is not a regular file`. Also reds the failed-sync and 127 scenarios, which run with the variable unset. |
| B | syncs only when the variable is empty or unset, the most plausible wrong reading | **Only scenario 3 reds**: `an inherited variable naming another path still syncs: expected 'present', got 'absent'` and the `plugin.json` check. Scenario 2 goes green, which proves its prefix assignment reaches the shim. |
| C | compares against `$(cd -- "$here/../.." && pwd)/dist/plugin`, a logical root | Before the fix: **the whole suite passes**. After: scenario 2 reds on both assertions. |
| D | whole-entry match, `":$V:" == *":$root/dist/plugin:"*` | Before the fix: the suite passes, since no scenario has a list value. After: the new list scenario reds (`expected 'present', got 'absent'`). |
| GREEN probe | `[[ "${V:-}" != "$root/dist/plugin" ]] && sync`, the decision itself | **The whole suite passes.** The fixed tests can be satisfied, and no test pins more than the decision. |

Restore check after each one: `grep -cE 'MUTANT|PROBE' toolkit/bin/claude` → 0,
and `git diff --stat toolkit/bin/claude` was empty. Both were rechecked after
the last restore.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Scenario 2 could not detect a comparison against a logical `<root>`**
   - Location: `tests/dogfood-launcher-test.sh`, scenario "a variable equal to
     this copy skips the sync"
   - Problem: the shim was reached through `$consumer/plugin-dev/bin`, a
     physical spelling, because `make_consumer` takes `$sandbox` from `pwd -P`.
     With that spelling the logical and physical roots are the same string.
     Mutant C, which resolves `<root>` without `-P`, passed every scenario. The
     decision names the physical root. A nested `claude` can reach the shim
     through any spelling PATH holds, while the variable it inherits is always
     the physical copy the outer shim exported.
   - Fix: scenario 2 now symlinks `$sandbox/link` to the consumer and puts
     `$sandbox/link/plugin-dev/bin` on PATH, which is the existing "shim exports
     the copy" idiom. The variable stays `$consumer/dist/plugin`, the physical
     spelling. A comment states why.
   - **Status**: FIXED. Mutant C now reds scenario 2, and the GREEN probe
     passes.

### Minor Issues

1. **Nothing pinned "equals" against "lists the copy as one entry"**
   - Location: `tests/dogfood-launcher-test.sh`, after scenario 3
   - Note: `session-start` matches the copy as a whole entry of a `:` list (D7),
     so copying that matcher into the shim is a plausible implementation, and
     mutant D passed the suite. The decision says "equals".
   - Fix: added the scenario "a variable listing this copy among others syncs".
     It sets
     `CLAUDE_CODE_PLUGIN_DIRS="$consumer/dist/plugin:/elsewhere/dist/plugin"`.
     The copy is listed first, so a prefix glob dies too. The scenario asserts
     the copy was present at exec and that the variable became the copy alone.
   - **Status**: FIXED. Mutant D now reds the new scenario, and the GREEN probe
     passes.

## Wrong-reason hunt (no further findings)

- **Physical spelling of scenario 2's variable**: `$consumer` comes from
  `$sandbox`, which is set by `cd "$(mktemp -d)" && pwd -P`. The value therefore
  holds where `/tmp` sits under a symlink, as on macOS where `/tmp` points to
  `/private/tmp`. The shim computes `<root>` with `cd -P`, so the two strings
  match.
- **Variable state pinned per scenario**: scenario 1 unsets the variable
  explicitly, on top of the suite-wide unset at line 20. Scenarios 2, 3 and the
  new one use a function-call prefix assignment. A probe confirmed this reaches
  the child (`in:1`) and does not persist afterwards (`after:unset`), so no
  scenario inherits another's value. Mutant B confirmed the value is delivered
  to the shim end to end.
- **Birth-state negative in scenario 2** (`dist` absent, copy `absent`): the
  matching positive is scenario 1, run on the same fixture with only the
  variable different, and it asserts the copy is present. The negative cannot
  turn vacuous without scenario 1 going red.
- **"still execs with the variable"**: this check passes under the current shim,
  so on its own it is not evidence. It is kept on purpose: it pins the export
  and exec half of the decision. Together with the `pid` and `rc` checks it
  rules out a GREEN that skips the sync by exiting early.
- **Production invocation**: `run_claude` execs `claude` by PATH lookup from
  `$launch_dir`, with the shim ahead of the stub. That is the path a developer
  or a nested agent `claude` takes.
- **Assertions reached**: `run_claude` brackets the launch with `set +e` and
  `set -e`, and every header printed in each run.

## Fixes Applied

- `tests/dogfood-launcher-test.sh`, scenario 2: the shim is now reached through
  a symlinked consumer spelling, and the comment says why.
- `tests/dogfood-launcher-test.sh`: new scenario "a variable listing this copy
  among others syncs", placed after "an inherited variable is overwritten".
- `shellcheck tests/dogfood-launcher-test.sh` is clean.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| (1) variable unset → syncs | Satisfied | scenario "the shim syncs before exec", killed by mutant A |
| (2) variable equal to this copy → no sync, still execs with the variable | Satisfied (red, as designed) | scenario "a variable equal to this copy skips the sync", now also pins the physical root (mutant C) |
| (3) variable naming another path → syncs and overrides it | Satisfied | scenario "an inherited variable is overwritten", killed by mutant B; list case added (mutant D) |

**Gaps:** none.

## Positive Observations

- Scenario 2 asserts the absence of the copy *at exec time* through the stub's
  record, as well as `dist` after the run. A sync that ran after exec, or in the
  background, could not pass it.
- Scenario 2's `pid` assertion makes "still ran" mean the exec happened, not
  just that something exited 0.
- The RED report's mutation proof listed its collateral reds (the failed-sync
  and 127 scenarios) instead of hiding them.

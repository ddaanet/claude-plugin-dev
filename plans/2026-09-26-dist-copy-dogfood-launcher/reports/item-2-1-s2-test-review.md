# Review: Item 2.1 slice 2 — test review (RED, mutation-proven)

**Scope**: the new scenario `an inherited variable is overwritten` in
`tests/dogfood-launcher-test.sh` (`git diff`), and the RED report
`reports/item-2-1-s2-red.md`. `toolkit/bin/claude` was touched only by
mutations, each one restored. **Date**: 2026-09-30 **Mode**: review + fix

## Summary

The scenario is sound. The inherited value is scoped to its single `run_claude`
call. The assertion is exact string equality against the physical
`<root>/dist/plugin`. A stub that never ran cannot satisfy it. Three wrong shims
of my own choosing each red the named test on its own assertion. The one the RED
report used (prepend the inherited value) is not among them. I found nothing to
fix.

**Overall Assessment**: Ready

## Mechanical check: the mutation proof, reproduced independently

The RED report's mutation prepended the inherited value
(`${CLAUDE_CODE_PLUGIN_DIRS:+$CLAUDE_CODE_PLUGIN_DIRS:}$root/dist/plugin`). I
used three different ones. Each is a single exact-string replacement of line 18,
`export CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin"`. Each was restored by
applying the inverse replacement before the next one was applied. The suite ran
in the foreground each time.

| Mutation (line 18) | Result |
|---|---|
| keep an inherited value: `export CLAUDE_CODE_PLUGIN_DIRS="${CLAUDE_CODE_PLUGIN_DIRS:-$root/dist/plugin}"` | `FAIL: an inherited variable is overwritten: expected '<sandbox>/my consumer/dist/plugin', got '/elsewhere/dist/plugin'`, `1 failure(s)`, rc 1 |
| skip the export when set: `[[ -v CLAUDE_CODE_PLUGIN_DIRS ]] \|\| export …="$root/dist/plugin"` | same failure, `got '/elsewhere/dist/plugin'`, rc 1 |
| append the inherited value: `"$root/dist/plugin${CLAUDE_CODE_PLUGIN_DIRS:+:$CLAUDE_CODE_PLUGIN_DIRS}"` | `got '<sandbox>/my consumer/dist/plugin:/elsewhere/dist/plugin'`, rc 1 |

In every run, the other four scenarios stayed green. So each red comes from this
test's assertion alone, and the mutations are indistinguishable from the correct
shim when no variable is inherited.

Restore verification after the last inversion:

- `grep -nE 'PLUGIN_DIRS:[-+]|-v CLAUDE_CODE_PLUGIN_DIRS' toolkit/bin/claude`
  found no hit (rc 1).
- `git diff --quiet toolkit/bin/claude` succeeded, so the SUT is identical to
  HEAD.
- The suite printed `all dogfood launcher scenarios passed`, rc 0.
- `git status` shows only the scenario diff and the RED report, plus sandbox
  masks.

## Wrong-reason hunting

- **Scoping, so later scenarios don't inherit the value.** The value is set as a
  prefix assignment on a shell function
  (`CLAUDE_CODE_PLUGIN_DIRS=/elsewhere/dist/plugin run_claude`). In bash
  (non-POSIX mode) that variable is exported for the duration of the call and
  removed afterwards. I probed both directions on bash 5.2.37:
  - A child process of the function saw `/elsewhere/dist/plugin`.
  - After the function returned, `${CLAUDE_CODE_PLUGIN_DIRS-<unset>}` read
    `<unset>`. This held also with `POSIXLY_CORRECT=1` and with `set -o posix`.
  - The runs above prove the value reaches the stub through the launch
    subshell's `exec`, the shim and its `exec`: the keep, skip and append
    mutations all recorded it.
  - Together with the prologue's `unset CLAUDE_CODE_PLUGIN_DIRS`, every other
    scenario, present or future (slices 3–6), starts with the variable unset.
  - Residual bound: older bash in POSIX mode keeps prefix assignments to
    functions after they return. The suite runs under `bash`, not in POSIX mode,
    so this does not apply.
- **Exact equality, not a substring.** `assert_eq` compares with
  `[[ "$1" != "$2" ]]` and quotes the right-hand side, so it is a literal
  comparison, not a glob match. Both the RED report's prepend
  (`/elsewhere/dist/plugin:<root>/dist/plugin`) and my append
  (`<root>/dist/plugin:/elsewhere/dist/plugin`) contain the expected value as a
  substring, and both red.
- **`<root>` is physical.** `$consumer` is `$sandbox/my consumer`, and
  `$sandbox` comes from `pwd -P`. This scenario uses the default physical
  `$shim_dir` and `$launch_dir`. The physical-vs-logical and launch-directory
  cases are pinned by slice 1's `the shim exports the copy` scenario. This
  test's job is to prove the overwrite, which it does independently of those
  cases.
- **Stale record when the stub never ran.** `make_consumer` creates a fresh
  `mktemp -d` sandbox with an empty `rec/` directory for this scenario. If the
  stub never ran, `recorded plugin_dirs` returns
  `<stub did not record plugin_dirs>`, which cannot equal the expected path. No
  record file from an earlier scenario is reachable.
- **Birth state.** The expected value differs from the inherited one, and the
  fixture starts with the variable set to `/elsewhere/dist/plugin`, not unset.
  So the test asserts a transition. A shim that does nothing to the variable
  records `/elsewhere/dist/plugin` and reds, as the keep and skip mutations
  show.
- **Decoy plausibility.** `/elsewhere/dist/plugin` is an absolute path shaped
  like a real copy. A shim that keeps "a valid-looking inherited value" cannot
  pass by rejecting a malformed decoy.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

None.

## Fixes Applied

None were needed. `tests/dogfood-launcher-test.sh` is unchanged by this review.
`toolkit/bin/claude` is byte-identical to HEAD (`git diff --quiet`).

`bash -n` and `shellcheck` are clean on the suite, which is 198 lines.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D9 shim exports `CLAUDE_CODE_PLUGIN_DIRS=<root>/dist/plugin` (overwrite, not merge) | Covered for slice 2 | keep, skip, append and prepend mutations all red this scenario |
| D4 / D8 | Not in slice 2 | slices 1 and 5 |

## Positive Observations

- The prefix assignment keeps the inherited value local to the one call. That is
  the shape slice 1's test review recommended, and it needs no cleanup line.
- The RED report's mutation (prepend) and this review's (keep, skip, append)
  together cover every way a shim can treat an inherited value other than
  overwriting it.

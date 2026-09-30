# Review: Item 2.1 slice 5 test — a failed sync aborts the launch

**Scope**: the new scenario in `tests/dogfood-launcher-test.sh`
(`git diff tests/dogfood-launcher-test.sh`) and `reports/item-2-1-s5-red.md`.
SUT `toolkit/bin/claude` touched only through mutations, each restored.
**Date**: 2026-09-30 **Mode**: test review + fix

## Summary

The scenario rebuilds a fresh fixture, removes the manifest, and asserts rc 1, a
stderr line naming the manifest, and no stub record. The status and no-exec
assertions are sound. The stderr check was weaker than D8 needs: a bare
`.claude-plugin/plugin.json` substring, not tied to sync's own `dogfood:` line
or to the resolved root. It is now tightened. A mutation that silences sync's
stderr, which the RED report did not try, reds on that assertion alone.

**Overall Assessment**: Ready

## Mechanical check (mutation proof, own mutations)

The test passes at HEAD, as expected under `set -euo pipefail`, so the proof is
by mutation of `toolkit/bin/claude`'s sync line. Each mutation was applied by an
exact Edit and restored by the inverse Edit.

1. `... sync` → `... sync 2>/dev/null`. This mutation exercises D8's "loud"
   half. Result: suite rc 1, one failure only:
   `a failed sync aborts the launch: stderr does not carry sync's refusal:`
   (empty stderr). Status and no-exec stay green, as they should, because the
   shim still aborts.
2. `... sync` → `... sync || trap 'exit 1' EXIT`. This is the "execs anyway,
   exits 1 from a trap" shape. Result: suite rc 1, three failures:
   `expected '1', got '0'`, `rec/argv exists`, `rec/pid exists`. `exec` replaces
   the process image and discards the trap, so the stub's exit 0 becomes the
   launch status. The stub records either way.

Restore verified after the final inverse Edit:
`grep -nE '2>/dev/null|trap' toolkit/bin/claude` found no hit,
`git diff --quiet toolkit/bin/claude` succeeded, and the suite was green
(`all dogfood launcher scenarios passed`). `bash -n` and `shellcheck` are clean
on the test file.

Per-test result after the fix: `a failed sync aborts the launch` passes at HEAD,
reds on mutation 1 (the stderr assertion) and on mutation 2 (status plus both
no-record assertions). Together with the RED report's `|| true` (all three) and
`|| exit 0` (status only), every assertion has a mutation that reds it alone or
together with the others.

## Wrong-reason hunting

- **Stderr check is sync's own line, unredirected.** Before the fix, any line
  containing `.claude-plugin/plugin.json` satisfied it. That could be a
  shim-side pre-check message, or a sync that resolved the wrong root and still
  named a manifest. Now it requires
  `dogfood: $consumer/.claude-plugin/plugin.json`, which is sync's
  `require_manifest` prefix plus the physical root (the path contains a space).
  A redirect or a reworded shim-side message fails it (mutation 1). The trailing
  wording (`not found; sync refused`) is deliberately left unpinned: that
  belongs to dogfood.sh's contract, not the launcher's.
- **"No record" is non-vacuous.** `make_consumer` creates a fresh `mktemp -d`
  sandbox with an empty `rec/`. The stub writes `argv` and `pid` unconditionally
  when it runs. Mutation 2 and the RED report's `|| true` both show the records
  appearing.
- **Exec anyway plus trap exit 1.** Cannot pass: `exec` drops the trap, so rc is
  the stub's 0 and the records exist (mutation 2). Running the next claude as a
  child and then `exit 1` would pass the status check and fail both no-record
  checks.
- **Per-scenario state.** `make_consumer` resets `sandbox`, `consumer`,
  `shim_dir`, `launch_dir`, `stubdir` and `path_head=""`. The previous
  scenario's `PATH="$runner_path"` is a function-call prefix and does not
  persist in bash. Its `runner_path`, `rest` and `entry` leak but are unread
  here.
- **Could rc 1 come from elsewhere?** A shim failing before sync for another
  reason would have no `dogfood: <root>/…` line, and a missing `dogfood.sh`
  exits 127. The stderr pin closes this.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Stderr assertion is a substring another line satisfies**
   - Location: `tests/dogfood-launcher-test.sh`, scenario
     `a failed sync aborts the launch`, the `grep -qF` check
   - Problem: `.claude-plugin/plugin.json` alone does not show that the line is
     sync's refusal (D8) or that sync resolved the consumer's root. Any message
     mentioning the manifest passes.
   - Fix: match `dogfood: $consumer/.claude-plugin/plugin.json`. Add a one-line
     comment giving the check's intent, and relabel the failure message.
   - **Status**: FIXED

### Minor Issues

None.

## Fixes Applied

- `tests/dogfood-launcher-test.sh` (slice 5 scenario): the stderr grep now pins
  sync's `dogfood:` prefix and the physical consumer root. Added a comment
  stating the check's intent. Failure label changed to "stderr does not carry
  sync's refusal". Suite re-run green at HEAD. The sync-stderr mutation reds on
  this assertion alone.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| D8 — sync failure is loud, aborts before exec | Satisfied (test) | rc 1, sync's `dogfood:` line on stderr, no stub record; mutations 1–2 and RED-report mutations |
| Slice 5 spec (rc 1, stderr names manifest, no record) | Satisfied | all three assertions present; stderr check strengthened within the spec |

## Positive Observations

- Two no-record assertions over files the stub writes unconditionally, on a
  fresh sandbox. The absence check has something to detect.
- The RED report's second mutation (`|| exit 0`) separates the status assertion
  from the no-exec ones, so neither rides on the other.

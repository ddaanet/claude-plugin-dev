# Review: Item 1.2/1 test review — `pre-tool` never exits 2 on a jq failure

**Scope**: uncommitted changes to `tests/dogfood-pre-tool-test.sh` and the RED
report `reports/item-1-2-s1-red.md`. `toolkit/dogfood.sh` was read for the
analysis and mutated once in place for a probe, then restored. **Date**:
2026-10-03T21:49:28+02:00 **Mode**: review + fix

## Summary

The RED change tightens the existing unreadable-payload scenario from "non-zero"
to exactly `1`, and adds a stub-jq scenario that exits 2. Both are sound and red
on their exit-code assertions. They pin only the first of `pre_tool`'s two jq
calls, though. A GREEN that maps only the payload read (`... || exit 1` on
`dogfood.sh`'s `path=` line) passed both, which would have left the
deny-building `jq -nc` free to exit 2. A third scenario now closes that gap.

**Overall Assessment**: Ready

## Mechanical check

The RED report's claims were reproduced against the unchanged SUT (jq 1.7):

- Test 1 FAILED with `exit code: expected '1', got '5'`. This is an assertion,
  not an ERROR.
- Test 2 FAILED with `exit code: expected '1', got '2'`. This is an assertion.
- In both tests the stdout-empty and stderr-diagnostic assertions pass. Every
  other scenario is green. Neither test PASSED or ERRORed.

## Wrong-reason hunting

- **Only the first jq call mapped.** `pre_tool` calls jq twice: once to read the
  payload and once in `jq -nc --arg …` to build the deny. Test 1 and test 2 both
  fail at the read, so the deny build is never reached. A GREEN that maps only
  the read passes both. This was confirmed by a probe, below. **Finding 1.**
- **Exit 0 (silently allowing) on jq failure.** It cannot pass. Every scenario
  asserts `rc == 1` exactly, and each asserts the diagnostic on stderr, so a
  `2>/dev/null || exit 0` GREEN fails twice.
- **Mapping only status 2.** For example, `[[ $rc == 2 ]] && exit 1`. It fails
  test 1, where the real jq 1.7 exits 5. Tests 1 and 2 together pin "any jq
  failure", not one status value. On a jq 1.6 host test 1 would see 2, and the
  stub still covers the other side only partially. That is acceptable, because
  the outline names the requirement as "any".
- **Mapping every non-zero exit of the script to 1.** For example,
  `main "$@" || exit 1`, or an ERR trap. This is acceptable, not wrong. The
  code's own comment (`pre_tool`'s header) puts "a directory on the path that
  cannot be entered" under the same contract as an unreadable payload: "stops
  the script non-zero: Claude Code shows a non-blocking hook error".
  `physical_path` already exits 1 there. Collapsing every failure to 1 therefore
  honours that contract, and the outline asks for no distinction between failure
  kinds. The suite has no unenterable-directory scenario (`rg -i 'enter|chmod'`
  finds none). A blanket map would also cover the missing scenario, and adding
  one is outside this slice.
- **`command -v jq` with the stub.** The stub is an executable file first on
  PATH, so `command -v` finds it and the stand-down guard does not fire. Each
  stub scenario asserts this before it runs. The stub's directory name holds a
  space, which also exercises PATH whitespace safety.
- **Are the assertions reached?** Yes. `run_dogfood` brackets the run with
  `set +e`/`set -e`, and `assert_eq` and `assert_contains` record failures
  without exiting. The run above printed every FAIL line.

## Issues Found

### Major Issues

1. **The deny-building jq call is untested, so "any jq failure" is only
   half-pinned.**
   - Location: `tests/dogfood-pre-tool-test.sh`, after the scenario "pre-tool
     maps a jq exit of 2 to a non-blocking status".
   - Problem: both new and tightened scenarios fail at the payload read. A GREEN
     that guards only that call passes the slice, while the `jq -nc` deny build
     still exits with jq's own status, which can be 2.
   - Fix: add a new scenario, "pre-tool maps a jq failure building the deny to a
     non-blocking status". It uses a stub `jq` (in `stub bin/`, with a space in
     the name) that `exec`s the real jq for every call except one whose
     arguments contain `permissionDecision`, which is the deny filter. That one
     call prints `jq: stub failure building the deny` and exits 2. The stub
     matches on the filter's purpose, not on flag spelling, so reordering
     `-nc`/`-cn` in GREEN does not dodge it.
     - The payload is built with the real jq before the stub goes on PATH,
       because `run_pre_tool` would call the stub.
     - A control run with the real jq first asserts the full deny on the same
       payload. This shows the path reaches the deny branch.
     - The assertions are `rc == 1`, empty stdout, and the stub's diagnostic on
       stderr. The diagnostic is the positive proof that the read passed through
       to the real jq and the deny build was reached. A broken passthrough would
       fail at the read, without that message.
   - **Status**: FIXED

### Minor Issues

None.

## Fixes Applied

- `tests/dogfood-pre-tool-test.sh`: added the deny-build scenario described in
  Major 1, with a comment naming the GREEN it rules out.
- `plans/2026-10-03-dogfood-review-fixes/reports/item-1-2-s1-red.md`: appended
  an addendum recording the third test and its red output, so the RED report
  still matches the suite.

## Verification

- `shellcheck tests/dogfood-pre-tool-test.sh` is clean.
- `bash tests/dogfood-pre-tool-test.sh` was run in the foreground against the
  unchanged SUT and gave 3 failures. Every other scenario is green, including
  the new scenario's real-jq control:
  - `pre-tool fails loudly on a payload jq cannot read exit code: expected '1', got '5'`
  - `pre-tool maps a jq exit of 2 to a non-blocking status exit code: expected '1', got '2'`
  - `pre-tool maps a jq failure building the deny to a non-blocking status exit code: expected '1', got '2'`
- Mutated-SUT probe: `|| exit 1` was appended to `dogfood.sh`'s
  `path="$(jq -j …)"` line, which is the plausible half-GREEN. The suite then
  showed tests 1 and 2 green and only the new scenario red
  (`expected '1', got '2'`). The edit was restored by inverse exact replacement,
  and `git diff --stat toolkit/dogfood.sh` is empty.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| m1: never exit 2 on any jq failure | Satisfied (tests) | Read-path failures with status 5 (real jq) and 2 (stub), plus the deny-build failure with status 2 (stub), all assert `rc == 1` |
| m1: map to a non-blocking non-zero status | Satisfied (tests) | `assert_eq "$rc" "1"` in all three scenarios; exit 0 and exit 2 both fail |
| m1: assert the exact status in the suite | Satisfied | Test 1's `!= 0` check is replaced by `assert_eq … "1"` |

## Positive Observations

- Each stub scenario asserts that the stub is the `jq` that `command -v` finds,
  so a PATH mistake cannot pass as a stand-down.
- Test 1 keeps the real jq. Its version-varying status (5 on 1.7) is what rules
  out a GREEN keyed on status 2.
- The stub diagnostic is checked on stderr, so a GREEN that suppresses jq's
  stderr fails as well. This matches the repo's no-stderr-suppression rule.

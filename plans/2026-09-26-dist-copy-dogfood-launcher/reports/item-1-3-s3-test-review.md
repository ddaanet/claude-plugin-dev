# Review: Item 1.3/3 test review — mismatches warn on both channels

**Scope**: `git diff tests/dogfood-test.sh` (three new session-start scenarios,
new helper `assert_session_warns`, and the 1.3/1 warn test's assertions), the
RED report `item-1-3-s3-red.md`. SUT `toolkit/dogfood.sh` mutated in place for
the checks only; no SUT change survives. **Date**: 2026-09-30 **Mode**: review +
fix

## Summary

The three scenarios are sound: each fixture carries the discrimination its label
claims, and each reds on its own assertions under a mutation different from the
RED report's. One gap: the helper dropped the slurped one-object check the 1.3/1
warn test carries, so the new tests did not pin the interface's "one object".
Fixed by adding it to the helper and routing the 1.3/1 warn test through the
helper, which removes the duplication.

**Overall Assessment**: Ready

## Mechanical check: mutation proofs reproduced

Each mutation is an exact replacement of text occurring once in
`toolkit/dogfood.sh`, confirmed landed by a grep count of 1 before the run, and
restored by the inverse replacement. After each restore a grep for the mutant
text found nothing and `git diff --quiet toolkit/dogfood.sh` held.

| Test | Mutation (anchor `[[ "$entry" == "$copy" ]] && exit 0`) | 1.3/3 reds | Other reds |
|------|------|------|------|
| another repo's copy | structural "is a copy": `[[ -f "$entry/../../plugin-dev/dogfood.sh" ]]` | this test only: systemMessage, hookEventName, additionalContext | 1.3/2 `plugin<LF>`, relative entry |
| `/x<root>/dist/plugin` | suffix: `[[ "$entry" == *"$copy" ]]` (the outline's `/other/<root>/dist/plugin` shape) | this test only, same three | none |
| `<root>/dist/plugin/skills` | under the root: `[[ "$entry" == "$root"/* ]]` | this test only, same three | 1.3/2 `plugin<LF>` |

Every red is `... is not true over stdout ''`: the mutant went silent, and the
assertion, not a harness error, reported it. The RED report's mutations
(`*/dist/plugin`, substring, prefix) were not reused.

## Wrong-reason hunting

- **`<other>` is a separate real copy.** Each `make_consumer` takes a fresh
  `mktemp -d`, so `other_root` and `root` differ in the sandbox component only;
  the other copy is synced and its existence asserted. Both fixtures share the
  repo name `my consumer` and the manifest name `fixture`, which strengthens the
  test: an implementation matching a tail such as `my consumer/dist/plugin`, or
  identifying a copy by its manifest or its vendored `dogfood.sh` (mutation
  above), goes silent and reds.
- **`/x<root>/dist/plugin` takes the literal branch.** `/x` does not exist, so
  `-d` is false and the entry skips `physical_path`. Even without the guard,
  `physical_path` would return the same spelling, since no component under `/x`
  exists. The observable reds only under a partial match, which is what the
  test's comment and label claim.
- **"Unresolved entry compared literally, trailing slash stripped" gets no pin
  here, and `/x<root>/dist/plugin/` would not supply one.** That entry warns
  whether or not the slash is stripped, so a test named for stripping would
  claim coverage it lacks. The strip is observable only when an unresolved entry
  equals `<copy>/` literally: the copy is absent (ruled out by the orchestrator)
  or sealed against `-x`, which pins nothing when the suite runs as root (the
  sealed-directory scenario's own caveat). No test added.
- **Birth state.** The warning is the default output, so each test on its own is
  a negative for the match. The silent-on-copy test is the positive over the
  same fixture shape, differing only in the entry, and the three mutations show
  each entry fails a distinct wrong matcher.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Helper does not pin "one object"**
   - Location: tests/dogfood-test.sh, `assert_session_warns`
   - Problem: the Item 1.3 interface says "one object", and the 1.3/1 warn test
     checks it with a slurped `length == 1`. The helper omitted that check. The
     per-field `jq_holds` calls use `jq -e`, which judges only the last output,
     so a SUT printing a stray value before the warning passed all three new
     tests. A mutant prefixing the warning with `jq -nc '{}';` passed every
     assertion the helper made.
   - Suggestion: add the slurped one-object check to the helper.
   - **Status**: FIXED. Under that mutant, the 1.3/1 warn test and all three
     1.3/3 tests now red on `stdout is one JSON object`, and on nothing else.
     Restored and verified as above.

### Minor Issues

1. **1.3/1 warn test duplicates the helper**
   - Location: tests/dogfood-test.sh,
     `session-start warns when the variable is unset`
   - Note: its six assertions were the helper's body plus the one-object check.
     The helper is now defined after `run_session_start`, ahead of its first
     user, and the 1.3/1 test calls it. Labels are unchanged, so failure output
     reads the same.
   - **Status**: FIXED

## Fixes Applied

- tests/dogfood-test.sh: moved `assert_session_warns` to follow
  `run_session_start` (bash needs it defined before the 1.3/1 call), added
  `jq_holds "$label: stdout is one JSON object" ... -s`, and updated its comment
  to say it checks for one object.
- tests/dogfood-test.sh: the 1.3/1 warn test now calls
  `assert_session_warns "$label" "$root"` in place of its inline assertions.

The suite passes against the committed SUT (`all dogfood scenarios passed`), and
`shellcheck tests/dogfood-test.sh` is clean. The file is 841 lines; the split is
deferred to the phase boundary.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| `<other>/dist/plugin` warns on both channels | Satisfied | "session-start warns on another repo's real copy" |
| `/x<root>/dist/plugin` warns | Satisfied | "session-start warns on a longer, non-existent entry" |
| `<root>/dist/plugin/skills` warns | Satisfied | "session-start warns on a longer, real entry" |
| Warning is one object, `systemMessage` leads with ESC `[0m` and names the copy, `hookEventName = SessionStart`, `additionalContext` names the copy | Satisfied (after fix) | `assert_session_warns` |
| Unresolved entry compared literally, trailing slash stripped | Not pinned in 1.3/3 | Observable only with the copy absent, which the orchestrator ruled out (see above) |

## Positive Observations

- Each fixture existence is asserted (`[[ -d ... ]] || fail`), so a sync change
  that dropped `skills/` or the other copy would show up as a fixture failure,
  not a vacuous warning.
- The block comment names what each entry rules out, and each mutation above
  confirms the claim.

## Recommendations

- The 1.3/2 warn scenarios (`plugin<LF>`, relative entry) assert only
  `hookEventName`. Switching them to `assert_session_warns` would pin the full
  warning. They are outside this slice's scope, so they were left unchanged.

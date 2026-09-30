# Review: Item 1.2 slice 6 tests (leaf symlink), RED phase

**Scope**: `tests/dogfood-test.sh`: the three new pre-tool scenarios and
`assert_denied_source`, plus `reports/item-1-2-s6-red.md`. `toolkit/dogfood.sh`
was read and not changed. **Date**: 2026-09-30 **Mode**: review + fix

## Summary

All three tests are red for the reason the slice names. Two fixes were applied.
The chain test now uses relative links, so it also catches a hop that is
resolved against the cwd instead of the link's own directory. The new helper had
copied `assert_denied`; it now holds the shared checks, and `assert_denied`
calls it and adds only the reason check. The helper therefore gains the
one-object and `systemMessage` checks it had dropped.

**Overall Assessment**: Ready

## Mechanical check

The suite ran in the foreground against the unchanged SUT. It reported 13
failures, all in the three new tests. Every pre-existing test passed. `bash -n`
and `shellcheck` are clean.

- `pre-tool follows a symlink at the leaf into the copy`: 6 assertion failures.
  Stdout is `''`, so the one-object, hookEventName, permissionDecision,
  additionalContext and both systemMessage checks fail. Exit code and stderr
  pass.
- `pre-tool follows a chain of leaf symlinks into the copy`: the same 6
  failures.
- `pre-tool allows a leaf symlink out of the copy`: 1 failure. The stdout
  assertion fails because the current SUT denies the path, with source
  `<root>/skills/z.md`. Exit code and stderr pass.

None of the tests PASSED and none ERRORED. Each one reds on an assertion.

## Candidate implementations (scratch copies, not the tree)

The suite was run against patched copies of `tests/` and `toolkit/` in a temp
directory. The repo's SUT was not touched.

| Candidate | Result |
|---|---|
| Planned: `readlink -f` when the leaf is an existing symlink | whole suite green |
| One-hop `readlink` | chain test red (6), all else green |
| `readlink` loop resolved against the cwd | chain test red (6), all else green |
| Deny nothing | allow test passes; both deny tests red (by construction) |

## Issues Found

### Critical Issues

None.

### Major Issues

1. **The chain test did not catch a readlink loop that resolves relative targets
   against the cwd**
   - Location: `tests/dogfood-test.sh`, chain scenario.
   - Problem: both links had absolute targets. A
     `while [[ -L ]]; do readlink; done` loop reaches the copy file with
     absolute targets. It misresolves relative ones, because it resolves them
     against the hook's cwd rather than the link's directory. Relative links are
     the common form inside a repo.
   - Fix: `x.md -> ../dist/plugin/skills/demo/SKILL.md` and `y.md -> x.md`. The
     chain still separates one hop from full resolution: one hop stops at
     `x.md`. It now also reds the unanchored loop, which sees the target `x.md`
     and checks it against the cwd, `$sandbox`. The single-link test keeps its
     absolute target, which carries the space in `my consumer`. The comment
     above the scenarios says why the links are relative.
   - **Status**: FIXED. Checked against candidates: one-hop and unanchored red,
     planned green.

### Minor Issues

1. **`assert_denied_source` duplicated `assert_denied` and dropped three of its
   checks**
   - Location: `tests/dogfood-test.sh`, deny helpers.
   - Problem: the new helper repeated `assert_denied` without the reason check,
     and also without the one-object slurp and the two `systemMessage` checks.
     Only the reason check depends on the payload being spelled in the copy. The
     other three hold for any deny. Dropping them let a leaf-resolution change
     that leaked output (such as a stray `readlink` print) or broke the object
     pass through the new tests.
   - Fix: `assert_denied_source` now holds every check except the reason check.
     `assert_denied` calls it and then adds the reason check. The pre-existing
     callers keep the same set of assertions. Only the order in which a failure
     message prints changes.
   - **Status**: FIXED.

## Wrong-reason hunting (no finding)

- **The state that fails each test.** The two deny tests fail when the guard
  compares the unresolved leaf. The allow test fails when it does too, because
  the unresolved `z.md` is spelled in the copy. Removing the fix reds all three.
- **Could the allow test pass without the fix?** It is a negative, and an
  implementation that denies nothing passes it. That implementation reds both
  deny tests, which differ only in which way the link points. The pre-existing
  `denies an Edit into the copy` test covers a plain copy file.
- **Could the source substring be satisfied by another string?**
  `<root>/skills/demo/SKILL.md` is not a substring of the payload
  (`<root>/skills/x.md` / `y.md`). It is not a substring of the unresolved
  source either, nor of `<root>/dist/plugin/skills/demo/SKILL.md`, because
  `dist/plugin/` breaks the contiguity. Only the resolved source matches.
- **`<root>` spelling.** `root="$(cd "$consumer" && pwd -P)"`, over a sandbox
  that `make_consumer` has already made physical. The absolute link targets use
  that spelling.
- **Isolation.** Each scenario calls `make_consumer`, which creates a fresh
  sandbox, and reassigns `root`. `label` is either passed explicitly or
  reassigned. The links live inside the per-scenario sandbox.
- **Whitespace.** Every path holding `my consumer` is quoted, both in the
  `ln -s` arguments and in the payload. The payload is built with `jq --arg`,
  and the assertion `$p` is bound with `--arg`. The relative targets hold no
  spaces.
- **Fixture reachability.** A leaf symlink in the source tree or in the copy is
  an ordinary state an agent or a user can create. Nothing here is unreachable.

## Fixes Applied

- `tests/dogfood-test.sh`, deny helpers: `assert_denied` now calls
  `assert_denied_source` and adds the reason check. `assert_denied_source` gains
  the one-object and `systemMessage` checks, and its comment was reworded.
- `tests/dogfood-test.sh`, chain scenario: both links are now relative
  (`../dist/plugin/skills/demo/SKILL.md`, `x.md`). The scenario comment explains
  why.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D6 copy guard, physical comparison extended to the leaf | Tests red as specified | The three scenarios; the planned implementation turns them green in a scratch copy |

## Positive Observations

- The chain test isolates one-hop resolution from full resolution. The RED
  report's decoded deny payload for the allow test shows the right reason for
  the red.
- The allow test's link lives inside the copy and points out of it. This is the
  exact mirror of the deny case, so neither direction is covered by accident.

## Recommendations

- GREEN: the residual for a dangling leaf link (unfollowed) goes in the
  `pre_tool` comment, replacing the sentence "A symlink at the leaf is not
  followed", which becomes false.

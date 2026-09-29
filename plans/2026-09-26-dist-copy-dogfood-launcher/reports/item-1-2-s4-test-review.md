# Review: Item 1.2/4 test review — physical spelling

**Scope**: the two new tests in `tests/dogfood-test.sh`
(`pre-tool denies a copy path through a symlinked repo`,
`pre-tool invoked through the symlink denies a physical path`) and
`reports/item-1-2-s4-red.md`. SUT `toolkit/dogfood.sh` read and temporarily
mutated for probes only; it ends byte-identical to HEAD. **Date**: 2026-09-30
**Mode**: review + fix (TDD test review)

## Summary

Both tests do what the RED report says. Test 1 reds on its assertions against
the committed SUT, and test 2 reds under an independent mutation of `root_dir`.
One gap turned up: a plausible GREEN that ignores the interface's
nearest-existing-ancestor rule also passes test 1 and the rest of the suite. It
splits the payload text at `/dist/plugin/` and resolves only the part before it.
A third test, on a symlink to the copy itself, now closes the gap. Test 1 also
gets a guard for its `new/`-is-absent precondition.

**Overall Assessment**: Ready

## Mechanical check

Run against the committed SUT (`bash tests/dogfood-test.sh`, foreground). The
suite ends `4 failure(s)`:

| Test | Result |
|------|--------|
| `pre-tool denies a copy path through a symlinked repo` | FAILED on assertions: `permissionDecision` and `additionalContext names the physical source path`, both over stdout `''`. Exit code, stderr and the new `new/ is not in the copy` guard pass. No error. |
| `pre-tool denies a copy path through a symlink to the copy` (added here) | FAILED on the same two assertions over stdout `''`. Exit code and stderr pass. No error. |
| `pre-tool invoked through the symlink denies a physical path` | PASSED. This is expected: the committed `root_dir` already uses `pwd -P`. Its discrimination is shown by the mutation below. |

No other test changed state.

## Mutation proof for test 2 (independent of the RED report's)

The RED report changed both `pwd -P` to `pwd`. This review used a different
mutation: an exact replacement, occurring once, of the second `root_dir` step,
turning it into a textual root.

- `        (cd "$here/.." && pwd -P)` became
  `        dirname "$(dirname "${BASH_SOURCE[0]}")"`
- Landed: `grep -cF 'dirname "$(dirname' toolkit/dogfood.sh` returned 1.
- Result: all 7 of test 2's `assert_denied` jq assertions failed over stdout
  `''`. For example:

  ```text
  FAIL: pre-tool invoked through the symlink denies a physical path: permissionDecision: .hookSpecificOutput.permissionDecision == "deny" is not true over stdout ''
  ```

  No test invoked through the physical path changed. The suite showed 9 failures
  (7 plus test 1's 2).
- Restored by the inverse replacement. `grep -cF 'dirname "$(dirname'` returned
  0, and `git diff --quiet toolkit/dogfood.sh` was clean.

## Candidate-GREEN probes for test 1

Each probe was a line inserted after the `path="$(jq …)"` assignment in
`pre_tool` and tagged `# PROBE-x`. Each was removed by inverse replacement.
After the last one, `grep -c PROBE-` returned 0 and
`git diff --quiet toolkit/dogfood.sh` was clean.

| Probe | Implementation | Outcome |
|-------|----------------|---------|
| A | resolve only the direct parent (`${path%/*}`) when it is a directory | Test 1 stays red. The absent `new/` does force the ancestor walk. |
| B | rewrite whatever precedes `/dist/plugin/` to `$root` (the "string-replace" cheat) | Test 1 passes. Slice 1.2/3's `pre-tool allows a path outside the repo prints nothing on stdout` fails, so the suite rules it out. |
| C | nearest-existing-ancestor walk, `pwd -P` on the ancestor, tail re-appended | Whole suite green, including the added test. Test 1 is satisfiable. |
| D | split the text at `/dist/plugin/`, resolve the prefix with `pwd -P` | Before the fix: whole suite green (the gap). After the fix: the added test reds on its two assertions. |

## Wrong-reason hunt

- **Is `new/` really absent?** Yes: sync copies `.claude-plugin/`, `.gitignore`,
  `plugin-dev/` and `skills/`. Probe A shows that absence is what forces the
  walk. Before this review nothing asserted the absence (see Minor 1).
- **Is `<root>` the `pwd -P` spelling?** Yes:
  `root="$(cd "$consumer" && pwd -P)"`. `make_consumer` already makes `$sandbox`
  physical, so the two spellings coincide here. The expected `$root/new/file.md`
  still differs from the link spelling `$sandbox/link/new/file.md`, so
  `contains($p)` cannot be satisfied by the link form.
- **Could additionalContext pass by naming the copy path?**
  `$root/dist/plugin/new/file.md` does not contain `$root/new/file.md`, so
  echoing the denied path cannot satisfy the assertion. Only the mapped source
  can.
- **Does a string-replace of `$sandbox/link` pass?** The SUT cannot know the
  link name. The general form (probe B) passes test 1 but is caught by 1.2/3.
- **Can test 2 pass with a logical root once path resolution exists?** No. With
  probe C in place, a logical `$root` of `$sandbox/link` still fails to prefix
  the physical payload. Test 2 keeps pinning `root_dir`'s `pwd -P` after GREEN.
- **Global state leak:** test 2 sets `consumer="$sandbox/link"`. The next block
  calls `make_consumer`, which resets it. No leak.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Test 1 does not pin the nearest-existing-ancestor comparison**
   - Location: `tests/dogfood-test.sh`, the
     `pre-tool denies a copy path through a symlinked repo` block
   - Problem: the payload spells `/dist/plugin/` literally, so a GREEN that
     splits the text there and resolves only the prefix (probe D) passes test 1
     and the whole suite. The Item 1.2 interface requires "compared physically
     (nearest existing ancestor through `pwd -P`)". Probe D contradicts that and
     would allow an edit through any symlink into the copy whose spelling lacks
     `dist/plugin`.
   - Fix: add `pre-tool denies a copy path through a symlink to the copy`.
     `$sandbox/copy-link` points to `$consumer/dist/plugin`, and the payload is
     `$sandbox/copy-link/new/file.md`. The test expects exit 0, empty stderr, a
     `deny`, and `additionalContext` containing `$root/new/file.md`. It uses the
     same assertion shape as test 1. A comment names the implementation it rules
     out. It reds against the committed SUT and against probe D, and goes green
     under probe C.
   - **Status**: FIXED

### Minor Issues

1. **Test 1's "`new/` does not exist" precondition was unasserted**
   - Location: `tests/dogfood-test.sh`, test 1
   - Note: the slice's discrimination against parent-only resolution (probe A)
     depends on `new/` being absent. The comment stated this but nothing checked
     it, so a fixture change that created `dist/plugin/new/` would silently turn
     the test into a parent-only check.
   - Fix:
     `assert_absent "$consumer/dist/plugin/new" "$label: new/ is not in the copy"`
     before the run. `label=` moved above it.
   - **Status**: FIXED

## Fixes Applied

- `tests/dogfood-test.sh`, test 1: `label=` moved before `run_pre_tool`;
  `assert_absent` guard on `dist/plugin/new` added.
- `tests/dogfood-test.sh`: new block
  `pre-tool denies a copy path through a symlink to the copy`, between test 1
  and test 2.
- `shellcheck tests/dogfood-test.sh` clean. `toolkit/dogfood.sh` unchanged
  (`git diff --quiet`).

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| 1.2/4 test 1: link → fixture, payload `$sandbox/link/dist/plugin/new/file.md`, `new/` absent, deny, `additionalContext` names physical `<root>/new/file.md` | Satisfied | test 1 block; red on its assertions; probes A and C |
| 1.2/4 test 2: script run through the link, payload spelled physically, deny | Satisfied | test 2 block; independent mutation reds all 7 assertions |
| Interface: compared physically, nearest existing ancestor through `pwd -P` | Satisfied after fix | added copy-link test; probe D red, probe C green |

## Positive Observations

- Test 2 reuses `assert_denied` in full, so an allow fails seven independent
  field checks rather than one.
- Test 1's expected value is the mapped source, not the denied path, so echoing
  the payload back cannot satisfy it.
- The RED report's mutation note, that removing only one `pwd -P` still
  canonicalises, is correct and was re-derived here.

## Recommendations

- GREEN for 1.2/4 must turn all three physical-spelling tests green. The added
  test is red for the same reason as test 1, and it is the one that stops a
  prefix-split implementation.

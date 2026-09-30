# Review: Item 1.3/2 test review — `session-start` entry matching

**Scope**: the three new scenarios in tests/dogfood-test.sh (one entry of
several, trailing slash, symlinked spelling) and item-1-3-s2-red.md. The SUT,
toolkit/dogfood.sh, was read and mutated in place for probes only, and was
restored each time. All uncommitted. **Date**: 2026-09-30 **Mode**: review + fix

## Summary

All three tests are red on their own stdout assertion against the committed SUT,
with no harness error. One wrong-reason gap was fixed. The several-entries test
put the copy last, so a GREEN that compares only the last entry (or a suffix of
the whole value) passed all three tests. Slice 1.3/3's warn cases cannot catch
that shape. The copy now sits between two entries. The block comment was also
corrected on two points.

**Overall Assessment**: Ready

## Mechanical check

The suite was run in the foreground before and after the fix. Both runs gave 3
failures, all `FAIL:` assertion lines, with no harness error:

- `session-start is silent on one entry of several prints nothing on stdout`
- `session-start is silent on a trailing slash prints nothing on stdout`
- `session-start is silent on a symlinked spelling prints nothing on stdout`

Each one got the full warning object. In each test the exit-code and stderr
assertions pass, which matches the RED report. `shellcheck` is clean.
`git status toolkit/` was clean after every mutation was restored.

## Mutation probes

Each probe replaced the SUT's one-line comparison in place. A script asserted
that its anchor occurred exactly once, and the inverse replacement restored it.
These are the results after the fix, over the full suite:

| GREEN shape | 1.3/2 result | Caught by |
|---|---|---|
| sketch: split on `:`, resolve each entry with `cd && pwd -P`, else strip `/` and compare literally | all green (whole suite green) | — (correct) |
| last entry only, resolved | **red** (several) | 1.3/2 (red only after the fix) |
| resolve root only, compare entries literally with `/` stripped | **red** (symlink) | 1.3/2 |
| split on whitespace (`${VAR//:/ }`) | **red** (1.3/1 silent, several, trailing slash; warn test too) | 1.3/1–2, via the space in `my consumer` |
| some entry ends in `/dist/plugin` | green | 1.3/3 `<other>/dist/plugin` |
| resolved entry contains the copy (substring) | green | 1.3/3 `/x<root>/dist/plugin` and `<root>/dist/plugin/skills` |
| resolved entry starts with the copy (prefix) | green | 1.3/3 `<root>/dist/plugin/skills` |
| variable non-empty | green | 1.3/3 (any case) |
| some entry is an existing directory | green | 1.3/3 `<other>/dist/plugin` and `<root>/dist/plugin/skills` |

Before the fix, the "last entry only" row was green on all three tests.

## Wrong-reason analysis

- **Pre-existing `$sandbox/link`.** Not an issue. `make_consumer` takes a fresh
  `mktemp -d` sandbox for every scenario, so `ln -s "$root" "$sandbox/link"`
  always creates a new link. It never creates a link inside an existing target.
- **Symlink case needs entry resolution.** Yes. `root_dir` is already physical.
  The script runs at `$sandbox/my consumer/plugin-dev/dogfood.sh`, which is the
  physical spelling, and the variable goes through the link. A GREEN that
  resolves only the root reds (row 3), and so does one using logical `pwd` on
  the entry. The link's target exists because `run_dogfood sync` created
  `dist/plugin`.
- **Trailing slash vs prefix matching.** The trailing-slash case cannot tell
  exact matching from prefix matching (row 7). That split belongs to 1.3/3's
  `<root>/dist/plugin/skills`. Taken alone, it pins "not raw string equality".
- **Several entries and `:` splitting.** Before the fix, a last-entry or suffix
  GREEN passed, and a loop whose last iteration overwrites the verdict would
  have passed too. None of 1.3/3's cases produce a false silence under that
  shape, so none of them catch it. With `/x/other:<root>/dist/plugin:/y/other`,
  neither end nor a suffix can stand in for splitting. Whitespace splitting is
  already caught because the root contains a space.
- **Non-resolving neighbours and stderr.** `/x/other` and `/y/other` do not
  exist, and the stderr assertion requires silence. A GREEN therefore has to
  guard the `cd` (`[[ -d ]]`, say) or redirect it. The guard is the form
  `no-stderr-suppression` prefers. Under `set -e`, an unguarded
  `r="$(cd "$e" && pwd -P)"` would also stop the script non-zero on the first
  entry and fail the exit-code assertion. Both points are intended pressure on
  GREEN.
- **`realpath` / `readlink -f`.** A GREEN using them would pass on Linux. The
  tests push toward them no more than toward `pwd -P`, since any physical
  resolution matches. The old comment said "only resolving the entry with pwd -P
  matches", which was overstated. It now says "resolved to its physical
  spelling". The portability choice is GREEN's to make, per the outline's
  decision 7.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Several-entries test passes a last-entry-only GREEN**
   - Location: tests/dogfood-test.sh,
     `session-start matches the copy among several entries`
   - Problem: the copy was the final entry, so `${VAR##*:}`, a suffix match on
     the whole value, or a last-iteration-wins loop all went silent. Probed: the
     last-entry mutation passed all three tests. 1.3/3 cannot catch it, because
     all its cases warn.
   - Fix: the variable is now `/x/other:$root/dist/plugin:/y/other`. The
     last-entry mutation now reds this test on its stdout assertion.
   - **Status**: FIXED

### Minor Issues

1. **Block comment misstated the fixture and the mechanism**
   - Location: tests/dogfood-test.sh, the comment above the three scenarios
   - Note: it said the variable was the only difference from the warn test, but
     the symlink test also adds a link. It also said only `pwd -P` matches, when
     any physical resolution does.
   - Fix: reworded both points, and added why the copy sits between two entries.
   - **Status**: FIXED

## Fixes Applied

- tests/dogfood-test.sh: several-entries variable gains a trailing `:/y/other`,
  so the copy is a middle entry.
- tests/dogfood-test.sh: block comment reworded as described under Minor 1.

## Notes for later slices

- **1.3/3 catches** the tail-match, substring, prefix, non-empty and
  any-existing-directory GREENs, as mapped in the table above.
- **The literal-compare rule is unpinned by 1.3/2 and 1.3/3 as specified.** "An
  entry that does not resolve is compared literally, trailing slash stripped"
  only shows as a *silent* result: a non-resolving entry that names the copy,
  which means `dist/plugin` is absent. Every 1.3/3 non-resolving case warns, so
  a GREEN that warns on every non-resolving entry passes both slices. Pinning
  the rule would take a silent case run before any sync (`<root>/dist/plugin/`
  with no `dist/`). The shim always syncs first, so the orchestrator can decide
  whether the rule warrants that test or should drop from the Interfaces.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| Silent for one entry of several | Satisfied | red on stdout; pins `:` splitting (last-entry mutation reds) |
| Silent for a trailing slash | Satisfied | red on stdout |
| Silent for a symlinked spelling | Satisfied | red on stdout; root-only mutation reds |
| exit 0, stdin not read | Satisfied / Partial | exit code asserted; stdin unpinned (as in 1.3/1) |

## Positive Observations

- Each scenario builds its own fixture and differs from the warn test only in
  the variable and, for the last, the link. The warn test stays the positive for
  all three.
- The space in the root makes whitespace splitting fail at once.
- The symlink test invokes the script at the physical path, so resolving the
  entry is load-bearing. This follows up the 1.3/1 review's note.

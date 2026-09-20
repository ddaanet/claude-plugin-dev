# Review: Item 1.1 slice 2 — RED-phase test review

**Scope**: `tests/release-test.sh` — the new
`=== pipefail-stripped release_tags failure publishes nothing ===` scenario and
the `make_virgin` fixture change inside the
`=== the origin probes fail closed with pipefail stripped ===` harness — plus
`reports/item-1-1-s2-red.md`. **Date**: 2026-09-20 **Mode**: review + fix

## Summary

The test is sound and its red evidence is real: the item's named mutation was
re-applied independently and the scenario's assertions failed on value
mismatches, not errors. The executor's fixture claim (that slice 1's
already-released fixture would pass vacuously) is correct and is confirmed by
the mutated run's own output. Two issues were found and fixed: line-number
citations in the scenario comment, which the repo's citation convention forbids,
and a bare-negative assertion set with nothing pinning that the run reached the
read under test.

**Overall Assessment**: Ready

## Mechanical first check (adapted red form) — my own re-runs

### 1. Baseline green on the current, unmutated tree

```
cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
```

```
=== the origin probes fail closed with pipefail stripped ===
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===

all release scenarios passed
```

### 2. Under the item's named mutation (before my fixes)

`toolkit/release.sh` backed up to `$TMPDIR/s2rev/release.sh.bak`, then
`release_tags`'s body replaced in place with the pre-slice-1 pipe
(`git tag --list 'v*' --sort=-v:refname | semver_tags`), comments untouched.
`git diff --stat` confirmed the mutation touched only that file
(`1 insertion(+), 3 deletions(-)`).

```
cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
```

```
=== pipefail-stripped release_tags failure publishes nothing ===
FAIL: pipefail-stripped release_tags failure publishes nothing local tag set unchanged: expected '', got 'v1.2.3'
FAIL: pipefail-stripped release_tags failure publishes nothing origin tag set unchanged: expected '', got 'v1.2.3'
FAIL: pipefail-stripped release_tags failure publishes nothing gh log empty: expected '', got 'release view v1.2.3
release create v1.2.3 --title Release 1.2.3 --generate-notes'

5 failure(s)
```

All three of slice 2's assertions FAILED on value mismatches (`expected ''`),
none PASSED, none ERRORed. This reproduces `item-1-1-s2-red.md` verbatim,
including the two slice-1 `FAIL:` lines the same run prints.

### 3. Restore, byte-for-byte

```
cd /Users/david/code/claude-plugin-dev && cp "$TMPDIR/s2rev/release.sh.bak" toolkit/release.sh && git diff --quiet -- toolkit/release.sh && echo "RESTORED: git diff --quiet clean (exit 0)"
```

```
RESTORED: git diff --quiet clean (exit 0)
```

`git status --short` afterwards shows `toolkit/` untouched; the only tracked
modification in scope is ` M tests/release-test.sh`.

## Verification of the executor's fixture claim

Claim: `new_sandbox "1.2.3"` alone is vacuous here, because origin's real
`v1.2.3` makes `origin_release_tags` (which the `git` stub does not touch — it
uses `git ls-remote`) trip the lost-tags refusal under both fixed and mutated
code.

**Confirmed, two ways.**

Structurally: `release_preflight`, on an empty local list, captures
`origin_release_tags` and — when it is non-empty — prints the `git fetch --tags`
hint and `die`s with "local release tags are missing — refusing to guess
whether ... was published". That `die` is above the `check-version.sh` call, the
`first_release=1` branch and every side effect, so nothing is tagged, pushed or
published on that path regardless of `release_tags`'s status handling.

Empirically: slice 1's scenario *is* that fixture, and the mutated run above
prints its output in full — the run ends at
`error: local release tags are missing`, having reached no publishing step. The
three "publishes nothing" assertions would therefore have held on that fixture
under the mutation. The executor's report is accurate and its rejection of the
first fixture was correct.

`make_virgin "1.2.3"` genuinely produces the state claimed: it deletes `v1.2.3`
locally *and* pushes the deletion to the bare origin
(`git push -q origin :refs/tags/v1.2.3`), leaving no `v*` tag on either side
with the manifest at `1.2.3`.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Line-number citations in the scenario comment**
   - Location: `tests/release-test.sh`, the slice-2 scenario comment
   - Problem: the comment cited "`refusal at :392-403`" and
     "`reaches first_release=1 at :481-482`". The repository's citation
     convention is that a comment cites the enclosing symbol plus a short quoted
     fragment, never a line number — and these had already rotted:
     `first_release=1` is at line 484, not 481-482.
   - Fix: replaced both with `release_preflight` plus a quoted fragment of the
     branch each names.
   - **Status**: FIXED

2. **Bare-negative assertion set: nothing pins that the run reached the read
   under test**
   - Location: `tests/release-test.sh`, the slice-2 scenario's three assertions
   - Problem: all three assertions are absences (local tag set unchanged, origin
     tag set unchanged, `$GH_LOG` empty), and all three snapshots are empty by
     fixture construction. They hold for *any* early failure — a broken fixture,
     a `sed` that mangled the stripped copy, a stub `git` that failed to `exec`,
     a die in `common_preflight` — none of which exercise `release_tags`'s
     status handling. The test detects today's mutation, but as a standing
     regression detector its evidence rests on the run actually reaching
     `release_preflight`'s tag read, which nothing asserted. This is the "bare
     negative" shape: pair it with a positive over the same fixture.
   - Fix: added two assertions before the three absences — `rc` is `1`, and the
     output names `release_preflight`'s own die, "could not list this plugin's
     release tags". Not redundant with slice 1's identical `assert_contains`: on
     the virgin fixture the lost-tags branch is not available, so this pins that
     the refusal came from `release_tags`'s status rather than from the hint
     ladder. Both also red under the mutation (see re-run below), so they
     strengthen rather than dilute the evidence. A three-line comment records
     why they are there.
   - **Status**: FIXED

### Minor Issues

1. **The stub-and-stripped-copy block is duplicated verbatim from slice 1**
   - Location: `tests/release-test.sh`, the slice-2 scenario's setup (the
     `sed`/`grep -qx` stripped copy plus the 13-line `git` wrapper heredoc)
   - Note: each scenario needs its own copy because `new_sandbox` creates a
     fresh sandbox, but the two blocks are byte-identical apart from the
     variable reuse and would be better as a harness helper alongside
     `make_virgin` and `lose_tag`. Extracting one requires rewriting slice 1's
     scenario, which is OUT of this review's scope.
   - **Status**: DEFERRED — slice 1's scenario is out of scope.
     `REFACTOR-NEEDED: tests/release-test.sh — the pipefail-stripped-copy + failing-`git
     tag
     --list` wrapper setup is duplicated across the two slice scenarios; extract a harness helper.`

## Other checks, all clean

- **Tag-set assertion is a set comparison, not a named refutation.** It compares
  `"$(git -C "$plugin" tag --list | sort)"` against a snapshot captured before
  the run, newline-delimited and sorted, inside quoted command substitution — no
  splitting on whitespace, and no tag named in the assertion. This is what the
  runbook asked for. (Git refnames cannot contain whitespace, so `sort` on the
  listing is safe regardless.)
- **Origin tag-set assertion is genuinely reached** and reads the bare origin
  (`"$plugin-origin.git"`, matching `git_init`'s naming), not the clone.
- **`$GH_LOG` is not stale.** The scenario opens with `new_sandbox "1.2.3"`,
  which sets `GH_LOG="$sandbox/gh.log"` on a fresh `mktemp -d` and truncates it
  (`: > "$GH_LOG"`). No sandbox is shared with an earlier `run`. Its emptiness
  is real: the mutated run's
  `expected '', got 'release view v1.2.3 / release create v1.2.3 …'` proves the
  assertion discriminates.
- **No disturbance to other scenarios.** The new block is the last before the
  failure tally. It reassigns `nopipefail_tags`, `git_wrapper_dir`, `real_git`,
  `saved_path`, `sandbox` and `plugin`, all after their final use by slice 1;
  `PATH` is saved and restored around the run. Full-suite green confirms.
- **Whitespace safety.** Every command substitution and variable reference in
  the added shell is quoted; the only interpolation into the stub body is
  `$real_git` inside a quoted `exec`, the hazard slice 1's comment already
  documents.
- **No lasting change to `toolkit/release.sh`.** Verified after every mutation
  cycle.
- `bash -n` and `shellcheck tests/release-test.sh` are clean after the fixes.

## Fixes Applied

- `tests/release-test.sh`, slice-2 scenario comment — replaced the two
  line-number citations with `release_preflight` plus quoted fragments of the
  branches they name; added a short paragraph stating why the run's exit code
  and die message are asserted alongside the three absences.
- `tests/release-test.sh`, slice-2 scenario assertions — added
  `assert_eq "$rc" "1" "… exit code"` and
  `assert_contains "$out" "could not list this plugin's release tags" "… refused at the tag read"`
  immediately after the `PATH` restore, before the three absence assertions.

## Post-fix evidence

### Green on the current tree

```
cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
```

```
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===

all release scenarios passed
```

### Red under the mutation (all five assertions)

```
=== pipefail-stripped release_tags failure publishes nothing ===
FAIL: pipefail-stripped release_tags failure publishes nothing exit code: expected '1', got '0'
FAIL: pipefail-stripped release_tags failure publishes nothing refused at the tag read: output did not contain 'could not list this plugin's release tags'
  --- output ---
git: fatal: stub git failing tag --list
check-version: in sync (1.2.3)
first release: publishing the manifest version 1.2.3 as-is (no bump)
tag: v1.2.3 created locally (manifest already at 1.2.3)
branch main: already pushed
To /tmp/claude-1000/tmp.TgKJYOUO5V/plugin-origin.git
 * [new tag]         v1.2.3 -> v1.2.3
github tag v1.2.3: pushed
github release v1.2.3: created
marketplace: already at 1.2.3
Release v1.2.3 complete
  --------------
FAIL: pipefail-stripped release_tags failure publishes nothing local tag set unchanged: expected '', got 'v1.2.3'
FAIL: pipefail-stripped release_tags failure publishes nothing origin tag set unchanged: expected '', got 'v1.2.3'
FAIL: pipefail-stripped release_tags failure publishes nothing gh log empty: expected '', got 'release view v1.2.3
release create v1.2.3 --title Release 1.2.3 --generate-notes'

7 failure(s)
```

The captured output is the hazard itself, printed in full: the mutated
`release_tags` swallowed the stubbed failure, `first_release=1` fired, and the
script tagged, pushed and published `v1.2.3` on a plugin whose release history
it could not read.

### Restore confirmation (final)

```
cd /Users/david/code/claude-plugin-dev && cp "$TMPDIR/s2rev/release.sh.bak" toolkit/release.sh && git diff --quiet -- toolkit/release.sh && echo "RESTORED: git diff --quiet clean (exit 0)" && bash tests/release-test.sh 2>&1 | tail -4
```

```
RESTORED: git diff --quiet clean (exit 0)
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===

all release scenarios passed
```

`git status --short` shows ` M tests/release-test.sh` as the only in-scope
tracked change; `toolkit/release.sh` is byte-identical to `HEAD`. Nothing was
committed.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| M2 — with `pipefail` stripped and `git tag --list` failing, the release publishes nothing | Satisfied | The scenario asserts the local tag set, the origin tag set and `$GH_LOG` are all unchanged, and (after the fix) that the run refused at `release_tags`'s own status. All five red under the named mutation. |

## Positive Observations

- The executor identified and rejected a vacuous fixture rather than shipping
  the spurious red it produced, and documented the rejection in the RED report —
  the exact failure mode this review exists to catch, caught upstream.
- The tag-set assertions use before-snapshots rather than naming `v1.2.3`,
  following the runbook's instruction precisely; naming the tag would have let a
  mutation that published a *different* version slip through.
- The no-bump-argument choice is correct and its reason is recorded: an explicit
  bump is refused on a first release before `bump_commit_tag`, which would have
  refused for a reason unrelated to the defect.
- The stub matches `git tag --list` positionally and delegates everything else,
  keeping `common_preflight`'s own git calls working — a narrow stub rather than
  a blunt one.

## Recommendations

Fold the stripped-copy-plus-failing-`git`-wrapper setup into a harness helper
when slice 1's scenario is next in scope (see the DEFERRED minor issue).

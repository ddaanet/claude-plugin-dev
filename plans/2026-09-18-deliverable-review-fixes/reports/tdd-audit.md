# TDD Process Review: 2026-09-18-deliverable-review-fixes (Phase 1)

**Date:** 2026-09-20 **Runbook:**
`plans/2026-09-18-deliverable-review-fixes/runbook.md` **Commits analyzed:**
`af72c2a..73d46da` — slice commits `b68cede`, `4d9bc80`, `45891f8`, `d0c13b9`,
`a69c97f`, `07b7ae9`, `6a77bea`; phase checkpoint `73d46da`

Sources: the seventeen committed Phase 1 slice reports under
`plans/2026-09-18-deliverable-review-fixes/reports/`, `phase-1-corrector.md`,
and `git show`/`git diff` on the commits those reports name. No subagent
transcript was read. Phases 2–4 were examined only to confirm no later commit
disturbed a Phase 1 test.

## Executive Summary

Phase 1's six slices are, on the evidence, unusually disciplined: every slice
carries a RED report whose failures are assertion mismatches rather than errors,
every reviewed test id appears verbatim in its slice commit under the same name
and file, no GREEN dispatch edited a test file, no commit carries a mutation,
and every mutation was restored byte-for-byte with `git diff --quiet` shown.
Commit shape is clean — exactly one marker-bearing commit per slice, plus the
one expected code-review-fixes commit for Item 1.1/1. The three skipped code
reviews are **not** the three the dispatch brief describes: the three slices
with genuinely empty implementation scope are 1.1/2, 1.2/1 and 1.3/2, but the
missing fourth report is **Item 1.3/1**, whose commit `07b7ae9` changed 29 lines
of `scripts/self-release.sh`. That is the one substantive process violation, and
it has a measurable cost: the phase corrector then found two Major defects in
exactly that function, including a fail-open status conflation of the same class
Item 1.1 exists to close.

## Per-Slice Compliance

| Item/slice | RED evidence | Test review | One slice commit | Tests unmodified | Issues |
|------------|--------------|-------------|------------------|------------------|--------|
| 1.1/1 | Genuine fail-before-fix; 2 assertion FAILs, no ERROR (`item-1-1-s1-red.md`) | Ready; 1 minor comment fix, no assertion touched | `b68cede` (+ `4d9bc80` code-review fixes, accounted for) | 3 ids present in `b68cede` | `memory` gitlink swept in by hook (minor) |
| 1.1/2 | Named mutation (restore the pipe); 3→5 assertion FAILs on values | Ready; 2 Major fixed (line citations, bare-negative set) | `45891f8` (tests only) | 5 ids present, incl. both review-added | Code review skipped — scope genuinely empty |
| 1.2/1 | Declared control, no red by design; liveness proved by a temporary needle mutation | Ready; 1 Major fixed (stub was not load-bearing — test was vacuous) | `d0c13b9` (tests only) | 5 ids + `lose_tag`/origin-tag deletion present | Code review skipped — scope genuinely empty |
| 1.2/2 | Genuine fail-before-fix; 2 assertion FAILs, branch-2 output shown | Ready; 2 minor fixes to the size guard | `a69c97f` | 6 ids present incl. post-filter size guard | none |
| 1.3/1 | Genuine fail-before-fix; 3 assertion FAILs (`item-1-3-s1-red.md`) | Ready; 1 minor comment fix | `07b7ae9` | 3 ids present | **Code review missing on a non-empty scope** |
| 1.3/2 | Named mutation (revert to `git describe`); 2 assertion FAILs, full publish shown | Ready; 1 Major fixed (reachability split unpinned) | `6a77bea` (tests only) | 2 ids + 3 review-added fixture guards present | Code review skipped — scope genuinely empty |

## Violations

### Critical

1. **Item 1.3/1 — GREEN commit `07b7ae9` received no code review.** `reports/`
   holds `item-1-3-s1-red.md`, `-test-review.md` and `-green.md` but no
   `item-1-3-s1-code-review.md`. The commit is not empty-scope:
   `git show --stat 07b7ae9` is `scripts/self-release.sh | 29 +++++-----`,
   `tests/self-release-test.sh | 19 ++++-`. It is the only Phase 1 slice that
   changed a production file without a slice-level code review.

   Cost, measured rather than assumed — `phase-1-corrector.md` found two Major
   issues in precisely the region `07b7ae9` introduced:
   - the landed comment claims "the `dist-v*` lineage sorts as text after "v"
     and is dropped there, not by the glob", which is the opposite of what
     `git tag --list 'v*'` does and contradicts the runbook's own Item 1.3 note
     (corrector Major 1);
   - `latest_tag=$(grep -m1 -E … <<< "$tags") || latest_tag=""` folds grep's
     status 2 into "no release tag yet", skipping the drift guard on a real
     filter error — the same fail-open class Item 1.1 exists to close, one stage
     down the same function (corrector Major 2).

   Both survived to the phase boundary because the per-slice gate that exists to
   catch them was not run. The `item-1-3-s1-green.md` report even restates the
   false mechanism in its own words ("noting the `dist-v*` lineage is dropped by
   the filter, not by the glob"), so a reviewer reading only the report would
   have had it.

2. **No committed record of the code-review skip decisions.** `rg` over
   `plans/2026-09-18-deliverable-review-fixes/` finds no skip log, no run
   summary, and the three report-committing commits (`04e8467`, `43cec74`,
   `0626ca8`) carry empty bodies. The skips are *inferable* from the commit
   stats — `45891f8`, `d0c13b9` and `6a77bea` touch `tests/` only — but the
   reason was not written down anywhere the audit record reaches. This is what
   let a fourth, unjustified omission sit indistinguishable from the three
   justified ones.

### Minor

3. **Three slices have no GREEN report** — 1.1/2 (`45891f8`), 1.2/1 (`d0c13b9`),
   1.3/2 (`6a77bea`). Each is a test-only commit under the "two assertion groups
   over one production change" / "small-list control" decisions, so there was no
   implementation to report; but the GREEN report is also where the suite result
   and `just precommit` evidence for the commit live. For those three commits
   there is no recorded gate run. The pre-commit hook runs `just precommit`
   unconditionally and the test reviews each record a green suite on the same
   tree, so the risk is documentary rather than real — but "no commit left the
   suite red" rests on inference for three of six commits instead of on a
   report.

4. **`b68cede` carries a `memory` submodule pointer bump** alongside
   `toolkit/release.sh` and `tests/release-test.sh`. The GREEN report names it,
   attributes it to the gitlore pre-commit hook, and confirms
   `.claude/handoff-*.md` were not swept in. No later slice commit repeats it.
   Recorded, not charged against the slice.

### Checks that came back clean

- **Genuine red, reviewed.** All six slices have a RED report. No report shows a
  test PASSING where a red was claimed. Every quoted failure is an
  `assert_eq`/`assert_contains`/`assert_not_contains` value mismatch with the
  captured `$out` showing a normal `die` or a completed run — no
  command-not-found, no syntax error, no missing fixture. Each test review
  independently re-ran the red and reproduced it verbatim.
- **One green commit per slice.** Six slices, six marker-bearing GREEN commits,
  each named by hash in its report (or, for the three without a GREEN report,
  uniquely identified by the `Item N.M/k` marker and matching the test-review's
  final test text). The only second marker-bearing commit is `4d9bc80`
  (`Item 1.1/1 — code-review fixes`), which `item-1-1-s1-code-review.md`
  accounts for. No slice is split across commits; no commit carries two slices.
- **No commit carries a mutation.** `git show` on each slice commit confirms the
  production hunks are the *fix* direction, never the mutation: `b68cede`
  removes `git tag --list … | semver_tags`; `a69c97f` removes
  `printf … | grep -qxF`; `07b7ae9` removes `git describe --tags --abbrev=0`.
  The three test-only commits touch no production file at all. Every mutation
  red (1.1/2, 1.3/2, and the liveness probes in 1.2/1) is followed by a quoted
  `git diff --quiet` exit-0 restore.
- **GREEN dropped no reviewed test.** Every test id listed in a test-review
  report appears in its slice commit, same name, same file — including the ids
  the *reviews themselves added*: `1.1/2`'s `… exit code` and
  `… refused at the tag read`, `1.2/1`'s `lose_tag "$plugin"` +
  `push -q origin :refs/tags/v1.2.3` fixture, `1.2/2`'s post-filter size guard,
  and `1.3/2`'s three `merge-base --is-ancestor` fixture guards. Nothing
  renamed, nothing relocated, nothing dropped.
- **No GREEN dispatch edited a test file.** All three GREEN reports state it
  explicitly, and the diffs corroborate: `b68cede`'s and `a69c97f`'s
  `tests/release-test.sh` hunks are pure additions matching the test-review's
  final text; `07b7ae9`'s `tests/self-release-test.sh` hunk is the slice test
  plus the dist-squatting comment restatement the item's "Also update" clause
  requires.
- **Scope compliance.** No Phase 1 commit touches a later item's work product.
  `git log 73d46da..HEAD -- tests/release-test.sh tests/self-release-test.sh`
  shows Items 2.1 and 3.1 later editing those files, and
  `git diff 73d46da..HEAD` over them contains no line mentioning any Phase 1
  scenario — the six scenarios are untouched by later phases.
- **Tests are reached by the gate.** All six scenarios are present at `HEAD` at
  `tests/release-test.sh:1479,1522,1581,1641` and
  `tests/self-release-test.sh:234,248`, at file top level in suites
  `just precommit` runs. Verified read-only at `HEAD`:
  `bash tests/self-release-test.sh` → `self-release.sh: ok` (EXIT=0),
  `bash tests/release-test.sh` → `all release scenarios passed` (EXIT=0), with
  all six scenario banners printed.
- **Regression handling.** No batched regression fixes. Both GREEN reports that
  had a sequence to record state that a single test was red and one minimal edit
  closed it (`item-1-2-s2-green.md` "Order tests were made to pass";
  `item-1-3-s1-green.md` "no regression loop was needed").
- **Refactoring separation.** One `REFACTOR-NEEDED` was raised
  (`item-1-1-s2-test-review.md`, the duplicated stripped-copy stub block) and
  correctly DEFERRED as out of scope rather than folded into a slice commit. No
  refactor report was due and none is missing.

## Verdict on the three recorded decisions

I judged each independently rather than accepting the framing.

1. **Mutation reds.** Two slices took their red under the item's named mutation:
   1.1/2 (restore `git tag --list … | semver_tags`) and 1.3/2 (revert to
   `git describe --tags --abbrev=0 --match 'v*'`). In both cases the mutation
   *is* the behaviour the test holds, and the failure is attributable to it and
   nothing else: under 1.1/2's mutation the captured `$out` shows
   `first release: publishing the manifest version 1.2.3 as-is` followed by tag
   push and `gh release create` — the exact hazard the item names, not an
   unrelated early exit; under 1.3/2's the `$out` shows a complete
   `Release v0.2.0 complete` run, so the drift guard was skipped rather than
   tripped for another reason. Neither is a wrong-reason red. Both were
   re-applied and re-reverted independently by the test reviewer.

   Item 1.1/2 deserves particular credit: the executor's *first* fixture
   produced a red that would have passed under the mutation too, recognised it
   as vacuous, replaced the fixture with `make_virgin "1.2.3"`, and reported the
   rejected attempt rather than shipping the spurious evidence. That is the
   failure mode this audit exists to detect, caught upstream of it.

2. **Two assertion groups over one production change** (Items 1.1 and 1.3).
   Confirmed from the diffs: `b68cede`/`4d9bc80` carry all of Item 1.1's
   production change and `45891f8` none; `07b7ae9` carries all of Item 1.3's and
   `6a77bea` none. The second slice in each pair is a test-only commit, and its
   empty code-review scope follows.

3. **Item 1.2 slice 1 is a control.** Confirmed and, importantly, *repaired*
   during the run: the test review measured that the scenario passed with its
   `git` stub disabled — i.e. as shipped by RED it was not a control at all —
   and fixed it by deleting origin's real tag so the stub is the only source of
   a listing. The slice's red substitute (a temporary needle mutation proving
   branch 1 is live) is legitimate control evidence, and the runbook records why
   no defect-red is possible below ~1 MB. Not a violation.

## List Revisions

- **One recorded revision**, `04e8467`
  (`📝 Item 1.1 — list revision and execution reports`), adding a six-line
  "**Fixture, revised as executed:**" block to Item 1.1 slice 2 in `runbook.md`,
  documenting the `make_virgin` fixture change and why `new_sandbox "1.2.3"`
  alone was vacuous. This matches the RED report's account exactly.
- No other Phase 1 divergence from the initial slice lists: six slices planned,
  six executed, in the planned order, with the planned targets.
  `git log --follow` on `runbook.md` shows no other revision after execution
  began (`af72c2a` is the pre-execution `/proof` pass).

## Code Quality Observations

- **Test quality is high and improved under review.** Every scenario pairs its
  negative assertion with a positive over the same fixture; the reviewers caught
  the two places where that was not true (`1.1/2`'s three bare absences,
  `1.3/2`'s unpinned reachability split) and closed both. The `1.2/1` finding —
  a stub the scenario did not depend on — is the strongest single review catch
  in the phase, because slice 2's whole discrimination inherits that fixture.
- **Assertions pin reasons, not outcomes.**
  `assert_not_contains "$out" "git fetch --tags"` (1.1/1) and
  `assert_contains "$out" "does not match latest tag (v0.9.0)"` (1.3/2)
  discriminate *which* branch fired, not merely that the run refused. Several
  reports note explicitly that `rc` alone cannot distinguish the branches.
- **Set comparison over named refutation** in `45891f8`: the tag-set assertions
  compare against before-snapshots rather than naming `v1.2.3`, so a mutation
  publishing a different version is still caught.
- **Implementation quality: one defect class recurred and was caught late.**
  `scripts/self-release.sh`'s `|| latest_tag=""` (landed in `07b7ae9`) is the
  same fail-open shape M2 was filed against, written into the file by the item
  fixing a neighbouring defect. `toolkit/release.sh`'s `semver_tags` draws the
  `[ "$?" -eq 1 ]` distinction explicitly; the new site did not. Fixed at the
  phase boundary, not at the slice.
- **Comment defects outnumber code defects 5:1** across the phase's review
  findings (false ordering claim, self-contradicting hazard paragraph, circular
  cross-reference, two false `dist-v*` mechanism claims, two stale line
  citations). Every one of them was a claim about mechanism that was checkable
  and wrong. No reviewer found a code defect that the tests had missed, other
  than corrector Major 2.

## Recommendations

### Critical

1. **Run the missing Item 1.3/1 code review, or record why not.** The slice's
   production hunk went to the phase boundary unreviewed and arrived with two
   Major defects. Both are now fixed in `73d46da`, so the remedy is documentary:
   add `reports/item-1-3-s1-code-review.md` recording that the review was
   omitted, that `phase-1-corrector.md` covered the same region, and what it
   found — so the gap is visible to the next reader rather than looking like a
   fourth empty-scope skip. File:
   `plans/2026-09-18-deliverable-review-fixes/reports/`.

### Important

2. **Make a skipped dispatch leave an artifact.** A skip justified by empty
   scope should write a one-paragraph stub report naming the slice, the commit,
   and the `git show --stat` line that proves the scope was empty. Had that
   convention been in force, the 1.3/1 omission would have been a missing file
   among five present rather than a fourth absence among four. Encode it in the
   execution skill's dispatch rules, not in this runbook.

3. **Require a GREEN report even for a test-only slice.** The three commits
   without one (`45891f8`, `d0c13b9`, `6a77bea`) have no recorded suite or
   `just precommit` result. A three-line GREEN report naming the commit, the
   closing suite line and the gate result costs nothing and closes the only
   place in this phase where "the suite was green at that commit" is inference.

### Minor

4. **Keep the "rejected fixture" disclosure as a required RED field.**
   `item-1-1-s2-red.md`'s account of the vacuous first fixture is the single
   most valuable paragraph in the phase's evidence. Making "fixtures tried and
   rejected, and why" an explicit RED report heading would make that habit
   systematic rather than one executor's good judgement.

5. **Add a mechanism-claim check to the code-review prompt.** Every comment
   defect found in Phase 1 was a falsifiable claim about what a command does,
   and each was falsified by one scratch-repo probe. A review instruction to run
   one probe per mechanism claim in a new comment would have caught the
   `dist-v*` glob claim at slice 1.3/1 instead of at the phase boundary.

## Process Metrics

- Slices executed: 6; fully compliant: 5 (1.3/1 fails on the missing code
  review).
- GREEN commits: 6; code-review-fix commits: 1 (`4d9bc80`), accounted for.
- Reports present: 6 RED, 6 test-review, 3 GREEN, 2 code-review, 1 phase
  corrector. Missing: 3 GREEN (empty-implementation slices), 4 code-review (3
  justified by empty scope, 1 not).
- Wrong-reason / vacuous tests caught at test review: **4** — 1.1/2 (bare
  negative set, 2 Major), 1.2/1 (stub not load-bearing, 1 Major), 1.3/2
  (reachability split unpinned, 1 Major). Plus 1 caught by the executor before
  review (1.1/2's rejected fixture).
- Defects caught at code review / phase checkpoint: 3 comment defects (1.1/1), 0
  (1.2/2), 4 at the phase boundary (2 Major, 2 Minor).
- Dispatches per item: Item 1.1 — 7 (red, test-review, green, code-review; red,
  test-review); Item 1.2 — 6 (red, test-review; red, test-review, green,
  code-review); Item 1.3 — 5 (red, test-review, green; red, test-review).
- Reds by kind: 3 genuine fail-before-fix (1.1/1, 1.2/2, 1.3/1), 2 named
  mutation (1.1/2, 1.3/2), 1 declared control (1.2/1).
- Mutations applied and restored: 6 across RED, test-review and code-review
  dispatches; 6 quoted `git diff --quiet` exit-0 restores; 0 mutations in any
  commit.
- Tree state at audit close: unchanged — `git status --short` shows only the
  pre-existing staged `.claude/handoff-*.md` and the sandbox mask dotfiles.

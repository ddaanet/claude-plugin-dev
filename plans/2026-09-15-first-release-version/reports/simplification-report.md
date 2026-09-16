# Simplification Report

**Runbook:** plans/2026-09-15-first-release-version/runbook.md **Date:**
2026-09-16T00:00:00Z

## Summary

- Items before: 12 (1.1, 1.2, 1.3, 1.4, 2.1, 3.1-3.6, 4.1), with 21 slices
  across the two tdd items' phases (Phase 1: 15 slices across 1.1/1.2/1.3/1.4;
  Phase 2: 6 slices in 2.1)
- Items after: 12 (unchanged)
- Consolidated: 0 items across 0 patterns

No edits were made to runbook.md. This report documents the three candidate
patterns named in the dispatch, why each was read from the two live test suites
(`tests/release-test.sh`, `tests/hook-test.sh`) rather than the runbook prose
alone, and why none qualifies once read that way.

## Consolidations Applied

None.

## Patterns Not Consolidated

### 1. Item 1.2's six lost-tags slices (the flagged primary candidate)

Surface indicator matched: six slices under one item, all exercising the
lost-tags origin probe with varying fixtures — this is exactly the shape the
"identical-pattern items" detector looks for. Reading each slice's own "Red:"
clause against the described implementation shows the match is surface-only:

- Slice 1 is red because the probe does not exist at all.
- Slice 2 is red because a naive probe checks only `v$V`, not any semver tag on
  origin — a fixture that would pass slice 1's implementation but fail this one.
- Slice 3 is red because a naive probe reads `ls-remote`'s lexicographic order
  rather than `--sort=-v:refname` — passes slices 1-2's implementation, fails
  this one.
- Slice 4 is red because a naive probe runs after `check-version.sh` rather than
  before it — passes slices 1-3's implementation, fails this one.
- Slice 5 is red because a naive probe treats a failed `ls-remote` as an empty
  listing rather than refusing — passes slices 1-4's implementation, fails this
  one.
- Slice 6 maps to FR-8, not FR-4: a different requirement (the marketplace entry
  disagreement refusal), only reachable once slices 1-5 land, and already
  flagged in the runbook as depending on both 1.2 and 1.3.

Each slice is the proof that one specific defect in a plausible partial
implementation is still uncaught by the slices before it — the runbook's own
"Red:" annotations state this explicitly and progressively (each says what
today's code, or a narrower fix, still gets wrong). Merging them into one
parametrized table would still show the merged item red against *unchanged*
code, but would lose the incremental proof that each is red against the
*previous slice's fix* — which is the actual thing the red-first discipline in
this runbook is protecting, per the "Red first" standing constraint and
CLAUDE.md's TDD guardrail against bundling reds that exercise different
behaviour. Not consolidated.

Within-slice batching that already exists and is correctly left alone: slice 1
already parametrizes two sub-tests (with and without a bump argument) under one
red reason; slice 5 already parametrizes two sub-tests (unreachable URL, removed
remote) under one red reason (a failed listing). These are the same-red-reason
merges the simplification pass would otherwise recommend, and the runbook's
author already applied them.

### 2. Item 1.3's three push-route settings

Surface indicator matched: three settings behind one refusal, the shape of "N
items each adding one case." Reading slice 1's text shows it is already a single
slice with "one test per setting in a loop over `remote.origin.pushurl`,
`branch.main.pushRemote` and `remote.pushDefault`," all red for the same reason
("none of the three is consulted today"). This is already the consolidated form
— one parametrized item, not three. Nothing to merge.

### 3. Item 1.4's four resume hint-ladder branches

Surface indicator matched: four slices, each adding one branch to the same
`if`/`elif` ladder in `resume_preflight`'s no-tag hint — the "sequential
additions to the same control structure" shape. Each slice's own text states a
distinct red reason tied to the ladder's branch order, not just varying fixture
data:

- Slice 1: red because today's code advises the bump form on a virgin repo,
  which a first release refuses on sight.
- Slice 2: red because there is no `v$V`-on-origin branch yet.
- Slice 3: red for a stated ordering reason — without this branch,
  `release_tags` emptiness falls through to slice 1's branch, which then hits
  the release guard's own refusal: "two refusals to reach advice the first one
  had." This is a distinct defect from slice 2's, contingent on branch order.
- Slice 4 is two regression guards (already batched into one slice) proving the
  pre-existing local-hint branches still fire once the new branches exist —
  explicitly labelled "green today" in the runbook, i.e. not a red proof at all,
  but a non-regression check that has to run after the other three land.

These are ladder branches whose reds are order-dependent on each other (slice
3's red reason is stated in terms of what slice 1 would otherwise do to this
fixture). Collapsing them into one parametrized item would still fail against
unchanged code, but would erase the proof that branch 3 specifically needs to
exist ahead of branch 1's catch-all — which is the reason the runbook gives for
keeping them ordered and separate. Not consolidated.

### Other categories checked, no candidates found

- **Independent same-module functions:** Item 1.1 adds `semver_tags()` and
  `release_tags()`; Item 1.2 adds `origin_release_tags()`. These read like the
  "each item adds one small function to the same file" shape, but 1.2 depends on
  1.1 (stated `Depends on: Item 1.1`) and maps to different requirements
  (FR-1/FR-2/FR-3 vs FR-4/FR-8) — a dependency chain and requirement split the
  runbook's own constraints forbid merging across.
- **Sequential additions to a data/doc structure:** Phase 3's six doc items each
  touch a different file (`release-flow.md`, `version-guard.md`, `recovery.md`,
  `design.md`, `release.just`+`README.md`, the changelog). This is already the
  consolidated grouping — each item batches every hunk belonging to one file (or
  one closely-coupled pair) rather than splitting per hunk. Item 3.3 alone
  already merges four hints into one item, and 3.5 already merges two files.
  Nothing further to batch without crossing a `Depends on` edge (3.4 depends on
  3.1+3.2; 3.6 depends on 3.1-3.5).
- **Item 2.1's six slices** (version-guard.sh): each is red for a distinct,
  separately-named reason (deny-reason wording, no route to `$proposed`,
  `systemMessage` byte-identity, predicate-not-count, `GIT_*` clearing, and
  failure-vs-emptiness) — the same order-dependent-proof shape as Item 1.4,
  confirmed against `tests/hook-test.sh`'s existing `assert_deny`/
  `assert_allow` helpers, which give no indication a merge would preserve each
  red individually. Not consolidated.

## Requirements Mapping

No changes — all mappings preserved (runbook.md was not modified). The
FR-1..FR-10 table at plans/2026-09-15-first-release-version/runbook.md:37-48 is
unchanged, and every item/slice referenced above still exists exactly as before.

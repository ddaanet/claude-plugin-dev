# Runbook Review: first-release version selection

**Artifact**: plans/2026-09-15-first-release-version/runbook.md **Design**:
plans/2026-09-15-first-release-version/outline.md **Date**: 2026-09-16 **Mode**:
review + fix-all

## Summary

Every outline rule, decision and per-file change reaches an item; the phase
split, dependency edges and item granularity hold up, and the two ordering calls
the runbook made on its own were checked against the fixtures and are both
correct. Three findings were critical: one slice fixture that cannot go red at
all, one slice whose stated red is the wrong failure for its position in the
sequence, and a standing constraint whose "red against unchanged code" wording
contradicts roughly a third of the slices and invites an executor to fabricate a
red. All findings are fixed in place.

**Overall Assessment**: Ready

## Ordering calls verified against the fixtures

- **Item 1.1 before Item 1.2.** `make_virgin` (`tests/release-test.sh:194-213`)
  deletes the tag locally *and* pushes the deletion to origin (`:201-202`), so
  the scenario at `:625` has no tags anywhere. Inverting it under Item 1.1 alone
  is correct. I walked the other tag-sensitive scenarios (`:592`, `:610`,
  `:625`, `:634`, `:643`, `:721`, `:361`) against the post-1.1 predicate: all
  stay green, and all stay green again once Item 1.2's probe lands, because no
  existing scenario leaves a semver tag on origin. The claim holds. Recorded in
  the Phase 1 header so the next reader does not have to re-derive it.
- **Item 1.4 slice 4's fixture.** With `v1.2.3` kept locally and deleted from
  origin and the manifest at `1.2.4`: branch 1 (`v$V` on origin) misses, branch
  2 (any semver on origin) misses because origin is empty, branch 3
  (`release_tags` empty) misses because the local tag was kept — branch 4 fires.
  The claim holds; both conditions are now stated in the slice, since either one
  alone would silently retarget the test.

## Requirements Coverage

| Requirement | Phase | Items | Coverage | Notes |
|---|---|---|---|---|
| FR-1 | 1 | 1.1/1 | Complete | |
| FR-2 | 1, 2 | 1.1/1-3, 2.1/4 | Complete | Filter duplicated, one tag set |
| FR-3 | 1 | 1.1/1 | Complete | Commit instruction now also in item prose |
| FR-4 | 1 | 1.2/1-5 | Complete | |
| FR-5 | 1 | 1.4/1-4 | Complete | Four ladder branches, one per slice |
| FR-6 | 1 | 1.3/1-2 | Complete | |
| FR-7 | 2 | 2.1/1-3, 6 | Complete | |
| FR-8 | 1 | 1.2/6 | Complete | Hint branch now named in 1.2's prose |
| FR-9 | 3 | 3.1-3.6 | Complete | |
| FR-10 | 4 | 4.1 | Complete | |

Deliverable-level pass over the outline's per-file sections found four design
elements that reached no item; all four were added (see Major Issues 2-4 and
Minor 3).

## Review Findings

### Critical Issues

1. **Item 1.2 slice 3's fixture cannot go red — the sort is untested**
   - Location: Item 1.2, slice 3
   - Problem: the fixture was origin holding `v1.2.3` and `v1.10.0`, asserting
     the hint names `v1.10.0`. `git ls-remote` orders refs lexicographically by
     refname, so its first line for that pair is already `refs/tags/v1.10.0` —
     which is also the version-newest. An implementation that omits
     `--sort=-v:refname` and takes the first line passes. Verified empirically
     (git 2.47.3): default order over `v1.2.3 v1.9.0 v1.10.0 v1.11.0 v1.2 vnext`
     is `v1.10.0 v1.11.0 v1.2 v1.2.3 v1.9.0 vnext`. The outline's own example
     (`v1.10.0, v1.2.3, v1.9.0`) has the same defect — its first entry is the
     newest too. Since the runbook says "nothing else tests the sort", the
     `--sort` would have shipped unproven.
   - Fix: fixture is now `v1.9.0`, `v1.10.0`, `v1.11.0` on origin, none local,
     hint must name `v1.11.0`. Unsorted order is `v1.10.0 v1.11.0 v1.9.0`, so
     the first line *and* the last are both wrong — red against either naive
     reading. The slice records why a `v1.2.3`/`v1.10.0` pair is not red, so the
     simpler fixture is not reintroduced.
   - **Status**: FIXED

2. **Item 1.2 slice 2's red claim is wrong for its position**
   - Location: Item 1.2, slice 2
   - Problem: "Red: today it bumps to `1.3.1`" is true of *unchanged* code, but
     slice 2 lands after Item 1.1. With the conjunct dropped and no probe yet, a
     tagless clone whose manifest was hand-advanced to `1.3.0` reads as a first
     release and **publishes `v1.3.0`** — tags HEAD, pushes the tag, calls
     `gh release create`, bumps nothing. The slice is still red, but on the
     opposite failure, and an executor reconciling the run with the stated claim
     would conclude the fixture is wrong.
   - Fix: red claim restated as the publish outcome, with the pre-1.1 behaviour
     kept in parentheses; added `$GH_LOG` empty and "no `v1.3.0` tag on origin"
     to the assertions, which are what catch it.
   - **Status**: FIXED

3. **The "Red first" standing constraint contradicts the slice design**
   - Location: Standing constraints
   - Problem: it required every slice to be "shown failing against unchanged
     code". That is true of about half the slices. The rest — 1.2/3, 1.2/4,
     1.2/5, 1.4/4, 2.1/2, 2.1/3, and the `v1.2.3` half of 2.1/4 — are
     discriminating fixtures, red only against the narrowest implementation that
     passes the slices before them, or outright green guards. The simplification
     report already reasoned in those terms; the constraint did not. Under
     `/orchestrate` a red-phase reviewer holding the literal wording either
     blocks a correct slice or pushes the executor to manufacture a failure.
   - Fix: constraint restated — red against the code as it stands at that slice,
     with the `Red:` line naming the implementation it discriminates against
     where that is not unchanged code, and an explicit **guard** label for
     slices that are green when they land and must not be forced red. Labels
     applied to 1.4/4 (both tests), 2.1/2, 2.1/3 and 2.1/4.
   - **Status**: FIXED

### Major Issues

1. **Item 1.4 slices 2 and 4 disagree about the scenario at `:361-367`**
   - Location: Item 1.4, slices 2 and 4
   - Problem: slice 2's fixture *is* the existing scenario at `:361-367`
     (`new_sandbox "1.2.3"`, local tag deleted, origin's kept), but read as a
     new scenario; slice 4 then said that scenario "moves". Whichever is meant,
     `:361-367`'s current `run \`just release <bump>\` instead` assertion fails
     the moment slice 2's branch lands, so leaving it untouched breaks the suite
     at slice 2's green — the one boundary the phase design promises.
   - Fix: slice 2 now says it rewrites `:361-367` in place and keeps its
     `no tag …` assertion; slice 4 adds a *new* scenario re-establishing the
     `<bump>` coverage slice 2 removed.
   - **Status**: FIXED

2. **Item 1.1 prose omitted two changes its slices require**
   - Location: Item 1.1, lead paragraph
   - Problem: (a) the bump-refusal hint edit (`:227-235`) appeared only inside
     slice 1's third test; (b) nothing said `marketplace_entry_exists` survives.
     Dropping the conjunct leaves it unused in `release_preflight`, and an
     executor tidying up would delete a variable `bump_marketplace` still reads
     at `:383` and `:455` to choose between creating and bumping the entry —
     breaking first publication, which no scenario in the phase re-tests until
     `:634`.
   - Fix: both stated in the item, with `bump_commit_tag`'s untouched
     initial-release branch (outline "stay as they are").
   - **Status**: FIXED

3. **Item 1.2 prose omitted the Decision 1 hint branch**
   - Location: Item 1.2, lead paragraph
   - Problem: slice 6 requires `release_preflight`'s `check-version.sh` failure
     hint (`:202-206`) to branch when no semver tag exists anywhere; the item
     described only the probe, so the change had no home in the item's stated
     scope.
   - Fix: added, pointing at slice 6.
   - **Status**: FIXED

4. **Item 2.1 omitted two outline elements**
   - Location: Item 2.1, lead paragraph
   - Problem: the accepted bound the outline requires in a comment (a
     `CLAUDE_PROJECT_DIR` that is not a repo but sits inside one lists the
     enclosing repo's tags) reached no item, and nothing said the
     initial-release branch keeps the no-bypass sentence — the property the
     whole guard exists for, and the one an agent-facing rewrite is most likely
     to soften.
   - Fix: both added.
   - **Status**: FIXED

5. **Item 1.2 slice 1's `patch` test is satisfiable by the wrong refusal**
   - Location: Item 1.2, slice 1
   - Problem: with Item 1.1 landed, the bump refusal also exits 1 and its hint
     already names `v1.2.3` ("to publish v1.2.3"), leaves no tag, calls no `gh`
     and advances no origin. Only `git fetch --tags` discriminated, and nothing
     pinned the probe as running *ahead* of the bump refusal — which is FR-4's
     substance.
   - Fix: added "output does not name `never been released`", with the reason.
   - **Status**: FIXED

6. **Item 1.3 slice 1's fixture is underspecified in a way that changes it**
   - Location: Item 1.3, slice 1
   - Problem: "each pointed at a second bare repo" is only possible for
     `remote.origin.pushurl`. `branch.main.pushRemote` and `remote.pushDefault`
     take a remote *name*; set to a path they are not the state the outline
     describes, and the asserted "value" differs. Two executors write two
     fixtures.
   - Fix: the slice now says the fixture adds `git remote add other <repo>`
     first and sets those two to `other`, and asserts the value actually set.
   - **Status**: FIXED

### Minor Issues

1. **Item 1.2 slices 3 and 4 did not name their `new_sandbox`** — "origin holds
   `v1.2.4`, manifest `1.2.4`, entry `1.2.3`, no local tag" leaves the setup
   sequence to the executor. Both now spell out the sandbox, which tag is
   deleted where, and that the manifest advance is committed. **Status**: FIXED
2. **Item 1.2 slice 5's setup order is load-bearing** — `make_virgin` pushes, so
   breaking origin before it runs kills the fixture. Stated. **Status**: FIXED
3. **The outline's "no shipped file added or removed" check was unrecorded** —
   added to the Phase 3 header, covering the CLAUDE.md Layout list,
   `dist-tree-test.sh` and `doc-sync-test.sh`. **Status**: FIXED
4. **Item 2.1 slice 1 asserted a paraphrase** — "states that the manifest holds
   the version the first release will publish" is not a test. Replaced with the
   literal substrings (`never been released`, `will publish`, absence of
   `last released version`). **Status**: FIXED
5. **FR-8's table note** ("rests on 1.2 and 1.3 having landed") read as a
   dependency that the phase order contradicts — slice 6 is inside 1.2 and lands
   before 1.3. Reworded to what it means: Decision 1's *trust* in the probe
   rests on 1.3. **Status**: FIXED
6. **Fixture tag set** — the new sort tags are additional to the shared
   `vnext`/`v1.2`/`v1.2.3` set; noted in the standing constraint that they
   exercise ordering, not the filter, so the "keep both suites in step" rule is
   not read as requiring them in `hook-test.sh`. **Status**: FIXED

### Observations, not fixed

- **`toolkit/release.sh` growth.** 508 lines today; Phase 1 adds three
  functions, a probe block, a hint branch and their comments — call it 560-580.
  No gate measures it (`tests/docs-test.sh` caps `docs/` and `plans/` only), and
  the 400-line convention is soft. Splitting a top-level-flow script mid-plan
  would be scope creep, so no item was added; flagging it as the moment the file
  stops being one sitting's read. `tests/release-test.sh` (756) grows by roughly
  15 scenarios.
- **Runbook size.** 392 lines after the fixes, against the 400-line cap
  `tests/docs-test.sh` enforces over `plans/`. `/proof` has ~8 lines of room;
  anything larger has to buy its space back.

## Fixes Applied

- Standing constraints, "Red first" — restated per finding C3, guard label
  introduced.
- Standing constraints, fixture tag set — sort tags noted as ordering-only.
- Requirements table, FR-8 note — reworded.
- Phase 1 header — `:592`/`:634`/`:721` recorded as staying green; the
  `make_virgin` fact that licenses the 1.1-before-1.2 order recorded.
- Item 1.1 prose — bump-hint edit, `marketplace_entry_exists` retention,
  `bump_commit_tag` unchanged.
- Item 1.2 prose — Decision 1 hint branch.
- Item 1.2 slice 1 — `never been released` absent, with its reason.
- Item 1.2 slice 2 — red claim rewritten; `$GH_LOG` and origin-tag assertions.
- Item 1.2 slice 3 — fixture replaced (`v1.9.0`/`v1.10.0`/`v1.11.0`), red reason
  grounded in the verified `ls-remote` order.
- Item 1.2 slice 4 — fixture spelled out.
- Item 1.2 slice 5 — setup order.
- Item 1.3 slice 1 — pushRemote/pushDefault take a remote name.
- Item 1.4 slice 2 — rewrites `:361-367` in place.
- Item 1.4 slice 4 — new scenario, both fixture conditions stated, guards
  labelled and the second test's discriminating implementations named.
- Item 2.1 prose — no-bypass sentence, accepted-bound comment.
- Item 2.1 slices 1-4 — literal assertions, guard labels, red reason for 4.
- Phase 3 header — shipped-path check.

Gate: `just format-docs` clean, `bash tests/docs-test.sh` green, runbook at 392
lines. Working tree left dirty, one modified file.

## Design Alignment

No contradictions with the outline. Where the runbook already diverged it was
right and stays: the outline says the resume refusal has "three hints", the
ladder it then specifies has four, and the runbook's Item 3.3 says four.

Checked and confirmed against the live code rather than the prose: the probe
must precede `check-version.sh` (`release.sh:202-206`) and every side effect
(`:314-320`, `:342`, `:365`); `common_preflight` validates `origin` only when
there is no marketplace entry (`:176-177`), which is what lets Item 1.2 slice
5(b) reach the probe at all; `resume_preflight`'s refusal (`:283-288`) has no
side effect, so a failed listing there can fall through to local advice;
`hook-test.sh`'s `$proj` is not a repo (`:28`), so its six existing scenarios do
exercise Item 2.1's listing-failure fallback and must pass unchanged;
`assert_deny` (`:55-69`) already covers exit code, stdout JSON, `systemMessage`
and empty stderr, so Item 2.1's slices inherit the bypass check.

Recall entries applied: `git-hook-env-leak` (harness `unset` plus the guard's
own clearing, kept as distinct slices), `hook-output-channels` (only
`permissionDecisionReason` branches), `no-stderr-suppression` (the `2>/dev/null`
justification stays inline in the item), `no-backcompat` (the conjunct goes
outright), `claude-plugin-dev` (the changelog does not ship, so the index line
is the only consumer-facing notice).

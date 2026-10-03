# TDD Process Review: 2026-10-03-dogfood-review-fixes

**Date:** 2026-10-03 **Runbook:** none. Slices were defined at dispatch time
from `plans/2026-10-03-dogfood-review-fixes/outline.md`. **Commits analyzed:**
`f7a9bcf0c9f75f8ccdc67acd6d2d02895045b90e..3780b7d` (11 commits)

## Executive Summary

The three behaviour slices (1.1/1, 1.1/2, 1.2/1) comply with every per-slice
check. Each shows a genuine assertion-level RED that a test review confirmed and
hardened. Each slice is one GREEN commit carrying its tests, its implementation,
and its RED, test-review and GREEN reports. Each code review is its own later
commit. No reviewed test was dropped or renamed. This audit re-ran each slice
commit's tests against the parent commit's code and got exactly the FAIL lines
the reports record, and all five dogfood suites pass at every code commit in the
range.

The test-only item 1.3 is where the process was weaker. Its four mutation proofs
are present and correct, one per named change, but no test review reproduced
them. The m12 move in that item also dropped the rejection half of the case it
moved. The closing code review caught that and restored it in `cb64414`.

Recommendations:

- Give test-only items a test-review dispatch.
- Keep RED reports in step with the scenarios added at test review.
- Record the item and slice list somewhere durable when no runbook exists.

## Per-Slice Compliance

| Item/slice | RED evidence | Test review | One slice commit | Tests unmodified | Issues |
|---|---|---|---|---|---|
| 1.1/1 | Yes: "a variable equal to this copy skips the sync" red on 2 assertions; scenarios 1 and 3 use a mutation proof | Yes: mutants A–D and a GREEN probe; 1 Major + 1 Minor fixed | `9104046` (+ code review `6b985df`) | Yes: all 4 reviewed ids present at `9104046` and HEAD | RED report has no addendum for the list scenario added at test review (minor) |
| 1.1/2 | Yes: "a failed sync aborts the launch" red on the count assertion | Yes: 9 candidate GREENs probed; 2 Major + 2 Minor fixed | `e77ca7d` (+ code review `b6aa831`) | Yes: "a failed rsync keeps its status" added at review and present at HEAD | GREEN report's per-test sequence understates the red set (minor) |
| 1.2/1 | Yes: 2 tests red on `exit code` (`got '5'`, `got '2'`); a third added at review, with a RED addendum | Yes: half-GREEN probe; 1 Major fixed | `d6df153` (+ code review `0a2631d`) | Yes: all 3 ids present at `d6df153` and HEAD | none |
| 1.3 (test-only) | Mutation proof: 4 mutations, one per named change, each red on its own assertion, each restore verified | **None** | `b8da498` | n/a (no GREEN). The m12 move dropped an assertion pair, restored in `cb64414` | no test review reproduced the proofs; m12 negative half dropped |

## Violations

- **Item 1.3, check 1: the mutation proofs had no test-review reproduction.**
  - Evidence: `b8da498` adds only `reports/item-1-3.md`. No
    `item-1-3-test-review.md` exists, so no reviewer reproduced the four
    mutations with different ones at item level.
  - The closing review (`reports/review-code.md`, added by `cb64414`) later
    reproduced the m10 proof (conditional payload-`cwd` root), the m12 proof
    (`cd -P` changed to `cd` in `root_dir`) and a logical shim root. It did not
    reproduce m11 or the glob-root proof.
  - Mitigation, from this audit: I reproduced both in a `git archive HEAD`
    extract under `$TMPDIR`, without touching the repository.
    - m11 mutant: `[[ -n "${CLAUDE_PROJECT_DIR-}" ]] && root=…`. "the shim
      exports the copy" goes red on 2 assertions.
    - Glob mutant: an unquoted `case` pattern in place of `[[ != ]]`. "a
      variable equal to a glob-named copy skips the sync" goes red
      (`no copy made: '…/my [consumer]/dist' exists`).
  - All four proofs therefore stand, but item 1.3 did not get them reproduced
    in-process.
- **Item 1.3, test integrity: the m12 move dropped the rejection half.**
  - `b8da498` removed the launcher suite's `session_start` helper together with
    both of its assertions:
    - silence on the exported copy;
    - `fail "…another repo's copy is not rejected"`, on
      `/elsewhere/dist/plugin`.
  - It carried only the silence over into `tests/dogfood-session-start-test.sh`.
    `item-1-3.md` states this ("The 'another repo's copy' framing is not carried
    over"), but outline decision 3 says "move, don't relabel".
  - A generic "session-start warns on another repo's real copy" scenario already
    existed. However, nothing ran the rejection through a symlinked invocation.
  - `review-code.md` Minor 1 caught this. `cb64414` restored it as
    `session-start invoked through a symlinked repo warns on another repo's copy`
    (`assert_session_warns "$label" "$root"`). It was resolved before the run
    closed. A test review of item 1.3 would have caught it one dispatch earlier.
- **Item 1.3, check 1 (minor): the m10 proof was not broken out per scenario.**
  - `item-1-3.md` proof 1 reports "69 FAIL lines" and quotes only the first. It
    does not show that the two hand-built payloads were red under the mutation:
    the jq-less control and the deny-build control.
  - The jq-less payload's `cwd` cannot matter, because `pre_tool` stands down
    before it reads the payload.
  - `review-code.md` later reran the mutation after the `pre_tool_payload`
    refactor and states that the 69 failures "include both controls". Resolved.

No violation was found for checks 2–4 on slices 1.1/1, 1.1/2 or 1.2/1.

- **Check 2.** `git log --diff-filter=A` resolves each slice's `red`,
  `test-review` and `green` reports to a single commit, and it is the same
  commit for all three: `9104046`, `e77ca7d`, `d6df153`. Each code-review report
  resolves to its own later commit: `6b985df`, `b6aa831`, `0a2631d`.
  - Each of those carries only comment or message-string changes to the file
    under review, with no test edits.
  - No `Item N.M/k` commit lacks an accounting report.
  - No report of another slice rides along.
- **Check 3.** No GREEN report records a test edit. Every scenario header the
  test reviews name is present in the slice commit's suite under the same name
  and file. It is also still present at HEAD.
- **Check 4.** No code review flagged `REFACTOR-NEEDED`, and no `-refactor.md`
  exists, so the check is not applicable.

## List Revisions

There is no runbook, so there is no `runbook.md` history. From the reports and
commit subjects, the slice list ran as follows:

- 1.1/1 Major 1;
- 1.1/2 m3;
- 1.2/1 m1;
- 1.3 m10/m11/m12;
- 2.1 and 2.2 prose.

Implied revisions:

- **1.1/1's code review fed into item 1.3.** `item-1-1-s1-code-review.md`
  recommended a glob-metacharacter fixture root, and item 1.3 absorbed it as "a
  variable equal to a glob-named copy skips the sync". `item-1-3.md` records
  this ("Review recommendation, launcher suite").
- **Outline Major 2 is not in the range.** It landed as `f7a9bcf` ("✅ pin the
  sync exclude list's root anchor", +24 lines in `tests/dogfood-sync-test.sh`).
  That commit is the range's exclusive start, so it was not audited, and it
  carries no slice report.
- **Test-review additions within slices** are not list revisions:
  - 1.1/1: the list scenario;
  - 1.1/2: the rsync scenario;
  - 1.2/1: the deny-build scenario.

No artefact records the mapping from outline findings to item and slice numbers.
That is a process gap, not a defect in the work.

## Code Quality Observations

- **Mechanical RED reproduction (this audit).** Each slice commit's suite was
  run against its parent's `toolkit/`, in `git archive` extracts. The FAIL lines
  match the test-review reports exactly:
  - `9104046` on its parent: 2 FAILs, both "a variable equal to this copy skips
    the sync".
  - `e77ca7d` on its parent: 2 FAILs. One is in "a failed sync aborts the
    launch" and one in "a failed rsync keeps its status", both on the
    not-started count.
  - `d6df153` on its parent: 3 FAILs, all on `exit code`, with `got '5'`, `'2'`
    and `'2'`.
  - None of the three runs had an ERROR.
- **Suite green at every commit (this audit).** The launcher, pre-tool,
  session-start, sync and sync-refusal suites exit 0 with zero FAIL lines at:
  - `9104046`, `6b985df`, `e77ca7d`, `b6aa831`;
  - `d6df153`, `0a2631d`, `b8da498`, `cb64414`.
- **Test-review strength.** Each test review probed plausible wrong GREENs and
  closed real holes. Examples:
  - 1.1/1: a logical `<root>` passed the whole suite, and so did a whole-entry
    `:` list match.
  - 1.1/2: a fixed `exit 1` passed, because the refusal already exits 1. The
    rsync stub exiting 23 now separates the two.
  - 1.2/1: mapping only the payload-read jq call passed.
- **Code-review mutated-SUT runs found a test gap the test review missed.** In
  1.1/1, the unquoted-`[[ != ]]` mutant left the whole suite green. That led to
  the glob-named consumer in 1.3.
- **Report accuracy (minor).**
  - `item-1-1-s2-green.md` says there was "one failing test" and that the rsync
    scenario "already passed". The test review records 2 red scenarios after its
    fixes, and this audit reproduced 2. The same change satisfied both, so the
    test-at-a-time record is imprecise rather than violated.
  - `item-1-1-s1-red.md` and `item-1-1-s2-red.md` have no addendum for the
    scenarios their test reviews added. `item-1-2-s1-red.md` does have one.
- **Assertions labelled differently from their scenario header.** Scenario "an
  inherited variable is overwritten" carries assertions labelled "an inherited
  variable naming another path still syncs" (`tests/dogfood-launcher-test.sh`,
  at `9104046`). This is harmless but makes a FAIL line harder to map back to
  its scenario.
- **Suite length.** After `cb64414`, `review-code.md` reports launcher at 429
  lines and pre-tool at 448, both over the 400-line soft cap. The review judged
  this a bounded overage on a cohesive suite and named the jq-failure group as
  the seam to split along later.
- **Untested output change outside the TDD items.** Item 2.2 (`58f24a1`) added a
  third "Next steps" line to `toolkit/install.sh`. `tests/install-test.sh` has
  no assertion on Next steps or Dogfooding. The outline files m4 under docs, so
  this is not a TDD violation, but the user-visible pointer is unpinned.
- **`cb64414` removed `unset CLAUDE_CODE_PLUGIN_DIRS` from "the shim syncs
  before exec".** This does not weaken the test: the preamble at
  `tests/dogfood-launcher-test.sh` line 20 unsets it suite-wide, and a
  prefix-assignment on a function call does not persist.

## Recommendations

### Important

1. **Dispatch a test review for test-only items.**
   - Issue: item 1.3 ran as a single dispatch with no `item-1-3-test-review.md`.
   - Impact:
     - m11 and the glob proof went unreproduced within the run.
     - The dropped m12 rejection half reached the closing review.
   - Action: for a no-GREEN item whose evidence is a mutation proof, run the
     same test-review dispatch the slices get. It reproduces each named test's
     red with a different mutation and checks moved tests against their
     originals. Where: the orchestration step that dispatches hardening items,
     and `plans/2026-10-03-dogfood-review-fixes/reports/item-1-3.md` as the
     example.

### Minor

1. **Keep the RED report in step with test-review additions.**
   - Issue: 1.1/1 and 1.1/2 test reviews added scenarios without a RED addendum.
     1.2/1 did add one.
   - Action: the test review appends the added scenario's red output, or its
     mutation disposition, to `item-N-M-s<k>-red.md`.
2. **Report the full red set in GREEN's per-test sequence.**
   - Issue: `item-1-1-s2-green.md` lists one failing test where two were red.
   - Action: GREEN starts its sequence from the suite's actual FAIL list, not
     from the RED report alone.
3. **Record the slice list when there is no runbook.**
   - Issue: the item and slice numbering is reconstructable only from report
     titles and commit subjects.
   - Action: add a short item and slice list, with the outline finding ids, to
     `outline.md` or a run summary. Note there any absorbed review
     recommendations, such as the glob fixture, and any out-of-range landings,
     such as Major 2 in `f7a9bcf`.
4. **Break a fixture-wide mutation proof out per scenario.**
   - Issue: the m10 proof cites "69 FAIL lines" plus the first one.
   - Action: list the scenarios that red, or at least the hand-built payload
     sites, as `review-code.md` later did.

## Process Metrics

- Slices executed: 3 TDD slices plus 1 test-only item. Fully compliant: 3 of 3
  slices. Item 1.3 is compliant on its RED substitute (4 of 4 mutation proofs)
  but has no test review.
- Wrong-reason tests caught at test review: 7.
  - 1.1/1: 2, the logical root (C) and the list match (D).
  - 1.1/2: 4, a fixed exit status, `claude` not required as a word, an
    unconditional line, and the line also on stdout.
  - 1.2/1: 1, the deny-build call left unmapped.
- Test gaps caught at code review: 1, the glob/unquoted comparison in 1.1/1.
- Test-integrity issues caught at the closing review: 1, the m12 negative half.
- Dispatches per item:
  - 1.1: 8 (2 slices × red, test review, green, code review);
  - 1.2: 4;
  - 1.3: 1;
  - 2.1: 1; 2.2: 1;
  - closing: 2 (`review-code.md`, `review-docs.md`).

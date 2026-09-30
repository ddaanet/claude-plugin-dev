# TDD Process Review: 2026-09-26-dist-copy-dogfood-launcher

**Date:** 2026-10-01 **Runbook:**
plans/2026-09-26-dist-copy-dogfood-launcher/runbook.md **Commits analyzed:**
fd16ae65f4b2..6253d9e (tdd items 1.1, 1.2, 1.3, 2.1, 2.2; 28 slices)

## Executive Summary

All 28 slices have all four reports. Each report is added by exactly one commit.
Each slice resolves to one GREEN commit that also carries its tests and its RED,
test-review and GREEN reports. Every slice's red is either a genuine assertion
failure or a mutation proof reproduced by the test review, and no reviewed test
id was dropped, renamed or lost between RED and HEAD, the two phase splits
included. The findings are these:

- The orchestrator edited or added tests in its own GREEN three times (1.2/5,
  2.1/4, 2.1/6).
- Three first-slice GREENs implemented most of their item's contract, which left
  12 later slices with nothing to red against (1.1/1, 2.1/1, 2.2/1).
- GREEN grew several tests at once in three slices.
- Four commits carried files from outside their slice.

The main recommendations: never let the orchestrator touch tests during GREEN,
and order slices in the plan so that each behaviour's red comes before the code
that realises it.

## Per-Slice Compliance

RED legend: **R** = genuine red on assertions against unchanged code; **M** =
mutation proof in RED; **R+M** = mixed. The test-review column records whether
the review reproduced the proof with its own, different mutation. CR is where
the code review ran: **C** = a corrector dispatch with its own commit, **N** = a
no-diff note riding the GREEN commit, **S** = the orchestrator's self-review of
its own in-session GREEN, riding the GREEN commit.

| Slice | RED | Test review | Slice commit | Tests unmodified | CR | Issues |
|---|---|---|---|---|---|---|
| 1.1/1 | R | fixed, still red | 8c65143 | yes | C 496691f | GREEN over-scope (V5) |
| 1.1/2 | M (one mutation, 2 tests) | own m1–m3; added a 3rd test | 8757ede | yes | N | V8, V9, runbook rides slice commit |
| 1.1/3 | M | own M1–M4 | c538e3c | yes | N | — |
| 1.1/4 | M | own mutations | 3c2c5e0 | yes | N | recursion residual (accepted) |
| 1.1/5 | R | fixed, still red | 1c6eaff | yes | C 7c79791 | no per-test sequence |
| 1.1/6 | R+M | own mutation | c365573 | yes | C 21b1585 | no per-test sequence |
| 1.1/7 | M | own mutations | 3f0af91 | yes | N | — |
| 1.2/1 | R | fixed, still red | 03aa880 | yes | C f2401fe | no per-test sequence |
| 1.2/2 | R | still red | 545eba1 | yes | S | V6 |
| 1.2/3 | M | own mutations | 0b7ef2e | yes | N | V4 (handoff, memory) |
| 1.2/4 | R+M | red; own mutation | c4a263c | yes | C 8c7233c | V7 (CR added tests) |
| 1.2/5 | R | still red | 3657fb1 | **no** | S | **V1**, V6 |
| 1.2/6 | R | fixed, still red | 3d78728 | yes | C b4aa2c8 | ran after 1.3/4 (L) |
| 1.3/1 | R + negative | mutation supplied by review | f5caa8f | yes | C 1bc03a8 | V9 |
| 1.3/2 | R | fixed, still red | fa834cb | yes | C fdcf8ca | V3, V7 |
| 1.3/3 | M | own mutations | 97fd4ba | yes | N | V4 (memory) |
| 1.3/4 | R | still red | 554513f | yes | S | V4 (handoff), V6 |
| 2.1/1 | R | fixed, still red | ff6c4c2 | yes | C ffae9da | V3, V5 |
| 2.1/2 | M | own mutations | 109a47b | yes | N | — |
| 2.1/3 | R+M | own mutations | 25a5401 | yes | C fe66d54 | — |
| 2.1/4 | M | own mutations | 1393276 | **no** | N | **V2** |
| 2.1/5 | M | own mutations | 08bd766 | yes | N | — |
| 2.1/6 | R | fixed, still red | 93ed5a3 | **no** (comment) | S | **V2**, V6 |
| 2.2/1 | R | fixed, still red | 4406ea0 | yes | C e20b07e | V3, V5 |
| 2.2/2 | M | own mutations | cb0be2d | yes | N | — |
| 2.2/3 | M | own mutation | 474d89a | yes | N | — |
| 2.2/4 | M | own mutation | 0021a27 | yes | N | — |
| 2.2/5 | R | still red | 3770e74 | yes | C 9196d4a | — |

"Tests unmodified" means that GREEN did not edit the tests, per its report and
the commit diff. At test-id granularity, every scenario header, and every
install assertion label that a test review names, is present in its slice commit
and still present at HEAD. The Phase 1 split (b0ede63) moved the 41
dogfood-suite scenario headers into four files unchanged. The Phase 2 split
(522eede) moved every install slice label unchanged. The later Phase 1 and
Finish commits only add tests (three newline-root scenarios).

## Violations

1. **V1 — 1.2/5: GREEN added a test scenario (critical).** The orchestrator's
   in-session GREEN added `pre-tool fails loudly on a payload jq cannot read` to
   tests/dogfood-test.sh in 3657fb1 (item-1-2-s5-green.md, "One scenario was
   added to exclude it"). No RED or test-review dispatch saw that test. It was
   never red against unchanged code. Its only evidence is GREEN's own single
   mutation (`2>/dev/null && printf x)" || exit 0`). The test review had
   recommended it as out of scope for the orchestrator, and GREEN wrote it
   instead of routing it through a RED. The runbook's list revision a08402f then
   credits it to "(test review)", which misattributes it.
2. **V2 — 2.1/4 and 2.1/6: GREEN edited tests.**
   - 1393276: the orchestrator's GREEN changed slice 1's
     `the shim exports the copy` fixture (`git init -q "$sandbox/elsewhere"`)
     and its comment. It acted on the test review's out-of-scope Major 2
     (item-2-1-s4-green.md). The change adds discrimination (a git-first root),
     but the red was shown only on the reviewer's deleted scratch copy, never in
     the repo, and no test review ran after the edit.
   - 93ed5a3: GREEN re-aligned a comment line in `make_consumer`'s header in
     tests/dogfood-launcher-test.sh (item-2-1-s6-green.md). It is harmless in
     substance, but GREEN's ban on test edits has no exception for comments.
3. **V3 — test-at-a-time not followed.** Three GREEN reports record the
   implementation written whole and the tests run together:
   - item-2-1-s1-green.md: "the shim was written whole rather than grown per
     scenario";
   - item-1-3-s2-green.md: "written in one edit; the three tests were then run
     together";
   - item-2-2-s1-green.md: "written as one function … passed together on the
     first implementation".

   Four GREEN reports with more than one new test record no per-test sequence at
   all: 1.1/1, 1.1/6, 1.2/1 and 1.1/5 (the last is one looped scenario plus a
   negative control).
4. **V4 — files from outside the slice rode slice commits.**
   - 0b7ef2e (1.2/3): `.claude/handoff-task.md`, `.claude/handoff-todo.md` and a
     `memory` submodule bump.
   - 97fd4ba (1.3/3): a `memory` submodule bump.
   - 554513f (1.3/4): the two `.claude/handoff-*.md` files.
   - 8757ede (1.1/2): a runbook list revision (7 lines), which the commit body
     declares.

   None of these is a later item's work product, so dispatch control was not
   lost. They are session bookkeeping mixed into slice commits.
5. **V5 — first-slice GREENs implemented beyond their tests and stranded later
   slices.**
   - 8c65143 (1.1/1) shipped decision 2's full pipeline: `--delete`,
     `--delete-excluded`, NUL-safe, unanchored `.git`. Slices 1.1/2, 1.1/3,
     1.1/4 and 1.1/7 had no red left.
   - ff6c4c2 (2.1/1) wrote the shim whole, which stranded 2.1/2, 2.1/4 and
     2.1/5.
   - 4406ea0 (2.2/1) built `add_hook` with its final identity and append rules,
     which stranded 2.2/2–2.2/4. The list revision 27c98e9 records "2.2/1
     implements 2–4: mutation proofs".

   The runbook's Interfaces prescribe these shapes verbatim, and its slice text
   anticipates the mutation fallback. The plan's slice order is therefore the
   root cause, and the executors followed it.
6. **V6 — implementation diffs reviewed only by their author.** In 1.2/2, 1.2/5,
   1.3/4 and 2.1/6, the orchestrator wrote GREEN in session and then
   self-reviewed it ("self-review", no corrector dispatched). This follows the
   run's recorded convention for one-line or one-guard changes (the handoff in
   0b7ef2e and 554513f). The Phase 1 and Phase 2 checkpoint correctors later
   reviewed the whole-phase diffs, so this code did get an independent review,
   but at the phase and not the slice.
7. **V7 — the code review added tests without a test review.**
   - 8c7233c (1.2/4 fixes) added
     `pre-tool follows .. past a directory not yet created` and
     `pre-tool keeps a trailing newline and a bare - in a name`.
   - fdcf8ca (1.3/2 fixes) added three session-start scenarios.

   Each is reported red against the committed SUT before the fix, but no second
   agent reproduced a proof, and the practice is inconsistent: the 2.1/3 code
   review declined to edit tests on the grounds that "tests are never edited in
   code review".
8. **V8 — a single mutation covered a batch.** In item-1-1-s2-red.md, "Both
   tests were reded by the same single mutation in one run". Each test did red
   on its own assertion, and the test review isolated test B with m2 and m3. For
   test A, though, both the RED mutation and review m1 also red B, so A never
   had a mutation of its own.
9. **V9 — tests with only one proof.**
   - `a file that becomes ignored leaves the copy` (1.1/2) was written at test
     review and proven by that reviewer's m4 alone.
   - `session-start is silent on the copy` (1.3/1) got no mutation in RED ("owed
     at the later slice"). The test review supplied the only one (always-warn).

   Neither was reproduced by a second, different mutation.

No violation was found for:

- one GREEN commit per slice (each `-green.md` is added by one hash);
- a report of another slice riding along;
- a missing code-review report (each of the 28 is added by one commit);
- a red suite at commit (every GREEN report records a green suite, and the
  pre-commit hook runs `just precommit`);
- a dropped or renamed reviewed test.

The 16 no-diff or self-review code reviews ride their GREEN commit, not a second
commit. That is the run's declared shape, and each report is still added by a
commit.

## List Revisions

The following revisions are recorded in runbook.md history, and each commit
lands after its slice's code review:

- 2502a53 (after 1.1/1): added 1.1/6's `a git failure stops sync before rsync`,
  from 1.1/1's code review.
- 8757ede (in the 1.1/2 slice commit): added
  `a file that becomes ignored leaves the copy`.
- 69be17c (after 1.1/6): the git-failure fixture became a stub `git`.
- c75c2d5 (1.2/4): added the review-added physical-spelling tests.
- a08402f (1.2/5): added `pre-tool fails loudly …`, misattributed to the test
  review (see V1).
- 1bb6e51 (1.3/2): added the code-review entries.
- f745f41 (1.2/6): added slice 1.2/6. It was executed after 1.3/4 and entered
  the runbook only after 3d78728 and b4aa2c8 landed. The decision was recorded
  beforehand in `.claude/handoff-todo.md` (554513f), so the divergence was
  recorded, but in the handoff first.
- 9d75a92 (2.1/1) and b46a50b (2.1/3): added the code-review-driven PATH cases.
- 27c98e9 (2.2/1): recorded that 2.2/2–4 are mutation proofs.
- Items with no list revision, as the handoff states: 1.3/1, 1.3/3 and 1.3/4.

## Code Quality Observations

- Test reviews were the strongest part of the run. 22 of 28 applied at least one
  wrong-reason or discrimination fix, and several built candidate
  implementations to show that the old tests passed a wrong GREEN:
  - 1.1/1: 6 wrong syncs green;
  - 2.1/1: fork, sync-after, logical root and `--show-toplevel` all green;
  - 1.2/4: a prefix-split GREEN green.
- Mutation proofs are disciplined throughout. Each mutation is an exact-string
  replacement with a landing check, and each restore is verified with
  `git diff --quiet` plus a grep for the mutant text. One RED (1.2/4 code
  review) records a first BRE-mode grep that proved nothing and re-checked it
  with `grep -F`, which is good practice.
- Tests were strengthened across slices by later dispatches, and each change was
  reviewed:
  - 1.2/2 RED moved 1.2/1's deny assertions into `assert_denied`, and the test
    review verified that all nine were preserved;
  - 1.3/3 routed 1.3/1's warn test through `assert_session_warns`, adding the
    one-object check;
  - 1.2/6 made `assert_denied` call `assert_denied_source`.

  None of these removed an assertion.
- Residual gaps were flagged and left unpinned:
  - `require_ignored_copy`'s exit-128 branch (1.1/6 code review);
  - the literal-compare rule for an unresolved `CLAUDE_CODE_PLUGIN_DIRS` entry
    (1.3/2 and 1.3/3 test reviews);
  - install.sh's `could not wire the hooks` error branch (2.2/1 and 2.2/5 code
    reviews);
  - the SessionStart side of matcher-agnostic idempotency (2.2/4).

  The first two are carried in the handoff for the run summary.
- tests/dogfood-test.sh reached 880 lines before the Phase 1 split, against the
  400 cap. The split followed the runbook's deferral to the phase boundary.

## Recommendations

### Critical

1. **Keep GREEN out of the test files.** An in-session GREEN wrote a test (V1),
   and another edited a prior slice's fixture (V2). The fix is procedural: in
   the build skill's GREEN step, a test the review recommends goes back through
   a RED dispatch, which yields a RED report, a test review and a slice of its
   own or a list revision, before GREEN resumes. The tests at issue now are
   `pre-tool fails loudly on a payload jq cannot read` in
   tests/dogfood-pre-tool-test.sh, and the `git init` in
   `the shim exports the copy` in tests/dogfood-launcher-test.sh. For both, have
   a test-review dispatch reproduce the red with its own mutation, and correct
   the runbook's "(test review)" attribution for the first.

### Important

1. **Order slices so each behaviour's red precedes its implementation (V5).**
   When an Interfaces line prescribes a whole pipeline or function (Item 1.1
   decision 2, Item 2.1's shim, Item 2.2's `add_hook`), the planner should
   either make the first slice's tests reach every clause of it, or split the
   Interfaces text so the first GREEN cannot satisfy later slices. This belongs
   in the runbook-writing step, not in the executor.
2. **Grow GREEN one test at a time and record the sequence (V3).** Each GREEN
   report should list the tests in the order they went green, with the edit that
   turned each one. "Written whole" should come back as a finding from the code
   review.
3. **Give code-review-added tests the same review as RED tests (V7).** Either
   forbid test edits in code review, as the 2.1/3 reviewer assumed, and route
   the finding to a new slice, or require a test-review dispatch on them. Pick
   one rule and state it in the code-review prompt.

### Minor

1. **Keep session bookkeeping out of slice commits (V4).** Commit the handoff,
   memory bumps and list revisions separately. List revisions already have their
   own commit type in this run (2502a53, 69be17c and later).
2. **Give each named test its own mutation (V8, V9).** This applies to tests a
   review adds as well, and a reviewer's own proof should be reproduced by a
   later dispatch.
3. **Dispatch a corrector for one-line GREENs.** Self-review saves little on a
   one-line diff, and a corrector call is cheap (V6).
4. **Add the Phase-flagged residual tests before release.** These are the
   exit-128 branch of `require_ignored_copy` and install.sh's error branch.

## Process Metrics

- Slices executed: 28 (1.1: 7, 1.2: 6, 1.3: 4, 2.1: 6, 2.2: 5).
- Fully compliant: 16 of 28 (no Issues entry, or only accepted residuals or
  runbook-sanctioned shapes). Of these:
  - 1.1/3, 1.1/4, 1.1/7, 2.1/2, 2.1/3, 2.1/5, 2.2/2, 2.2/3, 2.2/4 and 2.2/5 are
    clean;
  - 1.1/5, 1.1/6 and 1.2/1 lack only a recorded per-test sequence;
  - 1.2/6 has only its late runbook entry;
  - 1.2/4 and 1.3/2 are compliant in their own slice work, and the V7 finding
    concerns their code-review commits.
- Genuine red: 16 slices (4 of them mixed with mutation). Mutation-only: 12
  slices.
- Wrong-reason tests caught at test review: about 38 wrong-reason or
  discrimination gaps fixed, across 22 of 28 reviews. There were none in 1.1/7,
  1.2/2, 1.2/3, 2.1/2 and 2.2/2, and only a redundant assertion was dropped in
  2.2/3.
- Code-review corrector dispatches: 12. No-diff notes: 12. Self-reviews: 4.
- Dispatches per item, as RED, test review, GREEN and code review. A GREEN
  report that does not say "in session" is counted as dispatched.
  - 1.1: 7, 7, 3, 3
  - 1.2: 6, 6, 3, 3
  - 1.3: 4, 4, 2, 2
  - 2.1: 6, 6, 2, 2
  - 2.2: 5, 5, 2, 2

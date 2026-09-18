# Runbook consolidation — deliverable-review fix pass

Run 2026-09-19 over `runbook.md` (395 lines, 18 items) and
`runbook-test-suites.md` (253), after the eleven fixes of
`reports/runbook-review.md` and before `/proof`. **One merge applied**, three
candidate merges considered and rejected with reasons. Item count 18 → 15.

Gate after the edits: `just format-docs` clean and clean on re-run,
`bash tests/docs-test.sh` green (`docs ok (cap 400 lines, pointers resolve)`),
no trailing whitespace, nested-bullet field shape intact. `runbook.md` 395 →
**396**, `runbook-test-suites.md` 253 → **261**.

## The one thing that decided this pass

`/orchestrate` composes **one dispatch per item** and names it `item-N-M`
(`skills/orchestrate/SKILL.md` §2.2, `references/dispatch-composition.md`
§Naming). Agent reuse across items exists only as `SendMessage` remediation
after a failed dispatch — there is no happy path that hands item N+1 to the
agent that did item N.

So `runbook-test-suites.md`'s "Prefer one agent for the whole chain over one per
item", and `outline.md` Dependencies rule 5's "Prefer one agent per file over
one per item", **directed nothing**. Four items on one file meant four fresh
`edify:artisan` agents, each re-reading `outline.md`,
`cluster-b-test-suites.md`, `recall-artifact.md` and re-orienting in the same
336-line suite. Merging the items is the only mechanism that delivers the rule
the design already states.

That also cuts the other way, and it is why the rejections below are firm: for a
**tdd** item the dispatch count is per *slice* (four dispatches each — RED, test
review, GREEN, code review), and for an **inline** item it is zero. Merging
items of those two types changes the agent count by exactly nothing.

## Applied: Phase 2's four items → one item in four lettered parts

Items 2.1 (N7), 2.2 (M1), 2.3 (M3) and 2.4 (M4), all on
`tests/self-release-test.sh`, are now **Item 2.1** with parts (a)–(d).

**What it buys.** Three fewer artisan dispatches out of ~37 in the run, and with
them three cold starts on the same file. The quality argument is stronger than
the cost one: part (d) sweeps ten refusals, and part (c) rewrites one of those
ten — an overlap `outline.md` Dependencies already names as `B2 ↔ B3`. One agent
that has just written the rewrite is better placed to sweep it than a fresh
agent inheriting it. The same holds for Item 1.3's comment update, which lands
on the squatting refusal that is also one of the ten.

**What it costs.** Four things, all stated in the artifacts:

1. **Git history granularity.** `/orchestrate` commits once per general item, so
   the four fixture strengthenings land in one commit instead of four. Review
   granularity is *not* affected — the post-item step is `verify-step.sh`
   (precommit + clean tree), and the only review is the phase-boundary
   `edify:corrector`, which reads the whole phase diff either way.
2. **Proof granularity.** `/proof` gets one item to verdict where it had four.
   Mitigated by the lettered parts: each carries its own requirement, its own
   change and its own Mutation gate, so the item is still inspectable in four
   passes.
3. **N7's droppability.** The drop decision routed to the proof gate is now
   "delete part (a) and its gate" rather than "delete Item 2.1". The item says
   so in those words, and the hub's N7 paragraph and the requirements table both
   name `2.1 (a)`.
4. **Failure isolation.** A blocked dispatch now strands four changes rather
   than one.

**What the merge did not touch**, per your constraints:

- **All four Mutation gates of the four former items survive, separately
  stated** — (a) stray untracked file; (b) `git subtree split "$tag"` → `HEAD`;
  (c) both halves, `':(exclude).claude'` and `':(exclude)memory'` dropped
  independently; (d) `common_preflight`'s dirty-tree branch made non-fatal.
  Verified by grep: eight `Mutation gate` field lines across the node's five
  items — four in Item 2.1, one each in 3.1–3.4 — none merged into another.
- **The requirements table still resolves.** M1 → `2.1 (b)`, M3 → `2.1 (c)`, M4
  → `2.1 (d)`, N7 → `2.1 (a)`. All 6 Majors, 15 Minors and BD still map.
- **Every ordering constraint from `outline.md` "Dependencies and ordering"
  survives.** Rule 5's serialization within Phase 2 became *intra-item*
  ordering, stated as a load-bearing instruction with its failure mode: "(c)
  before (d) is the one that matters: a sweep landing first has its new
  assertions rewritten out from under it, and nothing fails when that happens."
  Item 2.1 still `Depends on:` Item 1.3 for both reasons (serialization and the
  comment consumption). Items 3.4-last, 4.6-after-Phases-1–3 and 4.7-last are
  untouched.
- **No prose file is split across items** and no two items touching different
  prose files were merged — constraint 3 is not engaged by this merge at all,
  since all four parts touch one file.
- The two former `Interfaces:` blocks (the `memory` fixture's probed contract,
  and `assert_gh_untouched`) no longer cross an item boundary, so they are
  folded into parts (c) and (d) rather than kept under a label the hub reserves
  for genuine cross-item consumption. The hub's convention paragraph says so.

## Rejected: merging Phase 1's tdd items (1.1 + 1.2)

They share both files (`toolkit/release.sh`, `tests/release-test.sh`) and 1.2
already `Depends on:` 1.1 for serialization, so the surface case is identical to
Phase 2's.

**Rejected because it saves zero dispatches.** A tdd item's cost is four
dispatches per slice; 1.1 and 1.2 have two slices each, and a merged item would
have four. 16 dispatches before, 16 after. The only saving is about six lines of
item header, against a real cost: the two items are *opposite-polarity* uses of
the same edit shape — 1.1 drops a `pipefail` dependency that was rescuing the
code, 1.2 drops one that was causing the defect — and that contrast is the thing
a reader most needs to keep straight. Merging buries it inside one item.

## Rejected: merging Phase 3's 3.2 + 3.3

Both on `tests/version-guard-test.sh`; 3.3 depends on 3.2 only by serialization.
Would save exactly one dispatch.

**Rejected because the payoff the per-file rule promises is already unreachable
on that file.** Item 3.4 must run last, and its ordering constraint fails
*silently* if violated — new assertions landing in the pre-conversion glob form
are skipped by the BRE re-check with a green suite. That constraint is worth
keeping structural, enforced by the orchestrator's phase walk rather than by
prose inside one dispatch. With 3.4 necessarily separate, no single agent holds
the file regardless, and merging 3.2 into 3.3 would only trade the item boundary
between two genuinely different kinds of work — repairing two existing assertion
defects (N4, N6) versus adding a new scenario with a new recording-stub idiom
(N5) — for one dispatch out of ~37.

I applied the same silent-failure test to Phase 2's (c)-before-(d) and it fails
it too, which is why that ordering is stated in bold in the merged item rather
than left implicit. The difference is that Phase 2's whole chain goes to one
agent that writes both halves, while 3.4's re-check has to observe work a
*different* dispatch produced.

## Rejected: merging Phase 4's inline items

The obvious pair is 4.4 (`toolkit/README.md`, one prose line) and 4.5
(`CLAUDE.md`, one hand-wrapped bullet) — different files, so constraint 3
permits it, and the Gate section already treats them as a pair.

**Rejected because inline items cost no dispatch and review routing is per-file
regardless.** `fragments/review-requirement.md` says in terms: "Batch
decomposition: when multiple files change in one task, apply proportionality
per-file … Do not collapse a batch into a single reviewer." So merging cannot
reduce reviewer dispatches. It could *increase* them — 4.5's rewrap is already
near the ≤5-net-lines self-review threshold, and adding 4.4's line to the same
item risks crossing it and converting two self-reviews into one
`edify:corrector` dispatch. The merge would be cosmetic at best, and it would
cost the 1:1 requirement traceability that makes N12 and N13 individually
verifiable at a gate the runbook already warns does not cover them.

## Hub/node seam, and the line cap

The merge net-added lines to the hub (a longer Phase 2/3 summary, the
`Interfaces:` convention note), which pushed `runbook.md` to 403 — over the cap.
Rather than compress the new material, I moved content across the seam, which is
what constraint 5 asks for:

- The **phase-typing argument** (why cluster B is `general` and not `tdd`) moved
  from the hub to the node. The hub keeps the conclusion plus a pointer, which
  is the hub/node contract this repo uses for `docs/design.md`. The argument is
  about the node's items exclusively, so the node is its proper home; the node's
  opening paragraph was updated, since it previously said the hub carries it.
- The **one-commit-per-item consequence** moved from the hub's Gate section to
  the node's Phase 2 header, where it is a fact about Item 2.1 rather than about
  the gate. The Gate keeps one clause and a pointer.

Result: hub 396 (four lines of headroom, against five before), node 261.

**This is the one number I would not call an improvement.** You asked for
consolidation that shortens the hub, and it did not — merging four items into
one removed three item headers from the *node* while the hub gained the
explanation of why. If the proof gate needs headroom, the next seam to move is
Item 4.6's four-bullet citation inventory (35 lines in the hub, entirely about
one item's targets); it would need a Phase 4 node, which is a bigger structural
change than this pass should take unprompted.

## Changed files

- `plans/2026-09-18-deliverable-review-fixes/runbook.md` — N7 paragraph, three
  requirements-table rows, the `Interfaces:` convention list, the phase-typing
  section (trimmed to a conclusion), the Phase 2/3 summary, the Gate's
  commit-bundling paragraph, and the closing open-decision pointer.
- `plans/2026-09-18-deliverable-review-fixes/runbook-test-suites.md` — header
  (five items, phase-typing argument), Phase 2 rewritten as one item in four
  parts. Phase 3 untouched.
- `plans/2026-09-18-deliverable-review-fixes/recall-artifact.md` — one
  identifier: `git-protocol-file-allow` is load-bearing for "Item 2.1 part (c)",
  not "Item 2.3". `/orchestrate` hands this file to every dispatch, so a stale
  item number there misroutes.

`reports/runbook-review.md` was **not** edited — it is a dated record, so its
"eight test-suite items" and its Item 2.2/2.3/2.4 references stay correct as of
its own date. The same goes for `outline.md`, `cluster-b-test-suites.md` and
both `proof-verdicts` files, which speak in `B1`–`B7` and are unaffected.

## For the proof gate

Two structural counts changed, so they read as regressions against the review
report unless noted:

- **15 items, not 18** — 10 `Requirements:` bullets in the hub, 5 in the node.
- **Phase 2 is one item**; the node's "five `general` items" is 1 + 4, not 8.

And two decisions are still yours, unchanged by this pass: whether to drop N7
(now part (a) of Item 2.1), and whether Item 4.6's citation convention also
belongs in `CLAUDE.md`'s Conventions.

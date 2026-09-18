# Proof verdicts — `outline.md`

Decision ledger for the `/edify:proof` item loop over `outline.md`, run under a
ralph loop that auto-accepts each proposed verdict. 14 items, the outline's own
section headings.

**Protocol per iteration:** find the first item below whose **Verdict** is `—`,
present it, propose a verdict with its reasoning, write the verdict and
reasoning into this file, stop. When every item has a verdict, apply the
accumulated `revise` edits to `outline.md` as one batch, run `just format-docs`,
confirm the 400-line cap, then emit the completion promise.

**Auto-accept caveat, recorded so it is not lost:** proof's forced verdict
normally comes from my human partner. Here it does not. What makes that
defensible is that the four items carrying a genuine fork — A2, B2, B7 and C4 —
were decided by them directly before this loop started, and their decisions are
already folded into the outline and into `classification.md`'s second decision
block. The remaining ten items are mechanical. Any item where this loop finds a
*new* fork gets verdict `skip` and is surfaced at the end rather than decided
here.

| # | Item | Verdict | Note |
|---|---|---|---|
| 1 | Scope | revise | see below |
| 2 | A1 — `release_tags()` must not rest on `pipefail` | revise | local + cross-cutting |
| 3 | A2 — hint ladder `printf \| grep -qxF` EPIPE | revise | fixture sized against the wrong string |
| 4 | A3 — `self-release.sh` tag shape | revise | names no mutation |
| 5 | B1 — dist split does not discriminate tag from `HEAD` | revise | existing comment is false, not weak |
| 6 | B2 — clean-check exemptions untested | revise | comment claims both halves |
| 7 | B3 — nine refusals assert a message and nothing else | revise | count and cited range disagree |
| 8 | B4 — two `release-test.sh` refusals under-assert | revise | tag assertion can pass vacuously |
| 9 | B5 — two `version-guard-test.sh` gaps | revise | slice 4 drops two assertions; collides with C4 |
| 10 | B6 — no allow scenario touches a git fixture | revise | **named mutation cannot go red** |
| 11 | B7 — `assert_contains` means two different things | revise | risk direction differs per assertion |
| 12 | Cluster C — prose (C1–C11) | revise | C9 records figures this pass invalidates |
| 13 | Dependencies and ordering | revise | "everything else is independent" is false |
| 14 | Gate | revise | false assurance: doc-sync covers neither C7 nor C8 |

## Item 1 — Scope — **revise**

Two edits to the Scope section.

**1. The IN line understates C4.** It reads "two stale self-citations the review
did not find (see C4)", which describes C4 as it stood before the proof gate. C4
is now a convention change applied at four sites, including
`tests/release-test.sh:1248` — a citation that is *accurate today* and is being
rewritten anyway so the repo carries one convention rather than two. A reader of
Scope alone gets no signal that the pass changes a convention binding future
edits, which is the one thing here with reach beyond the 21 findings.

**2. The Minor count reads as dropped rather than converted.** "13 of the 15
Minors" is arithmetically right, but both excluded Minors are in fact
*converted*, not dropped: the comment-volume one becomes C9's recorded bound and
the hint-count one becomes C11's stated non-fix. Scope's OUT bullets say so
individually; the IN line does not, so the two sections disagree in tone.

**Edit:** restate the IN line as — all 6 Majors; 13 of the 15 Minors fixed
directly and the remaining 2 converted to recorded bounds (C9, C11); two further
stale citations the review did not find; and a citation convention change
applied at four sites (C4).

## Item 2 — A1 — **revise**

The item's premise verified against the tree. `release_tags()` pipes into
`semver_tags`; `origin_release_tags()` immediately below already captures into a
local and reads its status, and its comment carries the full argument, ending
"That would leave this function's safety resting on one word of the `set` line
250 lines up." A1 applies that shape to the sibling. The pipefail-stripped
harness is the right vehicle and is load-bearing: under the fix, capture-then-
status refuses with or without `pipefail`, so the mutation goes red only on the
stripped copy.

**Local edit — name where the shared argument lands.** The item says to "drop
the half of `origin_release_tags`'s comment that now describes both" without
saying where that half goes. Once both callers capture, the argument stops being
about either caller: the hazard originates in `semver_tags` absorbing a no-match
grep's status 1, which is why a filter tail reports success on empty input. Move
it onto `semver_tags`'s own comment, and keep the
`Verified both ways (bash 5.2, git 2.47.3)` evidence line rather than deleting
it along with the paragraph that houses it.

**Cross-cutting edit — apply to the preamble, not to A1.** This outline cites
`release.sh:NNN` about forty times, all pinned to `8d3fbf5`, and A1 and A2 move
those lines. C4 has just established that line-number citations rot; the outline
carries the same defect it exists to fix. Rewriting forty citations is not worth
it and would itself go stale. Instead add one sentence to the preamble: the
outline's `<file>:<line>` citations are pinned to `8d3fbf5`, and any item
executing after A1 or A2 re-locates its `toolkit/release.sh` targets by symbol
rather than trusting the number. That covers A3, C1, C2 and C4 — every later
item that cites `release.sh` — in one line.

## Item 3 — A2 — **revise**

Premise verified at the site:
`if printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"; then`. Two siblings
in the same file already refuse `head -1` citing this SIGPIPE hazard by name,
and `version-guard.sh` already uses the herestring form, so the fix is the
in-repo idiom rather than a new one.

**Record the polarity, which the item blurs.** In A1, `pipefail` is what
*rescues* the code and the fix removes the dependency on it. Here `pipefail` is
what *causes* the defect — it promotes `printf`'s 141 over `grep`'s 0, so the
`if` reads a match as a no-match. Same edit shape, opposite reasons. Stating it
keeps a later reader from concluding the two items share one mechanism.

**Edit 1 — the ≥1 MB bound names the wrong string.** `$origin_tag_list` is the
*post-filter* value: `origin_release_tags` runs the raw `ls-remote` output
through `cut -f2 | sed 's|^refs/tags/||' | semver_tags` before the ladder sees
it, and the grep that must take EPIPE reads the filtered string. Measured
2026-09-18: 100000 tags yield a 1088895-byte `origin_tag_list`, but the stub
must emit **6188895 bytes** of `<oid><TAB>refs/tags/vX.Y.Z` rows to produce it —
5.7x. As written, "a ≥1 MB listing" reads as the stub's own output and
under-sizes the fixture by that factor. State both numbers and pin the ≥1 MB
bound explicitly to `$origin_tag_list`.

Record alongside it that `origin_release_tags`'s own
`printf | cut | sed | semver_tags` pipeline is safe at that size: every stage
reads to EOF, so none exits early and none can take EPIPE. `grep -q`'s early
exit is the only thing in the path that creates the hazard — which is also why
the fix is confined to one line.

**Edit 2 — name the scenario that reaches the ladder.** Line 577 sits inside the
lost-tags refusal path, reached only when the local semver listing came back
empty while origin holds tags. The item specifies the stub and the assertion but
not the surrounding fixture state that gets execution there, leaving the
implementer to reconstruct the one part that decides whether the test runs the
code at all.

## Item 4 — A3 — **revise**

Premise verified:
`latest_tag=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null) || latest_tag=""`.
Both named failure modes are live. `--match 'v*'` does match `vnext`, so a
`vnext` tag yields `die "… does not match latest tag (vnext)"` with a hint that
cannot fix it; and a release tag off `HEAD`'s ancestry leaves `latest_tag`
empty, so the `-n` test skips the drift guard entirely. The `v*` glob is
anchored, so `dist-v*` stays excluded under the replacement — the item's claim
that the squatting scenario's behaviour survives is correct.

**Edit 1 — A3 names no mutation, against the outline's own contract.** Cluster
A's preamble says each item is "one logic-path change plus the mutation that
must go red", and `classification.md` states every item's measurable criterion
is a named mutation. A1 and A2 each carry one. A3 carries "two scenarios, both
currently impossible to write" and stops. That establishes *red today* — a
different and weaker claim than detecting a regression: it says the test could
not previously have been written, not that it fails when the fix is undone.
Write the mutation down: revert to
`git describe --tags --abbrev=0 --match 'v*'`, under which both scenarios go
red.

**Edit 2 — drop the cross-file line citation.** A3 points at
`toolkit/release.sh:302-306` as where the two failure modes are spelled out — a
line number inside the file A1 is editing, and precisely the form C4 is
removing. It also leaves `self-release.sh` carrying a duplicated tag listing
whose rationale lives in another file. Have the self-release copy state the two
failure modes in its own comment instead.

**Edit 3 — say the duplication is deliberate.** `self-release.sh:8-12` justifies
sharing no code with `toolkit/release.sh`, but its argument is about not putting
"every consumer's release path behind a branch only this repo takes" — a
flow-factoring argument. A3 duplicates a three-line tag listing, which that
paragraph does not plainly cover. One clause noting the duplication is
intentional under that header stops a later reader from factoring it out.

## Items 5-11 — Cluster B

The seven Cluster B verdicts are in **`proof-verdicts-cluster-b.md`**, beside
the specs they revise.

## Item 12 — Cluster C — **revise**

Spot-verified the checkable targets. C1's header does carry "before a first
release there is no tag to desync from, but the recipe is still the only place a
version is meant to change". C3's deny does read "If the goal is to ship a
release, invoke the recipe instead". C7's line 34 does say "the latest tag".
C8's wrap is ragged at "`version-guard`), each".

**Edit 1 — C9 would record figures this same pass invalidates.** Measured
2026-09-18 and exact as written: `release.sh` 852 lines, 435 comment-only, 51%;
`version-guard.sh` 45%. But A1 and A2 edit `release.sh`, and C1 and C3 edit
`version-guard.sh`, all inside this pass. C9 writes those figures into
`docs/design.md`'s Limitations — a living, present-tense document — so it lands
a measurement already false by the time the pass commits. That is C4's defect
one layer up, and worse for sitting in the document whose contract is current
truth rather than a dated record.

Fix by splitting along the repo's own design-and-changelog convention: state the
bound in `design.md` as a proportion without false precision — "roughly half of
`release.sh` is comment-only, much of it write-time record rather than contract"
— and put the exact 852/435/51%/45% figures in C10's dated changelog entry,
where a measurement stays correct forever precisely because it is dated.

**Edit 2 — granularity, recorded rather than restructured.** Cluster A gives one
item per finding and Cluster B one per finding; Cluster C gives one item for
eleven findings across seven files (`version-guard.sh`, `version-guard.md`,
`design.md`, `recovery.md`, `README.md`, `CLAUDE.md`, `docs/changelog/`). The
asymmetry was a deliberate triage decision ("Simple, cluster C, batched") and is
not reopened here — but it does mean this single verdict covers eleven findings,
which is thin review by construction. Note in the item that `/runbook` splits
Cluster C per file rather than emitting one eleven-part dispatch.

## Item 13 — Dependencies and ordering — **revise**

"Everything else is independent" is false, and false in the way that matters
most for `/orchestrate`, which dispatches items to separate agents.

Every item mapped to the files it mutates:

- `tests/version-guard-test.sh` — **B5, B6, B7, C4**
- `tests/self-release-test.sh` — **A3, B1, B2, B3**
- `tests/release-test.sh` — A1, B4, C4
- `toolkit/release.sh` — A1, A2, C4
- `toolkit/version-guard.sh` — C1, C3

Three collisions are line-level, not merely file-level:

- **B2 ↔ B3.** B3 covers the nine refusals at `:262-309`; B2 rewrites the
  `.claude`/`memory` scenario at `:267-271`, inside that range.
- **A3 ↔ B3.** A3's "Also update" targets the squatting comment at `:296-297`;
  B3's ninth refusal is that same scenario at `:296-301`.
- **B5 ↔ C4.** Carried from item 9: C4's two stale citations
  (`release.sh:446-455`, `:456-460`) sit inside the twelve-line comment block B5
  edits.

One further constraint is not a collision but a correctness requirement:
**B7 runs last on `version-guard-test.sh`.** It converts all twenty assertion
call sites to the `grep` form, while B5 and B6 each *add* assertions to that
file. In any other order the new assertions land in the glob form, and B7's own
"re-check every needle under BRE" pass silently skips them.

**Edit — replace item 5.** The fix is the one `shared-claude` already names: a
shared mutable file rules out *parallel* agents, not sequential ones. State that
the four items on `tests/version-guard-test.sh` and the four on
`tests/self-release-test.sh` each run sequentially — ideally one agent per file
— with B7 last in its group.

## Item 14 — Gate — **revise**

Suite count verified: exactly eight files under `tests/`.

**Edit 1 — "C7 and C8 both land inside its reach" is false for both.**
`doc-sync-test.sh`'s own header settles it: "The prose differs on purpose --
audience, depth -- so only the commands are compared: every fenced block in the
root README's install/update sections must appear verbatim in the toolkit
README's." C7 is a prose line in a component bullet at `toolkit/README.md:34` —
not a fenced block, not inside the install or update sections. Doc-sync cannot
see it. C8 is `CLAUDE.md`'s `docs/references/*.md` bullet; check 2 extracts
`` `toolkit/...` `` tokens by `grep -oE`, and that bullet holds no `toolkit/`
path, so it passes trivially rather than being checked.

Both fixes are real and both land. But the Gate tells an implementer that
`just precommit` catches a mistake in them, and it does not — the same
false-assurance defect this pass exists to fix, in the section that certifies
the pass. Say instead that C7 and C8 are verified by reading.

**Edit 2 — name the hand-wrap hazard in C8.** `just format-docs` covers `docs/`
and `plans/` only, so C8's re-wrap is done by hand with no formatter guarantee.
Doc-sync's check 2 is token-based rather than line-based and so survives
re-wrapping — unless a wrap splits a backticked `` `toolkit/...` `` path across
a newline, which drops it from the documented set and surfaces as a spurious
"undocumented shipped file". The general form is in memory as
`markdown-formatter-choice`: wrapping breaks line-grepping doc checkers.

The `commit-bundling` paragraph is correct as written and needs no change.

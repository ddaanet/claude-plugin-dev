# Outline — deliverable-review fix pass

Fixes the findings of
`plans/2026-09-15-first-release-version/reports/deliverable-review.md` (Critical
0, Major 6, Minor 15) against `8d3fbf5`, tree clean. Every Major was re-verified
against current code during triage; none is stale. Classification, the four
triage decisions and the five taken at the proof gate are in `classification.md`
beside this file; the item-by-item proof verdicts are in `proof-verdicts.md`.

**Citations are pinned to `8d3fbf5`.** The `<file>:<line>` references below were
correct at that commit, and A1 and A2 move lines inside `toolkit/release.sh`.
Any item executing after those two re-locates its `toolkit/release.sh` targets
by symbol rather than trusting the number. References into frozen dated
artifacts — the executed `outline.md`, the review report — keep their line
numbers and stay correct, per C4.

Three clusters: **A** production code (3 items, each a logic path), **B** test
suites (7 items, each a fixture that currently cannot fail), **C** prose (11
items). A and B are tdd-shaped; C is inline.

## Scope

**IN** — all 6 Majors; 13 of the 15 Minors fixed directly, with the remaining 2
converted to recorded bounds rather than dropped (C9, C11); two further stale
citations the review did not find; and a **citation convention change** applied
at four sites (C4), which is the one change here that binds future edits.

**OUT**, with the reason:

- Cutting `toolkit/release.sh`'s write-time-record comment blocks (`:502-519`,
  `:245-257`, `:322-336`). Triage decision 2: the comments are accurate, the
  repo's comment philosophy is deliberate, and nothing currently measures source
  files — inventing a cap here is a wider decision than this pass. C9 records
  the volume as a bound instead.
- `outline.md:262`'s three-vs-four hint count. Triage decision 4: the executed
  outline is a dated artifact and the review report already carries the
  correction. C11 states this so a later pass does not re-open it.
- `/gitlore:push` for this repo's memory store, `memory/MEMORY.md`'s loader cap
  (`/gitlore:index-audit`), the three facts the cap left unwritten, and the
  unreproduced `tests/release-test.sh` failure of 2026-09-17. All are named in
  the task frame and none is a deliverable-review finding.

## Cluster A — production code

Each item is one logic-path change plus the mutation that must go red.

### A1 — `release_tags()` must not rest on `pipefail` (Major 2)

`toolkit/release.sh:297-308`. Today the body is
`git tag --list 'v*' --sort=-v:refname | semver_tags`. `semver_tags` absorbs a
no-match grep's status 1, so the pipeline's last stage reports success on empty
input and `git tag`'s failure reaches the caller only through `set -o pipefail`.

**Change:** capture the listing into a local and read *its* status, then filter
— the shape `origin_release_tags` already uses at `:337-345`. Rewrite the
function comment to say the safety no longer depends on the `set` line, and move
the half of `origin_release_tags:322-336` that now describes both
**onto `semver_tags`'s own comment** — once neither caller pipes, the hazard
belongs to the filter that absorbs the status, not to either caller. Keep the
`Verified both ways (bash 5.2, git 2.47.3)` evidence line; it moves with the
argument.

**Test:** extend the pipefail-stripped harness at `tests/release-test.sh:1427`
to a second scenario. A `git` wrapper on `PATH` — the stub idiom
`version-guard-test.sh` already uses for `guard_stub127_dir` — exits non-zero
for `tag --list` and delegates everything else to the real binary. Under the
stripped copy, `just release <bump>` must refuse and must not tag `HEAD`.

**Mutation that must go red:** restore the pipe. Under the stripped copy the
`|| die` at `:355` stops firing, `:377` takes the lost-tags branch,
`first_release=1` at `:471`, and `bump_commit_tag` tags `HEAD` — publishing the
manifest version of a plugin whose release history it could not read.

### A2 — the hint ladder's `printf | grep -qxF` can read a match as no-match

`toolkit/release.sh:577`. `grep -qxF` exits on first match; under `pipefail`
`printf`'s EPIPE becomes the pipeline status. Verified in the review at 200 000
lines, match on line 1, status 141. Two other sites in the same file avoid
`head -1` citing this exact hazard (`:383-384`, `:495-497`).

**Change:** `grep -qxF -- "$tag" <<<"$origin_tag_list"` — a herestring, no pipe,
so there is no EPIPE and no pipefail dependency. `version-guard.sh:139` is the
in-repo precedent.

**Scenario:** the fixture must reach the ladder, which sits inside the lost-tags
refusal path — entered only when the local semver listing came back empty while
origin holds tags. That surrounding state is part of the item: it decides
whether the test runs the code at all.

**Test:** a `git` stub whose `ls-remote --tags` emits synthetic rows with the
match first — ~8000 real `git tag` calls costs minutes, the stub one
`seq`-driven `printf`. Assert branch 1 fires ("origin already has <tag>", the
`git fetch --tags` remedy), not branch 2's `just release <bump>`.

**Size the *post-filter* string.** The ≥1 MB bound is on `$origin_tag_list`,
what `grep` reads — not on the stub's output, which `origin_release_tags` first
runs through `cut -f2 | sed 's|^refs/tags/||' | semver_tags`. Measured: 100000
tags give a 1088895-byte `$origin_tag_list`, needing **6188895 bytes** of
`<oid><TAB>refs/tags/vX.Y.Z` rows — 5.7x, so sizing the stub to 1 MB under-sizes
the fixture by that factor. ≥1 MB rather than the measured GNU grep 3.11
boundary (~96 KiB) because the threshold is the pipe buffer *plus* grep's read
buffer and so varies by implementation — ugrep 7.8.4 needed ~500 KB.
`origin_release_tags`'s own pipeline is safe at any size: every stage reads to
EOF, so only `grep -q`'s early exit creates the hazard. Full measurements in
`proof-verdicts.md`.

**Mutation that must go red:** restore the pipe. Polarity is opposite to A1 —
there `pipefail` rescues the code and the fix drops the dependency; here
`pipefail` *causes* the defect by promoting `printf`'s 141 over `grep`'s 0. Same
edit shape, opposite reasons.

### A3 — `self-release.sh` uses the tag shape `release.sh` documents as wrong

`scripts/self-release.sh:105-117`. `git describe --tags --abbrev=0 --match 'v*'`
sees only tags reachable from `HEAD` and returns the *nearest* of any matching
name, not the newest — the two failure modes `release_tags` in
`toolkit/release.sh` spells out for its own callers.

**Change:** list and filter. `git tag --list 'v*' --sort=-v:refname`, keep lines
matching `^v[0-9]+\.[0-9]+\.[0-9]+$`, take the first. Capture-then-filter, not a
pipe, for A1's reason. State the two failure modes in `self-release.sh`'s
**own** comment rather than pointing at `release.sh` — a cross-file line
citation into the file A1 is editing is exactly the form C4 removes. No code is
shared with `toolkit/release.sh`: that separation is deliberate
(`self-release.sh:8-12`) and this item does not touch it, so say in the comment
that duplicating a three-line tag listing is intentional under that header — the
paragraph there argues against factoring the *flow*, and a reader could
otherwise take this for an oversight.

**Tests:** two scenarios, both currently impossible to write.

1. A `vnext` tag on `HEAD`'s ancestry must not be read as the latest release.
   Today it yields `die "… does not match latest tag (vnext)"` with a hint that
   cannot fix it.
2. A release tag *off* `HEAD`'s ancestry — tagged on a since-abandoned branch —
   must still be seen. Today `latest_tag` comes back empty and the drift guard
   at `:112` is skipped entirely.

**Mutation that must go red:** revert to
`git describe --tags --abbrev=0 --match 'v*'`. Both scenarios above fail under
it. Naming this matters because "currently impossible to write" establishes only
that the tests could not have existed before — a weaker claim than detecting a
regression, and Cluster A's contract is the latter.

**Also update:** `tests/self-release-test.sh:296-297`, whose comment explains
the dist-tag-squatting scenario in terms of `describe --match 'v*'`. The
scenario's behaviour survives — the `v*` glob still excludes `dist-v*` — but the
stated reason does not.

## Cluster B — test suites

Seven items, each a fixture that currently cannot fail. Split to its own node
for length: **`cluster-b-test-suites.md`**. Ordering constraints that involve
them stay in Dependencies below.

## Cluster C — prose

Inline items. C1 and C3 touch the same file; C4 must land after A1 and A2.

Eleven findings across seven files sit in this one item, where clusters A and B
give one item per finding. That asymmetry is triage decision "Simple, cluster C,
batched" and is not reopened — but `/runbook` splits Cluster C **per file**
rather than emitting a single eleven-part dispatch.

- **C1 (Major 6)** — `toolkit/version-guard.sh:3-7`. The header's clause "before
  a first release there is no tag to desync from, but the recipe is still the
  only place a version is meant to change" is false under this plan. The same
  file's deny message (`:151-154`), `toolkit/release.sh:476-479`,
  `toolkit/README.md:181-186` and `docs/design.md:109-110` all record that on a
  first release the version legitimately changes by the maintainer's committed
  hand edit. Restate the header for both cases, which the executed
  `outline.md:126-127` asked for and which landed only half-done. Shipped file:
  a maintainer reading it concludes the opposite of what the plan exists to
  establish.
- **C2 (Major 5)** — `docs/references/version-guard.md:44-48`. The predicate
  clause is true; the conclusion "the hook and the recipe cannot disagree about
  which state a repo is in" is not. `version-guard.sh:124` lists **local** tags
  only; `release_preflight` probes origin when the local list is empty
  (`toolkit/release.sh:377-403`). On a lost-tags clone the recipe refuses with
  the `git fetch --tags` hint while the hook takes the initial-release branch.
  Local-only is correct for a `PreToolUse` hook — this is a bound to record
  beside the listing bound at `:132-134`, not a defect to close.
  `docs/design.md:187` already carries the defensible weaker form.
- **C3 (Minor 15)** — `toolkit/version-guard.sh:170-171`. "If the goal is to
  ship a release, invoke the recipe instead" is `if … then` phrasing in an
  agent-facing deny. The freeze at the executed `outline.md:126` was scoped to a
  plan that has shipped. **Narrower than it looks:** the steady-state branch
  names the recipe *legitimately* — `version-guard-test.sh:344` says so and
  `:347` asserts `just release` absent only from the no-tags reason. Fix the
  conditional framing; do not remove the identifier from the steady-state
  message. The initial-release branch (`:149-157`) is the model, and
  `craft:directive-writing` is the rule.
- **C4 (Minor 9, grown)** — a whole-tree sweep of `<script>.sh:<line>` citations
  found four hits, three of them stale. The review reported one.
  - `toolkit/release.sh:254` cites `:780-785` for "release_preflight never runs
    on resume"; the mode dispatch is `:837-843` and `:780-785` is the
    marketplace commit-gate rollback. **Stale.**
  - `tests/version-guard-test.sh:340` cites `release.sh:446-455` for a bump
    argument being refused on an unreleased plugin; that range is the version-
    drift refusal. The claim lives at `:472-481`. **Stale.**
  - `tests/version-guard-test.sh:341` cites `release.sh:456-460` for a bare
    `just release` publishing `$current`; that range is a `die` plus the resume
    hint. The claim lives at `:470-486` and `:618-626`. **Stale.**
  - `tests/release-test.sh:1248` cites `release.sh:138` for the dirty-tree
    refusal preceding `release_preflight`. **Accurate today.**

  **Decision taken 2026-09-18: convert all four sites to unambiguous line
  context and drop the line numbers.** Repairing the three numbers buys
  citations that rot inside this same pass — A1 and A2 both shift
  `toolkit/release.sh` again. The failure mode is not a dangling pointer: each
  of the three lands on *different real code*, so a reader who follows one gets
  a confident wrong answer rather than an error.

  The replacement form is the enclosing symbol plus a short quoted fragment of
  the cited line — e.g. "`release.sh`, the mode dispatch in `main`, the
  `--resume` branch" — not a bare function name, which loses precision in a long
  function. `tests/release-test.sh:1248` converts too, so the repo carries one
  convention rather than two.

  Citations *into frozen dated artifacts* keep their line numbers and are out of
  scope: an executed `outline.md`, a runbook, a review report and a changelog
  entry are never revised, so the number stays permanently correct. That
  exception covers this outline's own `outline.md:NNN` references.

  **Recorded upstream, no follow-up held here:** a brief at
  `../edify/inbox/brief-cite-line-context-not-line-numbers.md` proposes the same
  convention for `/design`'s outline guidance and for tightening `/runbook`'s
  existing "file:function or file:line" bullet. Dropping it is the end of this
  repo's involvement.
- **C5 (Minor 10)** — `docs/design.md:186-192` and `:135-140` carry the nodes'
  arguments (the non-blocking-exit mechanism; the three push-route keys and the
  `pushInsteadOf` bound) against the hub's own one-conclusion-per-decision
  contract at `:7-12` and `:63-67`. Both arguments already live at
  `version-guard.md:83-90` and `recovery.md:216-258`. Trim the hub to its
  conclusions.
- **C6 (Minor 11)** — partial tag loss is recorded in the executed outline's
  Scope/OUT and in neither `docs/references/recovery.md` nor `docs/design.md`.
  The symmetric bound on the adjacent check (`url.<base>.pushInsteadOf`) *is* in
  both, which makes the omission read as coverage. Record it in both.
- **C7 (Minor 12)** — `toolkit/README.md:34` says "the latest tag" where the
  file's own Conventions bullet sixty lines later says the `vX.Y.Z` tag. The
  only shipped manual a consumer reads.
- **C8 (Minor 13)** — `CLAUDE.md:73-76` carries a ragged wrap.
  `just format-docs` runs rumdl over `docs/` and `plans/` only. Hand-wrap it;
  widening the recipe over `CLAUDE.md` is a separate decision and not this
  pass's to take.
- **C9 (Minor 14)** — record the bound triage decision 2 left standing: nothing
  measures source files, and three blocks in `toolkit/release.sh` are write-time
  record rather than contract. One line in `docs/design.md`'s Limitations,
  naming it as accepted rather than unnoticed.

  **State it as a proportion, without figures.** This pass edits both files
  (A1/A2, C1/C3), so exact counts would be false on the commit that lands them —
  C4's defect one layer up, in a living present-tense document. Write "roughly
  half of `release.sh` is comment-only, much of it write-time record rather than
  contract" in the hub, and put the measured numbers in C10's **dated**
  changelog entry, where a measurement stays correct because it carries its
  date.
- **C10** — a dated write-time record at
  `docs/changelog/2026-09-18-deliverable-review-fixes.md` plus its index line in
  `docs/changelog.md`, per the repo's design-and-changelog convention. It also
  carries C4's convention change — source citations name unambiguous line
  context rather than line numbers, with frozen dated artifacts exempt — since
  that binds future edits and is not derivable from the diff.
- **C11** — no deliverable changes for the baseline defect. State in C10's
  record that `outline.md:262`'s three-hint count was left standing
  deliberately, so a later pass does not re-open it as an unfixed finding.

## Dependencies and ordering

1. **A1 and A2 before C4 — weakened, not dropped.** C4 no longer emits line
   numbers, so the shifts A1 and A2 cause can no longer invalidate it. What
   still orders them is content: C4 must name the mechanism as A1 and A2 leave
   it, and A1 rewrites the `release_tags` comment C4's first citation is
   adjacent to. Ordering is preferred, not required.
2. **A3 before the `tests/self-release-test.sh:296-297` comment update**, which
   is part of A3's own item.
3. **C1 before C3** — same file, adjacent prose, and C3's scope depends on C1's
   restatement landing first.
4. **B2 no longer needs special scheduling.** The submodule fixture was probed
   and is ~6 lines; it depends on nothing and blocks nothing.
5. **Items sharing a file run sequentially, never in parallel.** Four items
   touch `tests/version-guard-test.sh` (B5, B6, B7, C4) and four touch
   `tests/self-release-test.sh` (A3, B1, B2, B3); `tests/release-test.sh` has
   three (A1, B4, C4), `toolkit/release.sh` three (A1, A2, C4) and
   `toolkit/version-guard.sh` two (C1, C3). Prefer one agent per file over one
   per item. Three of these overlap at the line level, not merely the file:
   - **B2 ↔ B3** — B3 covers the refusals at `:262-309`; B2 rewrites the
     `.claude`/`memory` scenario at `:267-271`, inside it.
   - **A3 ↔ B3** — A3's comment update targets `:296-297`; B3's squatting
     refusal is that same scenario at `:296-301`.
   - **B5 ↔ C4** — C4's two stale citations sit inside the comment block B5
     edits.
6. **B7 runs last on `tests/version-guard-test.sh`.** It converts all twenty
   assertion call sites to the `grep` form while B5 and B6 each *add* assertions
   to that file. In any other order the new assertions land in the glob form and
   B7's BRE re-check silently skips them.

## Gate

`just precommit` must be green before each commit — it runs all eight suites,
`_import-check`, the 400-line cap, the doc-sync check, `whitespace` and
`format-docs`.

**Doc-sync does not cover C7 or C8 — verify both by reading.** It compares only
*fenced command blocks* in the two READMEs' install/update sections, and C7 is a
prose line in a component bullet; its second check extracts `` `toolkit/...` ``
tokens from `CLAUDE.md`, and C8's target bullet holds none, so it passes
trivially rather than being checked. Claiming the gate catches these would be
this pass's own false-assurance defect, in the section that certifies the pass.

C8 also carries a hazard no gate guards: `format-docs` covers `docs/` and
`plans/` only, so its re-wrap is by hand, and doc-sync's token extraction
survives re-wrapping **unless** a wrap splits a backticked `` `toolkit/...` ``
path across a newline — which drops it silently and surfaces as a spurious
"undocumented shipped file".

Per `commit-bundling`, each code change rides with the test that proves it and
with the comment that documents it — no carve-outs, and nothing dropped
silently.

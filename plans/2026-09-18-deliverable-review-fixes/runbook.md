# Runbook — deliverable-review fix pass

Design: `outline.md` (scope, clusters A and C, ordering, gate) and
`cluster-b-test-suites.md` (the seven test-suite items) beside this file.
Decisions: `classification.md`. Evidence: `proof-verdicts.md`,
`proof-verdicts-cluster-b.md`.

**This file is the hub.** Phases 2 and 3 — the eight test-suite items — are in
[`runbook-test-suites.md`](runbook-test-suites.md), split out for the repo's
400-line cap the way the design split cluster B. Requirements source:
`plans/2026-09-15-first-release-version/reports/deliverable-review.md` — 6 Major
(`M1`–`M6`), 15 Minor (`N1`–`N15`), one baseline defect (`BD`).

**Citations are pinned to `8d3fbf5`**, which is still the state of every
production file. Items 1.1 and 1.2 move lines inside `toolkit/release.sh`; any
later item re-locates its targets in that file by enclosing symbol, per the C4
convention this pass establishes.

**One coverage gap the outline does not carry: `N7`.** The review's seventh
Minor — `tests/self-release-test.sh`'s happy-path `tree left dirty` check is
tracked-only, so an untracked leftover passes — is assigned to no outline item.
It is the same root cause as `M3` (B2) at a different site. Carried here as
**Item 2.1**; if it should be dropped instead, that is a scope decision to take
at `/proof` rather than silently.

**Field lines are nested bullets, not continuation lines.** `just format-docs`
runs rumdl with MD013 reflow over `plans/`, which joins continuation lines into
one paragraph and would merge `Requirements:`, `Model:` and `Change:` into
running prose. Nested bullets survive the reflow.

## Requirements mapping

| Requirement | Outline item | Phase | Items | Notes |
|---|---|---|---|---|
| M1 dist split does not discriminate | B1 | 2 | 2.2 | |
| M2 `release_tags()` rests on `pipefail` | A1 | 1 | 1.1 | |
| M3 clean-check exemptions untested | B2 | 2 | 2.3 | |
| M4 ten refusals assert a message only | B3 | 2 | 2.4 | |
| M5 `version-guard.md` parity claim | C2 | 4 | 4.2 | |
| M6 `version-guard.sh` header contradicts | C1 | 4 | 4.1 | |
| N1 `printf \| grep -qxF` EPIPE | A2 | 1 | 1.2 | |
| N2 `self-release.sh` `git describe` | A3 | 1 | 1.3 | |
| N3 two `release-test.sh` refusals under-assert | B4 | 3 | 3.1 | |
| N4 `tagless_sysmsg` reads a stale `guard_out` | B5 | 3 | 3.2 | |
| N5 no allow scenario touches a git fixture | B6 | 3 | 3.3 | |
| N6 `vnext` half omits two assertions | B5 | 3 | 3.2 | |
| N7 happy-path dirty check is tracked-only | — | 2 | 2.1 | **Not in the outline** |
| N8 `assert_contains` harness divergence | B7 | 3 | 3.4 | |
| N9 stale `<script>.sh:<line>` citations | C4 | 4 | 4.6 | Grown 1 → 3 by sweep |
| N10 hub carries the node's argument | C5 | 4 | 4.3 | |
| N11 partial tag loss unrecorded | C6 | 4 | 4.3 | |
| N12 `README.md` "the latest tag" | C7 | 4 | 4.4 | |
| N13 `CLAUDE.md` ragged wrap | C8 | 4 | 4.5 | |
| N14 comment volume | C9 | 4 | 4.3 | Recorded as a bound, not cut |
| N15 `if … then` phrasing in a deny | C3 | 4 | 4.1 | |
| BD `outline.md:262` hint count | C11 | 4 | 4.7 | Left standing, stated so |

**Out of scope, per `outline.md` Scope/OUT:** cutting `release.sh`'s
write-time-record comment blocks; editing the executed `outline.md`;
`/gitlore:push`, `memory/MEMORY.md`'s loader cap and the facts queued behind it;
the unreproduced `release-test.sh` failure of 2026-09-17.

## Phase typing — one deviation from the outline

The outline types cluster B as tdd.
**Phase 2 and Phase 3 are `general` instead.** A cluster B item strengthens a
fixture whose assertions pass against *unchanged* production code; the
discrimination is proven by applying the item's named mutation, not by a failing
assertion on the current tree. A `tdd` dispatch's RED step would have nothing to
fail on. Each item therefore carries an explicit **Mutation gate** — the edit to
apply, the assertion that must fail under it, and the revert — which the
executor runs and reports before committing. Cluster A is genuine tdd and keeps
its type.

## `Depends on:` carries two kinds here

Most dependencies in this pass are **serialization**, not consumption: two items
edit the same file and must not run in parallel, per `outline.md` Dependencies
rule 5. Those carry no `Interfaces:` block, because nothing crosses between them
but the file's state. An `Interfaces:` block appears only where a later item
genuinely reads an earlier item's output — Items 1.1, 2.3, 2.4, 3.2 and 3.4.

## Phase 1: production logic paths (type: tdd)

- **Item 1.1:** `toolkit/release.sh` + `tests/release-test.sh` —
  `release_tags()` captures the listing and reads its own status instead of
  piping into `semver_tags`.
  - Requirements: M2
  - Model: sonnet
  - Change: rewrite `release_tags`'s body to the capture-then-filter shape
    `origin_release_tags` already uses — assign
    `git tag --list 'v*' --sort=-v:refname` to a local, **`|| return 1`** on its
    status, then filter the local through `semver_tags`. `return`, not `die`:
    both call sites already handle a non-zero status — `release_preflight`'s
    `|| die "could not list this plugin's release tags — nothing was done"`, and
    `resume_preflight`'s `if release_tag_list=$(release_tags) && …`, whose
    comment requires a failed listing to fall through to the last branch "whose
    advice is safe either way". A `die` here runs in the substitution's
    subshell, so it would not abort the script — it would print a second
    `error:` line into the middle of a hint ladder the code keeps deliberately
    non-fatal. Rewrite `release_tags`'s comment to say the safety no longer
    depends on the `set -o pipefail` line, and move the half of
    `origin_release_tags`'s comment that now describes both callers onto
    **`semver_tags`'s own** comment — once neither caller pipes, the hazard
    belongs to the filter that absorbs grep's status. Carry the
    `Verified both ways (bash 5.2, git 2.47.3)` evidence line across with the
    argument it supports.
  - Slices:
    1. The stripped copy refuses. Extend the
       `=== the origin probes fail closed with pipefail stripped ===` harness at
       the end of `tests/release-test.sh` with a second scenario: a `git`
       wrapper first on `PATH` that exits 1 for `tag --list` and `exec`s the
       real binary for everything else — the `guard_stub127_dir` stub idiom from
       `tests/version-guard-test.sh`. Test
       `pipefail-stripped release_tags failure refuses`: asserts `rc` is 1, that
       `$out` contains `could not list this plugin's release tags` — the needle
       is `release_preflight`'s existing `die`, since the stub prints nothing of
       its own — and `assert_not_contains "$out" "git fetch --tags"` — the
       lost-tags remedy is the wrong branch and its presence is the defect.
    2. It publishes nothing. Test
       `pipefail-stripped release_tags failure publishes nothing`: asserts the
       plugin's local tag set equals the fixture's (a set comparison, not a
       named refutation — which tag the code would create is itself under test),
       the origin tag set is unchanged, and `$(cat "$GH_LOG")` is empty.
  - Mutation that must go red: restore
    `git tag --list 'v*' --sort=-v:refname | semver_tags`. Under the stripped
    copy `release_preflight`'s `|| die` stops firing, the lost-tags branch is
    taken, `first_release=1`, and `bump_commit_tag` tags `HEAD` — publishing the
    manifest version of a plugin whose release history it could not read.
  - Interfaces:
    - `release_tags()` — writes the newline-separated semver tag list to stdout,
      newest first; returns 1 on a failed `git tag --list` rather than returning
      empty with status 0. Both call sites keep the handling they already have.
    - `semver_tags()` — filter, reads stdin; its comment is now the single home
      of the "absorbs a no-match grep's status" hazard note.

- **Item 1.2:** `toolkit/release.sh` + `tests/release-test.sh` — the resume hint
  ladder's origin-tag membership test drops its pipe.
  - Requirements: N1
  - Depends on: Item 1.1 (serialization — same file)
  - Model: sonnet
  - Change: in `resume_preflight`'s hint ladder, replace
    `printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"` with
    `grep -qxF -- "$tag" <<<"$origin_tag_list"`. A herestring has no pipe, so no
    EPIPE and no `pipefail` dependency. The in-repo herestring precedent is
    `toolkit/version-guard.sh`'s tag filter, `grep -E '…' <<<"$listing"` — a
    herestring, not a pipe; the `-qxF` flags are this site's own and carry over
    unchanged. **Locate the site by symbol**, not by `:577` — Item 1.1 has moved
    it.
  - Slices:
    1. The ladder is reached and branch 1 fires. The site sits inside the
       lost-tags refusal path, entered only when the local semver listing is
       empty while origin holds tags, so constructing that state is part of the
       test. With a `git` stub whose `ls-remote --tags` emits a handful of
       synthetic `<oid><TAB>refs/tags/vX.Y.Z` rows with the matching tag first,
       test `resume hint names the tag already on origin`: asserts `$out`
       contains `origin already has v<tag>` and the `git fetch --tags` remedy,
       and `assert_not_contains "$out" "just release"` — branch 2 is the wrong
       answer.
    2. It still fires when the listing is large. Same stub, sized so the
       **post-filter** `$origin_tag_list` is ≥1 MB. The bound is on what `grep`
       reads, not on the stub's output: `origin_release_tags` first runs the
       rows through `cut -f2 | sed 's|^refs/tags/||' | semver_tags`, and 100000
       tags give a 1088895-byte `$origin_tag_list` from 6188895 bytes of rows —
       5.7x, so sizing the stub to 1 MB under-sizes the fixture by that factor.
       Drive the rows from one `seq`-backed `printf`; ~8000 real `git tag` calls
       costs minutes. Test `resume hint names the tag already on origin at 1MB`:
       same two assertions as slice 1. ≥1 MB rather than the measured GNU grep
       3.11 boundary (~96 KiB) because the threshold is the pipe buffer *plus*
       grep's read buffer and varies by implementation — ugrep 7.8.4 needed ~500
       KB.
  - Mutation that must go red: restore the pipe. Polarity is opposite to Item
    1.1 — there `pipefail` rescued the code and the fix drops the dependency;
    here `pipefail` *causes* the defect by promoting `printf`'s 141 over
    `grep`'s 0.

- **Item 1.3:** `scripts/self-release.sh` + `tests/self-release-test.sh` —
  `release_preflight` lists and filters tags instead of `git describe`.
  - Requirements: N2
  - Model: sonnet
  - Change: replace `git describe --tags --abbrev=0 --match 'v*'` with
    `git tag --list 'v*' --sort=-v:refname` captured into a local, filtered to
    lines matching `^v[0-9]\+\.[0-9]\+\.[0-9]\+$`, first line taken.
    Capture-then-filter, not a pipe, for Item 1.1's reason. State the two
    failure modes in `self-release.sh`'s **own** comment rather than pointing at
    `release.sh` — a cross-file line citation into the file Item 1.1 edits is
    exactly the form Item 4.6 removes. Say in that comment that duplicating a
    three-line tag listing is intentional under the separation header at the top
    of `self-release.sh`: that paragraph argues against factoring the *flow*,
    and a reader could otherwise take this for an oversight.
  - Slices:
    1. A `vnext` tag on `HEAD`'s ancestry is not read as the latest release.
       Test `self-release: vnext on ancestry is not the latest tag`:
       `new_sandbox` already leaves `v0.1.0` on the only commit with
       `toolkit/VERSION` at `0.1.0`, so the fixture adds one ordinary commit and
       tags **it** `vnext` — `v0.1.0` then sits on `HEAD~` and `vnext` on
       `HEAD`. `run minor` must reach a release: asserts `rc` is 0,
       `assert_tag v0.2.0 local`, and
       `assert_not_contains "$out" "does not match latest tag"`. Today
       `describe` returns the nearest tag of any name — `vnext` — and the drift
       guard refuses with `does not match latest tag (vnext)`, a hint that
       cannot fix it.
    2. A release tag off `HEAD`'s ancestry is still seen. Test
       `self-release: release tag off ancestry still triggers drift guard`:
       fixture creates `v0.9.0` on a commit not reachable from `HEAD` and leaves
       `toolkit/VERSION` at `0.1.0`; asserts `rc` is 1 and `$out` contains
       `does not match latest tag (v0.9.0)`. Today `describe` sees only the
       reachable `v0.1.0`, which matches `toolkit/VERSION`, so the guard passes
       and the release proceeds — the newer tag is invisible, not merely
       unranked. The review's "`latest_tag` comes back empty" describes a repo
       with *no* reachable tag; keep `v0.1.0`, which
       `require_prior_release_published` downstream needs.
  - Also update: the dist-tag-squatting scenario's comment in
    `tests/self-release-test.sh`, which explains the scenario in terms of
    `describe --match 'v*'`. The behaviour survives — the `v*` glob still
    excludes `dist-v*` — but the stated reason does not.
  - Mutation that must go red: revert to
    `git describe --tags --abbrev=0 --match 'v*'`. Both slices fail under it.
    Naming this matters: "currently impossible to write" establishes only that
    the tests could not have existed before, which is weaker than detecting a
    regression, and cluster A's contract is the latter.

## Phases 2 and 3: test-suite discrimination (type: general)

Eight items across three test suites, split to their own node for length:
**`runbook-test-suites.md`**. Phase 2 is the four items on
`tests/self-release-test.sh` (2.1 N7, 2.2 M1, 2.3 M3, 2.4 M4); Phase 3 is 3.1 on
`tests/release-test.sh` (N3) and 3.2–3.4 on `tests/version-guard-test.sh`
(N4/N6, N5, N8). Each carries a Mutation gate in place of slices.

The ordering constraints that cross into Phase 1 and Phase 4 stay here: Item 2.1
follows Item 1.3 and Item 3.1 follows Item 1.2 (same file, serialization); Item
2.4 also consumes Item 1.3's comment update; Item 3.4 runs last on
`tests/version-guard-test.sh`, before Item 4.6 touches its comments.

## Phase 4: prose (type: inline)

Executed by the orchestrator. Split per file rather than one eleven-part
dispatch, per `outline.md`. Item 4.6 runs after Phases 1–3; Item 4.7 runs last.

- **Item 4.1:** `toolkit/version-guard.sh` — restate the header for both release
  cases and drop the conditional framing from the steady-state deny.
  - Requirements: M6, N15
  - M6: the header clause "before a first release there is no tag to desync
    from, but the recipe is still the only place a version is meant to change"
    is false under this plan. The same file's deny message, `release.sh`'s
    first-release branch, `toolkit/README.md` and `docs/design.md` all record
    that on a first release the version legitimately changes by the maintainer's
    committed hand edit. Restate for both cases. This is a shipped file: a
    maintainer reading it concludes the opposite of what the plan exists to
    establish.
  - N15: "If the goal is to ship a release, invoke the recipe instead" is
    `if … then` phrasing in an agent-facing deny. **Narrower than it looks** —
    the steady-state branch names the recipe *legitimately*, and
    `tests/version-guard-test.sh` asserts `just release` absent only from the
    no-tags reason. Fix the conditional framing; do not remove the identifier
    from the steady-state message. The initial-release branch is the model and
    `craft:directive-writing` is the rule.
  - M6 lands before N15 — N15's scope depends on the restatement.
  - **Both deny reasons are an asserted surface.** M6 edits the file header,
    which nothing asserts; N15 edits the steady-state reason, which
    `tests/version-guard-test.sh` reads through
    `assert_contains "last released version"` and `assert_no_escape_hatch` (the
    no-bypass sentence present, no `settings.json` and no `version-guard`
    identifier). By Phase 4 those call sites are in Item 3.4's `grep -q --` form
    and the `vnext` block carries Item 3.2's additions. Keep every needle
    satisfied and re-run the suite; the gate would catch a break, but the
    constraint is the item's, not the gate's.

- **Item 4.2:** `docs/references/version-guard.md` — record the hook/recipe
  bound.
  - Requirements: M5
  - The predicate clause is true; the conclusion "the hook and the recipe cannot
    disagree about which state a repo is in" is not. The hook lists **local**
    tags only, while `release_preflight` probes origin when the local list is
    empty, so on a lost-tags clone the recipe refuses with the
    `git fetch --tags` hint while the hook takes the initial-release branch.
    Local-only is correct for a `PreToolUse` hook — record this as a bound
    beside the existing listing bound, not as a defect to close.
    `docs/design.md` already carries the defensible weaker form.

- **Item 4.3:** `docs/design.md` and `docs/references/recovery.md` — trim the
  hub to conclusions, record partial tag loss in both, record the comment-volume
  bound.
  - Requirements: N10, N11, N14
  - N10: the hub carries the nodes' arguments (the non-blocking-exit mechanism;
    the three push-route keys and the `pushInsteadOf` bound) against its own
    one-conclusion-per-decision contract. Both arguments already live in
    `version-guard.md` and `recovery.md`. Trim.
  - N11: partial tag loss is recorded in the executed outline's Scope/OUT and in
    neither `recovery.md` nor `design.md`, while the symmetric bound on the
    adjacent `url.<base>.pushInsteadOf` check *is* in both — which makes the
    omission read as coverage. Record it in both.
  - N14: one line in `design.md`'s Limitations naming the comment volume as
    accepted rather than unnoticed.
    **State it as a proportion, without figures** — this pass edits both
    `release.sh` and `version-guard.sh`, so exact counts would be false on the
    commit that lands them, which is N9's defect one layer up in a living
    present-tense document. Write "roughly half of `release.sh` is comment-only,
    much of it write-time record rather than contract"; the measured numbers go
    in Item 4.7's dated entry.

- **Item 4.4:** `toolkit/README.md` — the component bullet says "the latest tag"
  where the file's own Conventions bullet sixty lines later says the `vX.Y.Z`
  tag.
  - Requirements: N12
  - The only shipped manual a consumer reads.

- **Item 4.5:** `CLAUDE.md` — hand-wrap the ragged bullet.
  - Requirements: N13
  - `just format-docs` runs rumdl over `docs/` and `plans/` only, so nothing
    reflows this; widening the recipe is a separate decision and not this pass's
    to take.
  - **Hazard no gate guards:** `tests/doc-sync-test.sh` extracts
    `` `toolkit/...` `` tokens from `CLAUDE.md`, and a wrap that splits a
    backticked path across a newline drops it silently and surfaces as a
    spurious "undocumented shipped file". Re-run the suite and read its output
    rather than trusting a green exit.

- **Item 4.6:** `toolkit/release.sh`, `tests/version-guard-test.sh`,
  `tests/release-test.sh` — convert four `<script>.sh:<line>` citations to
  unambiguous line context.
  - Requirements: N9
  - Depends on: Items 1.1, 1.2, 3.1, 3.2, 3.4 — 3.2 is `outline.md`'s line-level
    overlap B5 ↔ C4 (the two stale `version-guard-test.sh` citations sit inside
    the comment block 3.2 edits), named here rather than left to transitivity
    through 3.4.
  - A whole-tree sweep found four hits, three of them stale; the review reported
    one. Each of the three lands on *different real code*, so a reader who
    follows one gets a confident wrong answer rather than an error:
    - `release.sh`'s comment citing `:780-785` for "release_preflight never runs
      on resume" — the mode dispatch is elsewhere and that range is the
      marketplace commit-gate rollback. **Stale.**
    - `version-guard-test.sh`'s comment citing `release.sh:446-455` for a bump
      argument being refused on an unreleased plugin — that range is the
      version-drift refusal. **Stale.**
    - `version-guard-test.sh`'s comment citing `release.sh:456-460` for a bare
      `just release` publishing `$current` — that range is a `die` plus the
      resume hint. **Stale.**
    - `release-test.sh`'s comment citing `release.sh:138` for the dirty-tree
      refusal preceding `release_preflight`. **Accurate today** — convert it
      too, so the repo carries one convention rather than two.
  - Replacement form: the enclosing symbol plus a short quoted fragment of the
    cited line — "`release.sh`, the mode dispatch in `main`, the `--resume`
    branch" — not a bare function name, which loses precision in a long
    function. **Re-locate each target by symbol**, since Items 1.1 and 1.2 have
    moved `release.sh` and Items 3.2–3.4 have moved `version-guard-test.sh`.
  - Citations *into frozen dated artifacts* keep their line numbers and are out
    of scope: an executed `outline.md`, a runbook, a review report and a
    changelog entry are never revised, so the number stays permanently correct.
  - Recorded upstream, no follow-up held here: a brief at
    `../edify/inbox/brief-cite-line-context-not-line-numbers.md` proposes the
    same convention for `/design` and `/runbook`. Dropping it was the end of
    this repo's involvement.

- **Item 4.7:** `docs/changelog/2026-09-18-deliverable-review-fixes.md` and its
  index line in `docs/changelog.md` — the dated write-time record.
  - Requirements: N9, N14, BD
  - Depends on: every prior item
  - Carries three things not derivable from the diff:
    - **the citation convention** Item 4.6 establishes — source citations name
      unambiguous line context rather than line numbers, frozen dated artifacts
      exempt — because it binds future edits;
    - **the measured comment figures** Item 4.3 deliberately kept out of the
      hub, which stay correct here because the entry is dated;
    - **BD**: `outline.md:262`'s three-versus-four hint count was left standing
      deliberately — the executed outline is a dated artifact and the review
      report already carries the correction — so a later pass does not re-open
      it as an unfixed finding.

## Gate

`just precommit` must be green before **each** commit. It runs all eight suites,
`_import-check`, the 400-line cap, the doc-sync check, `whitespace` and
`format-docs`.

**Doc-sync does not cover Items 4.4 or 4.5 — verify both by reading.** It
compares only *fenced command blocks* in the two READMEs' install/update
sections, and 4.4 is a prose line in a component bullet; its second check
extracts `` `toolkit/...` `` tokens from `CLAUDE.md`, and 4.5's target bullet
holds none, so it passes trivially rather than being checked. Claiming the gate
catches these would be this pass's own false-assurance defect, in the section
that certifies the pass.

Per `commit-bundling`, each code change rides with the test that proves it and
with the comment that documents it — no carve-outs, and nothing dropped
silently. A cluster B item's mutation is applied, observed and **reverted**
before its commit; no commit carries a mutation.

One scope question the pass does not decide in an item: whether Item 4.6's
citation convention also belongs as a bullet in `CLAUDE.md`'s Conventions
section. **The executor's default is no** — it lands in Item 4.7's dated entry
and nowhere else, and no item edits `CLAUDE.md`'s Conventions. Raise it at the
proof gate, the way Item 2.1 is raised there; it is not an open choice inside
any dispatch.

# Deliverable Review: 2026-09-15-first-release-version

**Date:** 2026-09-18 **Methodology:** `edify:deliverable-review`, two layers —
three delegated opus per-type passes (`deliverable-review-{code,test,prose}.md`)
plus an interactive cross-cutting pass in the main session, run independently of
the delegated reports. **Baseline:** `outline.md` (the design) and `runbook.md`
(FR-1..FR-10, Decisions 1-3). No `design.md` exists for this plan; the outline
is the conformance spec. **Range:** `ca0204a..e229e1b` (`6550fb7~1..HEAD`),
excluding `plans/`, `tmp/` and `.claude/`.

## Inventory

| Type | File | +/− |
|---|---|---|
| Code | `toolkit/release.sh` | +384/−40 |
| Code | `toolkit/version-guard.sh` | +85/−2 |
| Code | `toolkit/release.just` | +4 |
| Code | `scripts/self-release.sh` | +294 (new, unspecified) |
| Config | `justfile` | +16/−59 |
| Config | `toolkit/VERSION` | 0.7.2 → 0.8.0 |
| Test | `tests/release-test.sh` | +709/−11 |
| Test | `tests/version-guard-test.sh` | +447 (new, from split) |
| Test | `tests/check-version-test.sh` | +104 (new, from split) |
| Test | `tests/hook-test.sh` | −210 (deleted by split) |
| Test | `tests/self-release-test.sh` | +336 (new, unspecified) |
| Docs | `docs/design.md` | +46/−4 |
| Docs | `docs/references/release-flow.md` | +81/−23 |
| Docs | `docs/references/version-guard.md` | +110 (new) |
| Docs | `docs/references/recovery.md` | +129/−23 |
| Docs | `docs/references/self-release.md` | +78 (new, unspecified) |
| Docs | `docs/changelog.md` + six records | +39 / +353 |
| Docs | `toolkit/README.md` | +11/−3 |
| Docs | `CLAUDE.md` | +40/−9 |

Total ≈ 3300 added lines, so Layer 1 ran at the three-agent tier.

**Design conformance:** every FR-1..FR-10 and every Decision 1-3 is implemented
and documented. `just precommit` is green on the working tree as reviewed (all
eight suites, `_import-check`, the 400-line cap, the doc-sync check; nothing was
restaged by `whitespace` or `format-docs`).

## Critical Findings

None.

## Major Findings

### 1. Nothing in the suite tells a dist split from the tag apart from a split from `HEAD`

`tests/self-release-test.sh:210-222`, axis: vacuity / coverage.

`ensure_dist_tag` runs before `push_branch` (`scripts/self-release.sh:277-279`),
so the `block_push` + `run minor` setup leaves `dist-v0.2.0`
**already created locally**. The `--resume` that follows takes the short-circuit
at `scripts/self-release.sh:183-186` and `git subtree split` never runs. The
assertion re-reads a tree cut before the later commit existed, and the comment's
claim —
*"What it proves is that the split ran against the tagged commit at all"* — is
false. The happy path (`:143-162`) splits when `HEAD` **is** the tagged commit,
so it cannot discriminate either.

**Failure scenario:** change `scripts/self-release.sh:203` to
`git subtree split -q --prefix=toolkit HEAD`. The whole suite stays green, and
the next resumed release publishes a `dist-vX.Y.Z` whose tree is `HEAD`'s
`toolkit/` rather than the tagged one. That ref is exactly what every consumer
vendors.

**Fix shape:** land the later work *inside* `toolkit/`, delete the local dist
tag before the resume (as the dead-origin scenario at `:325` already does), then
assert `git show dist-v0.2.0:` does not carry the later file.

### 2. `release_tags()` is the one listing still resting on `pipefail`

`toolkit/release.sh:307`, axis: robustness / internal consistency.

```sh
git tag --list 'v*' --sort=-v:refname | semver_tags
```

`semver_tags` absorbs a no-match grep's status 1, so the pipeline's last stage
reports success on empty input and `git tag`'s failure reaches the caller only
through `set -o pipefail`. **Verified empirically** (bash 5.2, in a non-repo
directory): with `pipefail` on the capture refuses; with `set +o pipefail` it
returns status 0 and an empty string.

**Failure scenario:** with `pipefail` lost from `toolkit/release.sh:2`, a
`git tag --list` that fails (corrupt `refs/tags`, unreadable `packed-refs`, a
killed `git`) yields `""` with status 0. The `|| die` at `:355` never fires,
`:377` enters the lost-tags branch, and on a silent origin `first_release=1` at
`:471` and `bump_commit_tag` tags `HEAD` — publishing the manifest version of a
plugin whose release history it could not read.

This is the exact fail-open that `origin_release_tags`'s own comment argues
against at `:329-334` (*"That would leave this function's safety resting on one
word of the `set` line 250 lines up"*), and that the range's last production
commit `a047aa2` exists to remove — applied to the `ls-remote` probes and not to
this one. `resume_preflight`'s comment at `:566-569` compounds it: it asserts
*"Reachable, both measured: `git tag --list` erroring, and a status-2 grep
error"*, and only the grep leg is covered structurally.

The pipefail-stripped scenario at `tests/release-test.sh:1427-1448` covers
`ls_remote_sha`'s three reads only — its own comment says
*"nothing else in the suite would notice"*, which is precisely true of this
line.

### 3. The `.claude/` clean-check exemption test is vacuous, and the `memory` half is untested

`tests/self-release-test.sh:267-271`, axis: vacuity.

The handoff frame is written **untracked**, and `scripts/self-release.sh:56` is
`git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory'`, which sees
tracked paths only.

**Failure scenario:** delete `':(exclude).claude'` from
`scripts/self-release.sh:56`. The assertion stays green and the exemption it
names is no longer guarded. `tests/release-test.sh:179-192`
(`stage_handoff_frame`) solved this and documents why; the self-release fixture
needs the same commit-then-rewrite-and-stage shape. The `':(exclude)memory'`
gitlink-ahead-of-HEAD state is never constructed at all.

### 4. `self-release-test.sh` refusals assert a message and nothing else

`tests/self-release-test.sh:231-309`, axis: coverage / specificity.

Nine refusal scenarios assert neither the exit status nor the absence of a side
effect. `$GH_LOG` is never asserted empty anywhere in this suite, so no refusal
is pinned as having happened before `gh` was reached — unlike `release-test.sh`,
which asserts it on essentially every refusal.

**Failure scenario:** make `common_preflight`'s dirty-tree branch print to
stderr and fall through instead of `die`. `:262-265` stays green while the
release proceeds on a dirty tree. The wrong-branch (`:273-276`) and
dist-tag-squatting (`:296-301`) scenarios have the same hole.

### 5. `version-guard.md` claims a hook/recipe parity that does not hold

`docs/references/version-guard.md:44-48`, axis: accuracy.

> The predicate is the one `release_preflight` uses … so the hook and the recipe
> cannot disagree about which state a repo is in.

The predicate clause is true; the conclusion is not. `version-guard.sh:124`
lists **local** tags only, while `release_preflight` probes origin when the
local list comes back empty (`toolkit/release.sh:377-403`).

**Failure scenario:** on a lost-tags clone the recipe refuses with the
`git fetch --tags` hint while the hook takes the initial-release branch and
tells the agent
*"which version a plugin first ships as is the maintainer's call"* — the
permissive wording for a plugin that may already be published, which is the harm
this same node cites at `:106-114` to justify the restrictive fallback on a
failed listing. The node records one bound for the listing (`:132-134`) and not
this one, so a maintainer asking whether the hook needs an origin probe reads
`:44-48` as settling it.

Local-only is correct for a `PreToolUse` hook; this is a bound to record, not a
defect to close. `docs/design.md:187` carries the defensible weaker form.

### 6. `version-guard.sh`'s header contradicts the decision the file implements

`toolkit/version-guard.sh:3-7`, axis: consistency. Shipped file.

> before a first release there is no tag to desync from, but the recipe is still
> the only place a version is meant to change.

False under this plan. On a first release the version legitimately changes by
the maintainer's committed hand edit — which is what the same file's own deny
message says (`:153-154`), what `toolkit/release.sh:476-479` instructs, and what
`toolkit/README.md:181-186` and `docs/design.md:109-110` record as the decision.
The outline (`:126-127`) asked for this header to be restated for both cases;
the initial-release half was added and the steady-state conclusion was carried
over unchanged.

**Failure scenario:** a maintainer reading the shipped header concludes a hand
edit is never legitimate — the belief the whole plan exists to correct.

## Minor Findings

**Correctness / robustness**

- `toolkit/release.sh:577` — `printf … | grep -qxF` exits on first match; under
  `pipefail` `printf`'s EPIPE becomes the pipeline status and a match reads as
  no-match (**verified**: 200 000-line listing, match on line 1, status 141). On
  an origin with >64 KiB of semver tags the resume hint ladder skips branch 1
  for branch 2 and advises `just release <bump>`, which `release_preflight` then
  refuses. Bounded to hint quality. Two other sites in the same file avoid
  `head -1` citing this exact reason (`:383-384`, `:495-497`).
- `scripts/self-release.sh:109` — `git describe --tags --abbrev=0 --match 'v*'`
  is the shape `toolkit/release.sh:302-306` documents as wrong for this job:
  describe sees only tags reachable from `HEAD` and returns the nearest of any
  name, not the newest. A `vnext` on `HEAD`'s ancestry produces
  `die "… does not match latest tag (vnext)"` with a hint that cannot fix it; a
  release tag off `HEAD`'s ancestry empties `latest_tag` and skips the drift
  guard at `:112` entirely.

**Test quality**

- `tests/release-test.sh:935-947`, `:949-964` — two refusals assert `rc` and
  message needles but not tag absence, `$GH_LOG`, origin `main` or the
  marketplace, against `outline.md:172-173`'s blanket rule.
- `tests/version-guard-test.sh:355` — `tagless_sysmsg` reads the `guard_out`
  left by the run at `:315-317`, forty lines and two assertion blocks earlier,
  with no note saying so (unlike the deliberate `$reason` reuse at `:324-332`).
  A scenario inserted between silently retargets the byte-identity comparison.
- `tests/version-guard-test.sh` — every `assert_allow` runs against `$proj`,
  which is deliberately not a repo, so no allow scenario touches a git fixture.
  `outline.md:130`'s property (the listing runs only after the deny is
  established) is unpinned: a mutation hoisting the listing above
  `version-guard.sh:80` passes the suite.
- `tests/version-guard-test.sh:374-381` — the `vnext` half of slice 4 omits
  `assert_no_escape_hatch`, which slices 1 and the tagged case both call.
- `tests/self-release-test.sh:149` — "tree left dirty" uses
  `git diff --quiet HEAD`, tracked-only; an untracked leftover passes.
- **Harness divergence across suites.** `tests/version-guard-test.sh:36-42`
  implements `assert_contains` as a literal glob (`[[ "$1" != *"$2"* ]]`) while
  `release-test.sh:30`, `self-release-test.sh:34` and
  `update-plugin-dev-test.sh:32` use `grep -q --` (a BRE). Same name, same
  signature, different matching semantics, in a repo that deliberately
  duplicates the harness per file. No needle currently produces a false pass,
  but a scenario moved between suites changes meaning silently — and
  `self-release-test.sh:207-208`'s `": pushed$"` anchors depend on the grep
  form.

**Documentation**

- `toolkit/release.sh:254` cites `release.sh:780-785` for "release_preflight
  never runs on resume". The mode dispatch is at `:837-843`; `:780-785` is the
  marketplace commit-gate rollback. **Verified** the citation was already ~14
  lines off when written at `ff1beec` and is now ~57 off.
- `docs/design.md:186-192` and `:135-140` — the hub carries the node's argument
  (the non-blocking-exit mechanism; the three push-route keys and the
  `pushInsteadOf` bound), against its own one-conclusion-per-decision contract
  at `:7-12`, `:63-67`. Both arguments are already at `version-guard.md:83-90`
  and `recovery.md:216-258`.
- Partial tag loss — recorded in `outline.md` Scope/OUT, recorded in neither
  `docs/references/recovery.md` nor `docs/design.md`. The symmetric bound on the
  adjacent check (`url.<base>.pushInsteadOf`) **is** recorded in both, which
  makes the omission read as coverage.
- `toolkit/README.md:34` still says "the latest tag" where the file's own
  Conventions bullet sixty lines later says `vX.Y.Z` tag. This is the only
  shipped manual a consumer reads.
- `CLAUDE.md:73-76` carries a ragged wrap. `just format-docs` runs rumdl over
  `docs/` and `plans/` only, so nothing will reflow it.
- `toolkit/release.sh` is 852 lines, 51% comment-only; `version-guard.sh` 45%.
  Nothing measures source files — `tests/docs-test.sh`'s cap applies to `docs/`
  and `plans/`. Three blocks are write-time record rather than contract
  (`:502-519`, eighteen lines on two hints the code no longer prints, framed as
  *"recorded so they do not come back"*; `:245-257`; `:322-336`). Accurate
  throughout; it is the volume that every consumer vendors.
- `toolkit/version-guard.sh:170-171` —
  *"If the goal is to ship a release, invoke the recipe instead"* is `if … then`
  phrasing in a deny channel. Pre-existing and explicitly frozen by
  `outline.md:126`; recorded so a later pass does not read the freeze as
  endorsement. The **new** initial-release branch (`:149-157`) is clean on this
  axis and stricter than the outline permitted.

## Baseline defect

`outline.md:262` says the no-tag refusal has **three** hints. The code emits
**four** (`toolkit/release.sh:577`, `:585`, `:596`, `:603`), `runbook.md` Item
3.3 says four, and `docs/references/recovery.md:85-103` documents four. The
outline's `:51-54` citation is also wrong: the pre-change `recovery.md` carried
one hint there. No deliverable needs changing; the outline is the defective
document.

## Gap Analysis

| Requirement | Status | Reference |
|---|---|---|
| FR-1 initial release publishes the manifest version as-is | Covered | `release.sh:470-486`, `:618-626`; `release-test.sh:777-791` |
| FR-2 predicate is tag-only, entry plays no part | Covered | `release.sh:294`, `:307`; filter byte-identical to `version-guard.sh:139` |
| FR-3 initial release refuses a bump argument | Covered | `release.sh:472-481`; `release-test.sh:793-810` |
| FR-4 origin probe before `check-version.sh` and every side effect | Covered | `release.sh:377-403` vs `:413`, `:840`, `:844`; `release-test.sh:876-986` |
| FR-5 resume hint ladder from one origin listing | Covered | `release.sh:559-611`; `release-test.sh:376-475` (see Minor, `:577`) |
| FR-6 `common_preflight` refuses a diverged push route | Covered | `release.sh:203-215`, `--get-all` and branch resolved from `symbolic-ref`; `release-test.sh:1016-1102` |
| FR-7 guard's agent message branches, human channel does not | Covered | `version-guard.sh:124-174`; `version-guard-test.sh:310-441` |
| FR-8 initial release with a disagreeing entry still refused | Covered | `release.sh:414-458`; `release-test.sh:812-849` |
| FR-9 docs, hub, consumer manual, changelog restated | Covered | Majors 5 and 6 are accuracy defects within covered documents |
| FR-10 toolkit self-release | Covered | `toolkit/VERSION` 0.8.0, `e3312f9`, minor bump as `outline.md` required |
| Decision 1 keep the drift refusal with its own hint | Covered | `release.sh:414-458` |
| Decision 2 failed listing takes the steady-state wording | Covered | `version-guard.sh:144`, `:147`; `version-guard-test.sh:399-418` |
| Decision 3 refuse a diverged push route | Covered | `release.sh:203-215`; `pushInsteadOf` recorded as a bound at `:165-174` |

**Unspecified deliverables** (produced, not in the outline's Scope):
`scripts/self-release.sh`, `tests/self-release-test.sh`,
`docs/references/self-release.md`, the `tests/hook-test.sh` split into
`version-guard-test.sh` + `check-version-test.sh`, and the `CLAUDE.md` edits
(`CLAUDE.md` is named OUT). All are follow-up work agreed after the runbook was
written. Justified as excess — but Majors 1, 3 and 4 and two Minors all land
there, so the follow-up work is held to a visibly lower test bar than the plan's
own deliverables. The split itself lost nothing: all eight version-guard
scenarios and all five check-version scenarios survive with assertions
unchanged, and `recovery.md` → `self-release.md` preserved every paragraph but
one, deleted deliberately because `43f348a` made it false.

**Missing deliverables:** none.

## Summary

Critical 0 · Major 6 · Minor 15.

`just precommit` is green. Every requirement and decision in the outline is
implemented and documented, and the plan's own test deliverables conform closely
— every enumerated scenario is present, all three load-bearing negatives are
written, and several scenarios exceed their contract with ordering and
membership guards the runbook did not ask for.

Four of the six Majors are in the unspecified follow-up work
(`scripts/self-release.sh` and its suite). Of the two in the plan's own
deliverables, one is a latent robustness gap (Major 2) and one is a prose
accuracy defect in a shipped file (Major 6); Major 5 is a prose accuracy defect
in a design node.

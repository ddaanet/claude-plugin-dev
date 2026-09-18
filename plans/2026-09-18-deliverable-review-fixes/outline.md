# Outline — deliverable-review fix pass

Fixes the findings of
`plans/2026-09-15-first-release-version/reports/deliverable-review.md` (Critical
0, Major 6, Minor 15) against `8d3fbf5`, tree clean. Every Major was re-verified
against current code during triage; none is stale. Classification and the four
triage decisions are in `classification.md` beside this file.

Three clusters: **A** production code (3 items, each a logic path), **B** test
suites (7 items, each a fixture that currently cannot fail), **C** prose (11
items). A and B are tdd-shaped; C is inline.

## Scope

**IN** — all 6 Majors, 13 of the 15 Minors, and two stale self-citations the
review did not find (see C4).

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
function comment to say the safety no longer depends on the `set` line, and drop
the half of `origin_release_tags:322-336` that now describes both.

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

**Test:** a `git` stub whose `ls-remote --tags` emits enough synthetic semver
lines to exceed the 64 KiB pipe buffer with the match first. Prefer the stub
over creating real tags: ~8 000 `git tag` calls costs minutes, the stub costs
one `seq`-driven `printf`. Assert branch 1 of the ladder fires — "origin already
has <tag>" and the `git fetch --tags` remedy — not branch 2's
`just release <bump>`, which `release_preflight` then refuses.

**Mutation that must go red:** restore the pipe.

### A3 — `self-release.sh` uses the tag shape `release.sh` documents as wrong

`scripts/self-release.sh:105-117`. `git describe --tags --abbrev=0 --match 'v*'`
sees only tags reachable from `HEAD` and returns the *nearest* of any matching
name, not the newest — the two failure modes `toolkit/release.sh:302-306` spells
out for its own callers.

**Change:** list and filter. `git tag --list 'v*' --sort=-v:refname`, keep lines
matching `^v[0-9]+\.[0-9]+\.[0-9]+$`, take the first. Capture-then-filter, not a
pipe, for A1's reason. No code is shared with `toolkit/release.sh` — that
separation is deliberate (`self-release.sh:8-12`) and this item does not touch
it.

**Tests:** two scenarios, both currently impossible to write.

1. A `vnext` tag on `HEAD`'s ancestry must not be read as the latest release.
   Today it yields `die "… does not match latest tag (vnext)"` with a hint that
   cannot fix it.
2. A release tag *off* `HEAD`'s ancestry — tagged on a since-abandoned branch —
   must still be seen. Today `latest_tag` comes back empty and the drift guard
   at `:112` is skipped entirely.

**Also update:** `tests/self-release-test.sh:296-297`, whose comment explains
the dist-tag-squatting scenario in terms of `describe --match 'v*'`. The
scenario's behaviour survives — the `v*` glob still excludes `dist-v*` — but the
stated reason does not.

## Cluster B — test suites

Every item here is `craft:test-discipline`'s core move: make the fixture carry
the discrimination, so the assertion has something to be wrong about. Each names
the mutation that must go red.

### B1 — the dist split does not discriminate the tag from `HEAD` (Major 1)

`tests/self-release-test.sh:210-222`. `ensure_dist_tag` runs before
`push_branch`, so the `block_push` + `run minor` setup leaves `dist-v0.2.0`
already created locally; the `--resume` takes the short-circuit at
`self-release.sh:183-186` and `git subtree split` never runs. The happy path
(`:143-162`) splits when `HEAD` *is* the tagged commit, so it cannot
discriminate either. Nothing in the suite pins the tree of the ref every
consumer vendors.

**Change:** land the later work *inside* `toolkit/`, delete the local dist tag
before the resume — the dead-origin scenario at `:325` already does exactly this
— then assert `git show dist-v0.2.0:<later-file>` fails and
`git ls-tree --name-only dist-v0.2.0` omits it.

**Mutation:** `scripts/self-release.sh:203` `"$tag"` → `HEAD`. Today the whole
suite stays green under it.

### B2 — the clean-check exemptions are untested (Major 3)

`tests/self-release-test.sh:267-271`. The handoff frame is written
**untracked**, and `self-release.sh:56` is
`git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory'`, which sees
tracked paths only. The `memory` half is never constructed at all.

**Change, `.claude/`:** adopt the commit-then-rewrite-and-stage shape of
`tests/release-test.sh:179-192` (`stage_handoff_frame`), whose comment already
documents why untracked does not reach the check.

**Change, `memory`:** construct a gitlink resting ahead of `HEAD` — the resting
state gitlore leaves. This needs a real submodule in the fixture; the suite
already drops the leaked git environment at `:17`
(`unset $(git rev-parse --local-env-vars)`), so the submodule calls are safe
there. A local-path submodule clone may need `-c protocol.file.allow=always`;
confirm against the sandbox rather than assuming.

**Mutations:** drop `':(exclude).claude'` → red; drop `':(exclude)memory'` →
red. Both stay green today.

### B3 — nine refusals assert a message and nothing else (Major 4)

`tests/self-release-test.sh:231-309`. No exit status, no absence of a side
effect, and `$GH_LOG` is never asserted empty anywhere in the suite — so no
refusal is pinned as having happened before `gh` was reached.
`tests/release-test.sh` asserts it on essentially every refusal.

**Change:** add an `assert_gh_untouched` helper and apply `rc`, `$GH_LOG` empty
and tag-absence to all nine. Note `$GH_LOG` is truncated per `new_sandbox`
(`:104`), so the pair at `:262-271` sharing one sandbox needs the log read
between runs, not after both.

**Mutation:** make `common_preflight`'s dirty-tree branch print to stderr and
fall through instead of `die`. `:262-265`, `:273-276` and `:296-301` all stay
green today while the release proceeds.

### B4 — two `release-test.sh` refusals under-assert (Minor 3)

`tests/release-test.sh:935-947` and `:949-964` assert `rc` and message needles
but not tag absence, `$GH_LOG`, origin `main` or the marketplace, against the
blanket rule the executed `outline.md:172-173` states. Bring both up to the
shape the rest of that file uses.

### B5 — two `version-guard-test.sh` gaps (Minors 4 and 6)

- `:355` — `tagless_sysmsg` reads the `guard_out` left by the run at `:315-317`,
  forty lines and two assertion blocks earlier, with no note saying so. The
  deliberate `$reason` reuse at `:324-332` *is* documented. Either re-invoke the
  hook or add the note; a scenario inserted between silently retargets a
  byte-identity comparison.
- `:374-381` — the `vnext` half of slice 4 omits `assert_no_escape_hatch`, which
  slice 2 (`:349`) and the tagged case (`:365`) both call. Add it.

### B6 — no allow scenario touches a git fixture (Minor 5)

Every `assert_allow` in `tests/version-guard-test.sh` runs against `$proj`,
which is deliberately not a repo. The executed `outline.md:130`'s property — the
tag listing runs only after the deny is established — is therefore unpinned.

**Change:** add one allow scenario against a git fixture (an edit to
`plugin.json` that does not change `.version`, in `$git_tagged_proj`).

**Mutation:** hoist the listing above `version-guard.sh:80`. The suite passes
today.

### B7 — `assert_contains` means two different things (Minor 8)

`tests/version-guard-test.sh:34-47` implements it as a literal glob
(`[[ "$1" != *"$2"* ]]`); `release-test.sh:30`, `self-release-test.sh:34` and
`update-plugin-dev-test.sh:32` use `grep -q --`, a BRE. Same name, same
signature, different semantics, in a repo that deliberately duplicates the
harness per file.

**Change:** move `version-guard-test.sh` to the `grep -q --` form. No needle
currently produces a false pass either way, but re-check every needle in that
file under BRE before landing — the dots in `1.2.3 -> 9.9.9` become any-char and
still match, which is the point to verify rather than assume.
`self-release-test.sh:207-208`'s `": pushed$"` anchors already depend on the
grep form, so this converges the four suites rather than diverging them further.

## Cluster C — prose

Inline items. C1 and C3 touch the same file; C4 must land after A1 and A2.

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
    refusal preceding `release_preflight`. **Accurate — leave it.**

  **Standing question for `/runbook`:** line-number citations rot on every edit,
  and A1/A2 will shift `release.sh` again. Recommend citing function names and
  dropping line numbers; that is a convention change, so surface it rather than
  deciding it here.
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
- **C9 (Minor 14)** — record the bound triage decision 2 left standing:
  `toolkit/release.sh` is 852 lines and 51% comment-only, `version-guard.sh`
  45%, nothing measures source files, and three blocks are write-time record
  rather than contract. One line in `docs/design.md`'s Limitations, naming it as
  accepted rather than unnoticed.
- **C10** — a dated write-time record at
  `docs/changelog/2026-09-18-deliverable-review-fixes.md` plus its index line in
  `docs/changelog.md`, per the repo's design-and-changelog convention.
- **C11** — no deliverable changes for the baseline defect. State in C10's
  record that `outline.md:262`'s three-hint count was left standing
  deliberately, so a later pass does not re-open it as an unfixed finding.

## Dependencies and ordering

1. **A1 and A2 before C4.** Both shift line numbers inside `toolkit/release.sh`,
   and C4's whole point is that its citations are right.
2. **A3 before the `tests/self-release-test.sh:296-297` comment update**, which
   is part of A3's own item.
3. **C1 before C3** — same file, adjacent prose, and C3's scope depends on C1's
   restatement landing first.
4. **B2 is the heaviest item** (a submodule fixture) and depends on nothing.
   Schedule it so it does not block the rest.
5. Everything else is independent.

## Gate

`just precommit` must be green before each commit — it runs all eight suites,
`_import-check`, the 400-line cap, the doc-sync check, `whitespace` and
`format-docs`. Doc-sync covers the two READMEs' shared command blocks and the
`CLAUDE.md` Layout list against `toolkit/`'s contents; C7 and C8 both land
inside its reach.

Per `commit-bundling`, each code change rides with the test that proves it and
with the comment that documents it — no carve-outs, and nothing dropped
silently.

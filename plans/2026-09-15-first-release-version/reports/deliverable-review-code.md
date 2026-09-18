# Deliverable review — code (Layer 1)

Scope: `toolkit/release.sh`, `toolkit/version-guard.sh`, `toolkit/release.just`,
`justfile`, `scripts/self-release.sh`, as they stand in the working tree.
Baseline: `outline.md`, `runbook.md` (FR-1..FR-10, Decisions 1-3), `CLAUDE.md`,
`shell-scripting:shell-gotchas`, `craft:directive-writing`.

Method: full read of all five files and both baseline documents; test suites not
run (per instruction). Empirical probes were run in throwaway fixtures for every
claim marked **verified** below. Claims marked **read** were checked against the
source text only.

## Critical

None.

Every requirement the outline states as a correctness property is implemented
and, where I could probe it cheaply, behaves as specified. In particular the
three shell constraints hold:

- **verified** — the `if push_values=$(…); then … elif [ "$?" -ne 1 ]` form at
  `toolkit/release.sh:204-214` reads the *failed if-condition's* status. Probed
  with a function returning 1, 2 and 128: `1 → else` (absorbed),
  `2 → elif body`, `128 → elif body`. The comment's claim at `:199-201` is
  accurate.
- **verified** — `origin_release_tags` (`toolkit/release.sh:338`) fails closed
  without `pipefail`: `listing=$(git ls-remote …) || return 1` reads the status
  before any filter. Commit `a047aa2`'s claim holds *for the ls-remote probes*.
  See Major 1 for the probe it does not cover.
- **verified** — `toolkit/version-guard.sh` never exits non-zero after the deny.
  Against a tagless `git init` fixture, a `v1.2.3`-tagged fixture, and a `git`
  stub exiting 127, all three runs gave `EXIT=0`, empty stderr, and a deny JSON
  on stdout.
- **verified** — `--sort=-v:refname` is present on both listings
  (`toolkit/release.sh:307`, `:338`) and the newest-first contract holds through
  the filter. Against a fixture carrying
  `v1.2.3 v1.9.0 v1.10.0 v1.11.0 vnext v1.2` (git 2.47.3): `ls-remote`'s default
  order is `v1.10.0 v1.11.0 v1.2 v1.2.3 v1.9.0`; with `--sort=-v:refname` the
  first semver-filtered line is `v1.11.0` from both the remote and the local
  listing. Peeled `^{}` rows are dropped by the anchor. Both callers take line 1
  (`:387` via `sed -n '1p'`, `:501` via `sed -n '1s/^v//p'`) — the correct end.
- **verified** — the semver filter is byte-identical in the two copies:
  `grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'` at `toolkit/release.sh:294` and
  `toolkit/version-guard.sh:139`.

## Major

### 1. `release_tags()` is the one probe still resting on `pipefail`

`toolkit/release.sh:307` — axis: robustness, internal consistency.

```sh
git tag --list 'v*' --sort=-v:refname | semver_tags
```

`semver_tags` deliberately absorbs a no-match grep's status 1, so the pipeline's
last stage reports success on empty input. The `git tag --list` stage's failure
status therefore reaches the caller *only* through `set -o pipefail`
(`toolkit/release.sh:2`).

**Verified.** Stubbing the listing stage to exit 128 through a filter shaped
like `semver_tags`:

- `set +o pipefail` → capture status **0**, output empty.
- `set -o pipefail` → capture status non-zero.

Failure scenario (inputs/state → wrong outcome): with `pipefail` absent from the
`set` line, a `git tag --list` that fails (corrupt `refs/tags`, an unreadable
`packed-refs`, a `git` killed mid-run) returns an empty string with status 0.
`release_tag_list=$(release_tags) || die …` at `:355` never fires. The empty
string then drives the lost-tags branch at `:377`, and — if origin is also
silent or the clone is genuinely tagless — `first_release=1` at `:471`,
`bump_commit_tag` tags `HEAD` at `:622`, and the run publishes the manifest
version of a plugin whose local release history it could not read.

This is the exact fail-open that `origin_release_tags`'s own comment argues
against, in its own words (`:329-334`): *"with pipefail off the pipeline returns
0 and the caller reads 'origin has no tags either' … That would leave this
function's safety resting on one word of the `set` line 250 lines up."* The
argument is made in full and then applied to only one of the two listings.

`resume_preflight:570` (`if release_tag_list=$(release_tags) && [ -z … ]`) has
the same dependency, and its comment at `:566-569` asserts
*"Reachable, both measured: `git tag --list` erroring, and a status-2 grep error inside semver_tags."*
The grep-error leg is genuinely pipefail-independent — `semver_tags` is the last
stage, so its status is the pipeline's either way. The `git tag --list` leg is
not. The comment reads as though both are covered structurally; one is covered
only by `pipefail`.

Latent, not a live defect: `pipefail` is set today and `git tag --list`
essentially never fails. Flagged Major because the range's last commit
(`a047aa2`) exists to establish precisely this property, and the file now
applies it inconsistently, with a comment that argues the general rule beside
the function that still breaks it.

Fix shape, mirroring `origin_release_tags`:

```sh
local listing
listing=$(git tag --list 'v*' --sort=-v:refname) || return 1
printf '%s\n' "$listing" | semver_tags
```

(with the empty-listing case handled as `origin_release_tags:345` already does —
`printf '%s\n' ""` emits one blank line, which the anchored filter drops).

## Minor

### 2. `printf | grep -q` under `pipefail` at the resume hint ladder

`toolkit/release.sh:577` — axis: edge-case robustness.

```sh
if printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"; then
```

`grep -q` exits on its first match; with `pipefail`, `printf`'s EPIPE status
becomes the pipeline's status and the `if` reads a match as no-match.

**Verified.** With a 200 000-line listing whose match is on line 1:
`grep -q: NO MATCH (status 141)`.

Failure scenario: a plugin whose origin carries more than one pipe buffer (~64
KiB, roughly 8 000 semver tags) of release tags, resuming at the newest of them.
Because the listing is sorted newest-first, `$tag` is line 1 — the earliest
possible exit, so the worst case for EPIPE. Branch 1 is skipped, branch 2 fires,
and the operator is told *"origin has release tags, but none matching v1.2.3 …
run `git fetch --tags`, then run `just release <bump>`"* — a bump form that
`release_preflight` will then refuse, when the correct advice
(`just resume-release`) was one branch away.

Consequence is bounded to hint quality: the refusal at `:612` is already decided
and fires either way, which the code says explicitly at `:549-551`. Two other
sites in the same file avoid `head -1` citing exactly this
SIGPIPE-under-pipefail reason (`:383-384`, `:495-497`), so the convention exists
and this line is the one place it is not applied. Fix:
`case $'\n'"$origin_tag_list"$'\n' in *$'\n'"$tag"$'\n'*)`, or
`grep -qxF -- "$tag" <<<"$origin_tag_list"` (a herestring is a temp file, not a
pipe — no EPIPE, no pipeline status).

### 3. Comment mass, and write-time record in code comments

`toolkit/release.sh` (852 lines, 435 comment-only — 51%),
`toolkit/version-guard.sh` (185 lines, 45%). Axis: clarity; the repo's own
standards.

The shared conventions cap "any artifact a reader takes in at one go — source
files" at 400 lines as a soft guideline, allowing a *bounded* overage.
`toolkit/release.sh` is 2.1× the cap. Nothing measures it: `tests/docs-test.sh`
applies its 400-line cap only to `docs/` and `plans/` (read,
`tests/docs-test.sh:28`).

`craft:directive-writing` on code comments: *"the rule, the constraint and the
contract stay; the story, the incident and the self-commentary belong to the
changelog."* Three blocks in the new code are the story:

- `:502-519` — eighteen lines on two hints the code no longer prints, explicitly
  framed as *"recorded so they do not come back."* That is a changelog entry
  living in a shipped file.
- `:245-257` — the full incident narrative of a past jq misread ("the run
  reached create_github_release — a GitHub release made public — before
  bump_marketplace's own jq call finally aborted the script"). The constraint a
  maintainer needs is the first two sentences.
- `:322-336` — fifteen lines to carry one constraint (*read ls-remote's status
  before any filter, because the filter absorbs status 1*). The empirical
  verification note and the counterfactual belong to the changelog.

Not a correctness problem, and the substance is accurate throughout. It is the
volume that costs: `toolkit/` is the dist boundary, so every consumer vendors
these 852 lines.

One point in the deliverables' favour: `toolkit/version-guard.sh:99-100` refers
to "the toolkit's own test suite" without naming a path — correct for a shipped
file, and it survived the `tests/hook-test.sh` → `tests/version-guard-test.sh`
rename that landed in this same range. I grepped for stale `hook-test.sh`
references outside `plans/` and found none in shipped code, docs or recipes.

### 4. `self-release.sh` picks the latest tag the way `release.sh` documents as wrong

`scripts/self-release.sh:109` — axis: functional correctness (unspecified
deliverable, reviewed on merit).

```sh
latest_tag=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null) || latest_tag=""
```

`toolkit/release.sh:302-306` states the case against `git describe` for this
job, in the same range: *"describe only sees tags reachable from HEAD, so a
release tagged on a since-abandoned branch would read as no tags at all; and it
returns the NEAREST tag of ANY name, distance-ordered rather than
version-ordered."* `--match 'v*'` narrows the name space but fixes neither
property, and still admits non-semver `v` tags.

Two failure scenarios:

- A `vnext` or `v1.2` tag anywhere on `HEAD`'s ancestry nearer than the release
  tag → `latest_tag` becomes `next` / `1.2` → `file_version` (say `0.9.0`) does
  not match → `die "toolkit/VERSION (0.9.0) does not match latest tag (vnext)"`
  with the hint *"revert any manual VERSION bump and re-run"*, which is not the
  problem and cannot fix it. **Read**, not probed — this repo currently carries
  no such tag.
- A release tag on a branch not in `HEAD`'s ancestry → `latest_tag=""` → the
  drift guard at `:112` is skipped entirely, and the bump proceeds from
  `toolkit/VERSION` unchecked.

`require_prior_release_published` (`:75-103`) partly covers the second case, but
only for the version `toolkit/VERSION` names — it is not a substitute for the
drift guard. The right shape is already in the sibling file:
`git tag --list 'v*' --sort=-v:refname` piped through the same semver anchor,
first line.

### 5. `if … then` phrasing in an agent DENY channel

`toolkit/version-guard.sh:170-171` — axis: conformance to
`craft:directive-writing`, not to the outline.

> If the goal is to ship a release, invoke the recipe instead of editing this
> file.

`craft:directive-writing`:
*"Writing 'if … then …' in an agent channel means rewriting it as 'do not …'"*,
since *"any imperative phrasing in a deny-reason gets executed literally."*

Pre-existing text, and the outline explicitly freezes it
(*"The steady-state message is unchanged"*, outline `:126`). Not a regression;
recorded so a later pass does not read the freeze as an endorsement.

The **new** initial-release branch (`:149-157`) is clean on this axis:
**verified** that it names no recipe at all, mentions `$proposed` (`9.9.9`)
nowhere after the opening line, and carries no escape hatch — which is stricter
than the outline permitted (*"may say what the recipe publishes"*).

## Scope note — unspecified deliverables in the range

Three items in the diff are outside the outline's Scope section and carry no
runbook item. Flagged as instructed; each is reviewed above on shell-correctness
merit.

- `scripts/self-release.sh` — 294 lines, wholly new (Minor 4).
- `justfile` — the inline `release` recipe body replaced by a call to that
  script, plus a new `resume-release`. **Verified** against CLAUDE.md's
  single-line-doc-comment convention: `just` takes the *last* comment line above
  a recipe, and in both cases that line is the doc string, with the explanatory
  lines above it. Correct. `resume-release` depends on no gate, matching the
  contract `release.just` gives consumers.
- The `tests/hook-test.sh` split into `tests/version-guard-test.sh` +
  `tests/check-version-test.sh`, visible in the `justfile` diff and reflected in
  `CLAUDE.md`'s Quality gate. The outline lists `CLAUDE.md` as OUT of scope, so
  that documentation edit belongs to the same follow-up work rather than to this
  plan.

## Conformance table

| ID | Status | Evidence |
|---|---|---|
| FR-1 initial release publishes the manifest version as-is | covered | `toolkit/release.sh:470-486` sets `first_release=1`, `V=$manifest_version`, returns without a bump; `bump_commit_tag:618-626` tags `HEAD` with no commit. Read. |
| FR-2 predicate is tag-only, `^v[0-9]+\.[0-9]+\.[0-9]+$`, entry plays no part | covered | `semver_tags:294`, `release_tags:307`, tested at `:377` / `:470`; no `marketplace_entry_exists` conjunct remains in the detection (that variable survives only for `bump_marketplace`, `:727`). Same filter in `version-guard.sh:139` — **verified byte-identical**. Restated in `release.sh:11-16` and `release.just:30-33`. |
| FR-3 initial release refuses a bump argument, names the version and the edit | covered | `:472-481`; `bump_arg` (`:35`, `:40`) distinguishes an explicit `patch` from no argument; hint carries `commit that edit` at `:477`. Read. |
| FR-4 origin probe before `check-version.sh` and before every side effect | covered | Probe `:377-403`; `check-version.sh` invoked `:413`; `bump_commit_tag` / `push_branch` called at `:840` / `:844`. Failed listing → `die` at `:380`. `--sort=-v:refname` on both listings and newest-first through the filter — **verified** on a git 2.47.3 fixture. |
| FR-5 resume hint ladder picks from one origin listing | covered | `:559-611`, four branches in the specified order; one listing at `:560` with `|| origin_tag_list=""` so a failure degrades the advice rather than the refusal. Read. Caveat: Minor 2 can misroute branch 1 → branch 2 on a >64 KiB listing. |
| FR-6 `common_preflight` refuses a diverged push route | covered | `:203-215`; all three keys present; branch resolved from `git symbolic-ref` (`:144`), not hardcoded; runs in both modes before any side effect. Exit-1-only absorption **verified** (1 → else, 2/128 → `elif` die). Values printed one per line, so whitespace is safe; a newline-bearing value is the stated residual (`:190-194`). Deviation from the outline's `--get`: `--get-all` is used, justified at `:179-188`, and is strictly better — `--get` on a multi-valued `pushurl` prints one value and exits 0. |
| FR-7 guard's agent message branches; human channel does not; failed listing → steady state | covered | **Verified end to end**: tagless `git init` fixture → initial-release wording, exit 0, empty stderr; `v1.2.3` fixture → steady-state wording; `git` stub exiting 127 → steady-state wording, exit 0, empty stderr; `systemMessage` byte-identical across the first two; `9.9.9` absent from the reason after line 1. Listing runs at `:124`, after the deny is settled at `:80`. Repo-local `GIT_*` cleared `:91-93`. `2>/dev/null` justified `:96-100`; `CLAUDE_PROJECT_DIR`-inside-a-repo bound stated `:101-103`. |
| FR-8 initial release with a disagreeing entry still refused, per Decision 1 | covered | `:414-458`; names both versions, states no release is recorded at either, points at the entry as the default fix, names the manifest edit as the alternative, offers no resume. `market_version` capture reads jq's status (`:431-433`) and distinguishes empty from failed (`:441`). Read. |
| FR-9 docs / consumer manual restated | partial (in-scope part covered) | Only `toolkit/release.just:30-33` falls in this review's file set; it states the predicate and that the marketplace entry plays no part. `docs/`, `toolkit/README.md` and the changelog are out of this layer's scope. |
| FR-10 toolkit self-release | n/a to these files | Phase 4, human-authorised. `scripts/self-release.sh` is the mechanism but is not itself FR-10. |
| Decision 1 keep the drift refusal, with its own hint | covered | Same as FR-8. |
| Decision 2 failed listing takes the steady-state wording | covered | **Verified** via the `git`-stub-127 run; structurally, `:147` requires `listing_failed -eq 0` and `:144` folds any non-0/1 filter status into `listing_failed=1`. |
| Decision 3 refuse a diverged push route rather than accept it as a bound | covered | Same as FR-6. `url.<base>.pushInsteadOf` is recorded as a stated, unchecked bound at `:166-174` with its reasoning. |
| Shell constraint — filters absorb status 1 only | covered | `semver_tags:294` `{ grep -E … \|\| [ "$?" -eq 1 ]; }`; `version-guard.sh:139-144` binds `grep_status` to its own capture and folds anything above 1 into the restrictive path. |
| Shell constraint — `ls-remote` status read inside an `if`, never a bare substitution | covered for the origin listing | `toolkit/release.sh:338` `\|\| return 1`; `:379` and `:560` read the function's status. `scripts/self-release.sh:89-90`, `:144` *do* use bare substitutions, which the comments at `:86-88` and `:141-143` argue is the safe direction there (a `die` inside `$( )` ends the subshell, leaving an empty result that reads as "missing" → refuses). Sound for those three call sites; `ensure_dist_tag:192` correctly captures into a variable instead, and says why. |
| Shell constraint — the guard never exits non-zero after a deny | covered | **Verified** across three fixtures. Every post-deny statement is inside an `if` condition, a `\|\| …` right-hand side, or an assignment. The residual is `jq` at `:183` failing, which is how the output is produced and has no failure-tolerant form. |

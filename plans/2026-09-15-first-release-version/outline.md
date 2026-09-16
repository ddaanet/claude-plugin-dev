# Outline — the initial manifest version is the initial release

Source brief:
[../2026-09-07-brief-first-release-version-selection.md](../2026-09-07-brief-first-release-version-selection.md).
Triage: [classification.md](classification.md).

## Rules (settled by my human partner, 2026-09-15)

1. Whatever version the initial manifest holds is the initial release. A
   scaffold's version is adopted as-is, never bumped past.
2. A plugin is at its initial release exactly when no tag matches
   `^v[0-9]+\.[0-9]+\.[0-9]+$`. The marketplace entry plays no part.
3. On an initial release, `just release` takes no argument and fails if one is
   given. It publishes the manifest version.
4. The initial template is the official `/plugin-dev:create-plugin`, run before
   this toolkit is installed; it seeds `0.1.0`. The toolkit writes no manifest
   and no version.

Rule 3 is already the behaviour of `release_preflight` (`release.sh:227-236`).
Everything else below is the delta.

## Shell constraints

Three failure modes recur across the changes. The argument for each belongs in
the code comment the change writes, not repeated here:

- **A no-match `grep` exits 1**, which under `set -euo pipefail` kills the
  script at the assignment. Every filter absorbs status 1 only —
  `{ grep -E '…' || [ $? -eq 1 ]; }` — so an empty result is a value and a real
  grep error (2) still fails.
- **`git ls-remote` exits 128** with no `origin` or an unreachable one
  (verified). Its status is read inside an `if`, never a bare substitution, so
  "could not check" reaches the caller instead of killing the script.
- **A hook exiting non-zero for any reason other than 2 is a non-blocking
  error**, and the tool call proceeds. A `version-guard.sh` that dies while
  composing its message therefore allows the edit it had already refused: a
  silent, total bypass. Nothing it computes after deciding may fail.

## Per-file changes

### `toolkit/release.sh` — tdd

- One filter, `semver_tags`, keeps stdin lines matching
  `^v[0-9]+\.[0-9]+\.[0-9]+$`. Two listings feed it, **both newest first** —
  every caller names the newest tag, so neither may be left in an arbitrary
  order:
  - `release_tags` — `git tag --list 'v*' --sort=-v:refname | semver_tags`. Both
    the initial-release check (replacing the two-part predicate at
    `release.sh:225`) and `latest_tag` (`:250`, keeping its `sed -n '1s/^v//p'`)
    use it.
  - `origin_release_tags` — `git ls-remote --tags --sort=-v:refname origin`,
    field 2 with `refs/tags/` stripped, same filter. The `--sort` is
    load-bearing: `ls-remote`'s default order is lexicographic, returning
    `v1.10.0`, `v1.2.3`, `v1.9.0`, so a refusal would name a tag that is not the
    newest once a plugin reaches a two-digit minor or patch.
  - The anchor drops peeled `v1.2.3^{}` lines, `foo/v0.1.0`, `vnext` and `v1.2`
    — the last being the one that would otherwise read as a release. `vnext`
    sorts *above* `v9.9` and `v1.2.3` under `-v:refname`; `v1.2` sorts below
    `v1.2.3`. All verified, git 2.47.3; tests pick tags by that order.
- `release_preflight`, **lost-tags guard first**: when `release_tags` is empty,
  probe `origin_release_tags` before `check-version.sh` (`release.sh:202-206`)
  and so before `bump_commit_tag` tags or `push_branch` pushes.
  - Any semver tag on origin — refuse, naming the newest, hinting
    `git fetch --tags`. Any tag and not only `v$V`: a tagless clone whose
    manifest and entry were hand-advanced to `1.3.0` over a published `v1.2.3`
    finds no `v1.3.0` and would publish the hand-written version, skipping the
    manifest-versus-latest-tag check (`:250-264`) a fetch would trigger.
  - No semver tag — initial release; continue.
  - Listing failed — refuse, saying so and that nothing was done. Fail closed:
    `push_branch` and `push_tag` need origin anyway (`:327,342,355`), so
    proceeding only moves the failure past the local tag.
  - **Before `check-version.sh`**, because a tagless clone of a release whose
    tag landed but whose marketplace bump did not (manifest `1.2.4`, entry
    `1.2.3`) otherwise gets drift advice first, and decision 1's hint could then
    commit `1.2.3` over a public `v1.2.4`.
  - **Before the side effects**, because otherwise the lost-tags case with no
    entry tags `HEAD`, pushes the branch, and dies in `push_tag` (`:360-361`) —
    a re-created annotated tag is a new object, so its sha never matches
    origin's. The stray local tag then makes a re-run read as released and
    `git fetch --tags` refuses to clobber it. `gh release view` (`:371`) only
    skips the create.
  - **Scope.** The probe runs only when `release_tags` is empty. A clone holding
    `v1.0.0` over origin's `v1.2.3` still reads as released and meets the
    existing `:250-264` check. Pre-existing, unchanged; widening the probe would
    put a network round-trip on the common path.
  - `common_preflight` validates `origin` only when there is no marketplace
    entry (`:176-177`), so an initial release with an entry reaches the probe
    with origin otherwise unverified.
  - Drop the `marketplace_entry_exists` conjunct and the comment arguing it is
    load-bearing (`:215-221`). `check-version.sh` still runs before the bump
    refusal; its failure hint follows decision 1.
  - The bump refusal stays, and its hint about publishing another version also
    says to commit the edit: `.claude-plugin/` is not exempt from the clean-tree
    check (`:130-131`).
- `resume_preflight`'s no-tag refusal (`:284-287`) picks its hint from one
  `origin_release_tags` listing:
  - `v$V` on origin — `git fetch --tags`, then `just resume-release`.
  - any other semver tag on origin — `git fetch --tags`, then
    `just release <bump>`. Any tag and not only `v$V`, for the guard's reason:
    an empty local tag set says nothing about what is published. Without this
    branch the next one fires and advises a bare `just release`, which the guard
    refuses on sight — two refusals to reach advice the first one had.
  - otherwise, `release_tags` empty — `just release`, no argument.
  - otherwise — `just release <bump>`, as today.
  - A failed listing falls through to the two local hints: the refusal has no
    side effect, so the probe only improves the advice.
- **`common_preflight` refuses a diverged push route** (decision 3), which is
  what makes `origin_release_tags` evidence about where the release lands.
- `bump_commit_tag`'s initial-release branch (tag `HEAD`, no commit) and
  `marketplace_entry_exists` (create vs bump the entry) stay as they are.
- Header comment (`:11-14`): restate detection per rule 2.

### `toolkit/version-guard.sh` — tdd

- **Message-only branch, same decision.** With no semver `v` tag the agent
  message says the manifest holds `$current`, the version the initial release
  will publish, and that setting it is the maintainer's edit. It still forbids
  bypassing the guard and offers no escape hatch.
  - It must not present `just release` as a route to `$proposed`: that publishes
    `$current`, and an agent asked to set a version would read the recipe as the
    substitute and publish the scaffold's version publicly. The message may say
    what the recipe publishes, not suggest running it for this edit.
  - **The human channel does not branch.** `systemMessage` (`:93`) is a factual
    one-liner, as true on an initial release as in steady state. Only
    `permissionDecisionReason` branches.
- The steady-state message is unchanged. Header comment (`:3-5`, "desync the
  manifest from the latest tag") restated for both cases.
- **The listing never decides.** It runs only after the deny is established
  (after `:78`), so an allowed edit pays nothing for it — and per the third
  shell constraint above, nothing it does may exit non-zero.
- **Failure and emptiness are different answers and are captured separately.**
  Folding every failure into one empty string makes an absent git
  indistinguishable from a project with no tags, and the two take opposite
  wordings (decision 2). The listing is its own command whose status an `if`
  reads; only the filter's no-match status is absorbed. A failed listing yields
  the steady-state wording. The `2>/dev/null` is justified rather than
  reflexive: git's "not a repository" is an expected outcome here, not a
  diagnostic, and `hook-test.sh:66-68` asserts the hook's stderr stays empty.
- Repo-local `GIT_*` variables are cleared for the listing: a `claude` started
  from inside a git hook can pass on a `GIT_DIR` that overrides the discovery
  `-C` would do.
- Accepted bound, stated in a comment: a `CLAUDE_PROJECT_DIR` that is not itself
  a repo but sits inside one lists the enclosing repo's tags (observed while
  probing). It affects the wording only.
- The tag filter is duplicated from `release.sh`, not sourced. `release.sh` runs
  its flow at top level (`release.sh:493-508`) and cannot be sourced, and a
  shared helper would be a new shipped path (`tests/dist-tree-test.sh`, the
  CLAUDE.md Layout list, `tests/doc-sync-test.sh`) for one `grep -E` line. Both
  suites exercise the same tag set, so the copies cannot drift unnoticed.

### `toolkit/release.just`

- Header comment (`:23-29`) already states rules 1, 3 and 4 correctly. What it
  never states is the predicate. Add one sentence: a plugin counts as never
  released when no tag matches `^v[0-9]+\.[0-9]+\.[0-9]+$`, and its marketplace
  entry plays no part. Signatures unchanged.

### `toolkit/check-version.sh`

- No change, under decision 1 or its rejected alternative. It compares the
  manifest against an existing entry as today (`:53-57`) and skips when there is
  none (`:46-51`). It could not branch on initial release in any case: it never
  reads tags. Decision 1's hint is printed by `release.sh:202-206`, which by
  then knows `release_tags` is empty.

## Tests

### `tests/release-test.sh` — red first

`make_virgin`'s comment (`:194-200`) loses "isolates the no-tags half of the
conjunct", and it gains a way to drop the tag locally only, leaving origin's.
Unless stated otherwise a refusal asserts: the named hint, no local tag created,
origin `main` not advanced, `gh` not called, marketplace untouched.

- **Entry at `1.2.3`, no tags, no argument** → publishes `v1.2.3`, manifest and
  marketplace untouched, no new commits. Red: today it bumps to `1.2.4`. The
  scenario at `:625` inverts and is renamed — its title states the opposite of
  rule 2.
- **Same state with `patch`** → refused as a first release. Red: today it
  succeeds.
- **Lost tags, entry present** (tag dropped locally only, one unpushed commit) →
  fetch hint. Red: today it bumps.
- **Lost tags, no entry** → fetch hint. Exit code alone is *not* red: today's
  code already exits 1, in `push_tag`, after tagging and pushing. The hint, the
  absent tag and the unadvanced origin are what fail.
- **Lost tags, hand-advanced** (origin keeps `v1.2.3`, manifest and entry at
  `1.3.0`, no argument) → fetch hint naming `v1.2.3`. Red: today it bumps to
  `1.3.1`. Also fails an implementation probing only `v$V`.
- **Lost tags, origin newest ≠ lexicographic first** (origin has `v1.2.3` and
  `v1.10.0`) → hint names `v1.10.0`. Red without `--sort=-v:refname`; nothing
  else tests the sort.
- **Lost tags over a half-landed release** (origin `v1.2.4`, manifest `1.2.4`,
  entry `1.2.3`) → fetch hint, not the drift hint. Red: today it gives drift.
- **Origin unreachable** (virgin, `set-url` to a missing path) → refusal naming
  the unverifiable probe. Red via the message and the absent tag.
- **Origin absent** (virgin with an entry, then `remote remove origin`) → same.
  With no entry `common_preflight` refuses first, so the entry is what reaches
  the probe.
- **Diverged push route**, one scenario each for `remote.origin.pushurl`,
  `branch.<name>.pushRemote`, `remote.pushDefault` → refused, naming the setting
  and its value. Red: none is consulted today.
- **Only non-semver `v` tags** (`vnext`, `v1.2`) on a virgin `0.1.0` → publishes
  `v0.1.0`. Red: today it refuses on manifest vs latest tag `next`.
- **`vnext` beside `v1.2.3`**, `patch` → releases `v1.2.4`. Red: today `vnext`
  is `latest_tag`. Not `v1.2`, which sorts below.
- **`--resume` on a virgin repo** → hint names `just release`, no argument. Red.
- **`--resume`, tag dropped locally only** (`:361-367`, origin keeps `v1.2.3`) →
  hint names `git fetch --tags` then `just resume-release`. Red.
- **`--resume`, origin holds a semver tag that is not `v$V`** (manifest
  hand-advanced to `1.3.0`) → hint names `git fetch --tags` then
  `just release <bump>`. Red: the ladder's second branch does not exist, and
  without it `release_tags` emptiness sends this state to the no-argument hint.
- **`<bump>` hint** moves to a new fixture: local `v1.2.3` kept, manifest at
  `1.2.4`, no `v1.2.4` anywhere. Green today; a regression guard.
- **Bump-refusal loop** (`:610-623`) stays, and gains an assertion on the commit
  instruction. Red.
- **Initial release, entry disagrees with the manifest** → per decision 1.
- Unchanged: `:634`, `:592`, `:721`.

### `tests/hook-test.sh`

Add `unset $(git rev-parse --local-env-vars)` as `release-test.sh:8-13` does —
`just precommit` runs as this repo's pre-commit hook (`justfile:132-141`) and a
leaked `GIT_DIR` would make a fixture listing read this repo's own tags. The
existing `$proj` is not a git repo (`:28`), so its scenarios exercise the
listing-failure fallback and must pass unchanged. `run_guard` (`:50`) gains a
project argument for the second fixture.

- **`git init` fixture, no tags** → initial-release wording, without the
  steady-state "is the last released version". `assert_deny` also catches the
  exit-1 bypass and stray stderr. Red.
- **Same scenario**: `$proposed` appears nowhere after the deny reason's first
  line. The only way to offer a route to the proposed version is to name it, and
  the opening `$current -> $proposed` is the one legitimate mention. Red.
- **`systemMessage` byte-identical** across the initial-release and steady-state
  scenarios, pinning that only the agent channel branches.
- **Same fixture, only `vnext`** → initial-release wording. Red.
- **Same fixture tagged `v1.2.3`** → steady-state wording. Green; a regression
  guard.
- **`GIT_DIR` leak**: tagless fixture, `GIT_DIR` set to a second fixture
  carrying `v1.2.3` → initial-release wording. Red — without the clearing the
  listing discovers the tagged repo. This tests the guard's own clearing, as
  distinct from the harness hygiene above.
- **Git absent**, via a stub exiting 127 on `guard_path` (`:43`) → still denies,
  steady-state wording. Green; it pins the fallback.

## Docs — inline

- `docs/references/release-flow.md`: "the latest tag" becomes the newest semver
  tag (`:12-14`). Rewrite detection (`:52-59`) in place, tags only, and restate
  the scaffold paragraph (`:33-38`) as rule 1. The brief's rejected options
  become rejected alternatives with their reasons: a guard that allows the edit,
  `--initial`, a baseline tag. The `0.0.0` seeding rejection (`:73-79`) stays;
  rule 4 agrees with it. The two-part conjunct is itself an overturned decision
  and is rewritten as one — `:52-59` today *argues for* it, and CLAUDE.md
  requires the new reasoning replace the old in place: the origin probe covers
  the lost-tags case directly and strictly better, since the conjunct only ever
  protected a lost-tags repo that *had* an entry.
- `docs/references/version-guard.md`: the initial-release message branch, why it
  names no recipe as a route to the proposed version, why only the agent channel
  branches, and why the listing can never turn a deny into an allow.
- `docs/references/recovery.md`: the no-tag refusal's three hints (`:51-54`);
  the lost-tags and diverged-push-route refusals joining the list at `:138-144`,
  with why the probe runs before the drift check; resume on a clone missing
  tags; `check-version.sh` on an initial release (`:19-32`), per decision 1.
- `docs/design.md`: rewrite the release-flow conclusion (`:105-107`) and add the
  message branch to the version-guard conclusion (`:146-150`).
- `toolkit/README.md` Conventions bullet (`:175-179`): detection by semver tag,
  the initial version coming from `/plugin-dev:create-plugin`'s manifest, and a
  different version being the maintainer's committed edit.
- Unchanged, checked: root `README.md` carries no first-release text, and
  `tests/doc-sync-test.sh` compares only the install/update command blocks. No
  shipped file is added or removed, so the CLAUDE.md Layout list and
  `tests/dist-tree-test.sh` need no change.
- A changelog record under `docs/changelog/`, dated the day it is written, plus
  its index line. That line says outright that detection semantics change — a
  marketplace entry no longer disqualifies a first release. The changelog does
  not ship, so the pointer is the only place a consumer learns it.
- Migration note: none. The consumers beside this repo (`handoff`, `gitmoji`,
  `gitlore`, `cwd-safety`, `shell-gotchas`) carry only `vX.Y.Z` tags, checked.
  The residual: a plugin released only under non-semver or non-`v` tags, with an
  entry, would now republish its manifest version. No known consumer is in that
  state.

## Scope

**IN:** `release.sh` (including `common_preflight`), `version-guard.sh`, the
`release.just` header, both test suites, the docs above, and the toolkit
self-release that ships them.

**OUT:**

- Item B, the sandbox `excludedCommands` README note.
- Choosing an initial version other than the manifest's through the recipe.
- Refusing a hand-seeded `0.0.0`.
- `install.sh`: it neither writes nor validates `.version`.
- Code changes to `check-version.sh`, which decision 1 leaves untouched.
- Root `README.md` and CLAUDE.md, per the check above.
- Editing `plugin-craft:toolkit-release`; only a note goes there after release.
- **Partial tag loss.** A clone holding `v1.0.0` over origin's `v1.2.3` still
  reads as released. Pre-existing, unchanged here.

## Decisions

1. **A marketplace entry that disagrees with the manifest on an initial
   release.** `check-version.sh` refuses it as drift (`release.sh:202-206`) and
   hints `just resume-release`; resume finds no tag and points back at
   `just release` (`:283-288`), which refuses on drift again — a loop with no
   exit but a hand edit. The lost-tags guard runs first and decision 3 refuses a
   diverged push route, so this state is reached only when the plugin is
   verifiably unpublished.

   **Decided:** keep the refusal. An entry naming a version that was never
   released is an anomaly, not noise — a plugin published under another name, an
   entry belonging to a different plugin, a manifest meant to hold that version.
   Overwriting silently picks one and hides the rest, and surfacing it costs one
   hand edit on a path that runs at most once in a plugin's life. The hint names
   both versions, says no release is recorded at either, and points at the entry
   as the one to correct — `bump_marketplace` would write the manifest version
   there on a successful first release anyway — while noting the manifest is the
   right edit if that version is the intended one. Resume is not offered. Add a
   red scenario for the hint.

   **Rejected:** skip `check-version.sh` when no semver tag exists anywhere and
   let `bump_marketplace` overwrite the entry.

2. **The hook's message when the tag listing fails** (git absent, not a repo).
   The deny is unaffected either way, so this is message quality, not
   correctness.

   **Decided:** the steady-state message. The plugin's state is unknown, and the
   two wordings are not symmetric in what they invite: steady-state says the
   version is release-managed and points at the recipe, while initial-release
   wording tells the agent the maintainer is free to choose what this first
   ships as — an invitation to pick a version for a plugin that may already be
   published. The restrictive one is the right answer to "don't know", and it is
   today's behaviour, so the existing non-repo scenarios stay valid.

   **Rejected:** the initial-release wording, or a third wording true in both
   states — never false, but a third message to write, test and keep in step for
   a path that fires only when git is missing or the project is not a repo.

3. **Origin fetched from one place and pushed to another.** `ls-remote origin`
   reads origin's fetch URL. Three settings redirect a push:
   `remote.origin .pushurl`, `branch.<name>.pushRemote`, `remote.pushDefault`.
   They do not reach the same commands — `push_branch`'s unqualified `git push`
   (`release.sh:342`) follows all three in that precedence, while `push_tag`'s
   `git push origin "$tag"` (`:365`) names its remote and is redirected only by
   `pushurl` — so the branch and the tag can reach different repositories. Under
   any of them the probe reads a repository the release does not publish to, and
   `push_tag`'s published-tag check (`:355`) is blind the same way.

   **Decided:** `common_preflight` refuses when any of the three is set, before
   any side effect and on both `release` and `--resume`, naming the setting and
   its value. The recovery is to unset it or point it at origin. Each
   `git config --get` exits 1 when unset, so each read absorbs that status.

   **Rejected:** an accepted bound in a comment, with no test. It would leave
   the probe unable to say anything about where the release lands, and decision
   1 rests on the probe being trustworthy.

## Dependencies

`release.sh` and `version-guard.sh` are independent and can be taken in either
order. Within each, tests come first: both are `tdd`, so the red scenarios land
and are shown failing against unchanged code before the implementation.

The two share one fixture convention rather than any code. Each suite exercises
the same tag set — `vnext`, `v1.2`, `v1.2.3` — which is what makes the
duplicated semver filter safe: a copy that drifts fails in one of the two
suites. Keep the set in step when either side changes it.

Docs follow the code they describe; the changelog record is written last among
them. Toolkit self-release last, `minor` — the toolkit is pre-1.0, where a minor
bump is the conventional home for a behaviour change, and a marketplace entry no
longer disqualifying a first release is one.

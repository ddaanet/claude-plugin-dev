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

## What changes against the current code

Rule 3 is already the behaviour of `release_preflight` (`release.sh:227-241`).
The changes are:

- **Detection.** Rule 2 replaces the two-part predicate: no `v*` tag *and* no
  marketplace entry (`release.sh:225`).
- **Tag filter.** The `v*` glob becomes a semver filter, in the detection and in
  the `latest_tag` computation (`release.sh:250`).
- **Lost-tags guard.** Dropping the marketplace conjunct makes a clone missing
  its tags read as never released. A new origin probe refuses that case before
  any side effect.
- **Wording.** The places that contradict the rules are fixed. That includes two
  refusals whose hints are wrong on an initial release: `resume_preflight`
  points at `just release <bump>` (`release.sh:286`), which rule 3 refuses, and
  the `check-version.sh` drift refusal points at `just resume-release`
  (`release.sh:204`), which cannot help without a tag (see Open questions).

## Per-file changes

### `toolkit/release.sh` — tdd

- One helper, `release_tags`, lists local tags matching
  `^v[0-9]+\.[0-9]+\.[0-9]+$`, newest first:
  `git tag --list 'v*' --sort=-v:refname` piped through `grep -E`. Both the
  initial-release check and the `latest_tag` computation use it (the latter
  takes the first line with the existing `sed -n '1s/^v//p'`). A stray `vnext`
  or `v1.2` neither marks a plugin released nor reads as the newest release.
  - `grep` exits 1 when nothing matches, which is exactly the initial-release
    case. Under `set -euo pipefail` a `tags=$(release_tags)` assignment then
    kills the script with no message. The helper absorbs status 1 only —
    `{ grep -E '…' || [ $? -eq 1 ]; }` — so an empty result exits 0 and a real
    grep error (2) still fails. The existing verbatim first-release scenario
    (`release-test.sh:592`, no tags at all) catches a helper that does not.
  - `vnext` sorts *above* `v9.9` and `v1.2.3` under `-v:refname`; `v1.2` sorts
    below `v1.2.3` (verified, git 2.47.3). Tests pick tags by that order.
- `release_preflight`:
  - Initial release when `release_tags` is empty. Drop the
    `marketplace_entry_exists` conjunct and the comment arguing it is
    load-bearing (`release.sh:215-221`).
  - The bump refusal stays. Its hint about publishing another version also says
    to commit the edit: `.claude-plugin/` is not exempt from the clean-tree
    check (`release.sh:130-131`).
  - `check-version.sh` still runs first (`release.sh:202-206`). Its failure hint
    becomes initial-release aware per Open question 1, so detection is computed
    before that branch rather than after it.
- **New guard for the lost-tags case**, in `release_preflight`'s initial-release
  branch, after the bump refusal and before `return`. That is before
  `bump_commit_tag` creates the local tag and before `push_branch` pushes
  anything.
  - Probe the exact ref: `git ls-remote --exit-code origin "refs/tags/$tag"`. A
    bare `v$V` pattern is tail-matched and also hits `refs/tags/foo/v0.1.0`
    (verified).
  - Branch on the status inside an `if`/`case`, never a bare substitution under
    errexit, so a git fatal is never the last word:
    - `0` — `v$V` is published: refuse, with a `git fetch --tags` hint.
    - `2` — no such ref: proceed.
    - anything else (`128` for no `origin` remote or an unreachable one,
      verified) — refuse, saying the initial release could not be checked
      against origin and nothing was done. Fail closed: `push_branch` and
      `push_tag` need origin anyway (`release.sh:327,342,355`), so proceeding
      only moves the failure past the local tag.
  - `common_preflight` validates `origin` only when there is no marketplace
    entry (`release.sh:176-177`), so an initial release with an entry reaches
    this probe with origin unverified.
  - Why it must precede the side effects. Without it, the lost-tags case with no
    entry tags `HEAD` locally, pushes the branch, and only then dies in
    `push_tag` (`release.sh:360-361`): a re-created annotated tag is a new tag
    object, so its sha never matches origin's. The stray local tag then makes a
    re-run read as released, and `git fetch --tags` refuses to clobber it. With
    an entry, today's code never reaches that far; after the change it would.
    `gh release view` (`release.sh:371`) only skips the create.
- `resume_preflight`'s no-tag hint (`release.sh:284-287`): when `release_tags`
  is empty, name `just release` with no argument; otherwise keep
  `just release <bump>`.
- `bump_commit_tag`'s initial-release branch (tag `HEAD`, no commit) and
  `marketplace_entry_exists` (create vs bump the entry) stay as they are.
- Header comment (`release.sh:11-14`): restate detection per rule 2.

### `toolkit/version-guard.sh` — tdd

- **Message-only branch, same decision.** When the project has no semver `v`
  tag, the agent message says the manifest holds `$current`, the version the
  initial release will publish, and that setting it is the maintainer's edit. It
  still forbids bypassing the guard and offers no escape hatch.
  - It must not present `just release` as a route to `$proposed`: that publishes
    `$current`, and an agent asked to set a version would otherwise read the
    recipe as the substitute and publish the scaffold's version publicly. The
    message may say what the recipe publishes, not suggest running it for this
    edit.
- The steady-state message is unchanged. Header comment (`version-guard.sh:3-5`,
  "desync the manifest from the latest tag") restated for both cases.
- **The listing never decides.** It runs only after the deny is established
  (after `version-guard.sh:78`), so an allowed edit pays nothing for it.
  - A bare `tags=$(git … | grep -E …)` under `set -euo pipefail`
    (`version-guard.sh:8`) exits 1 on no match — the very case this branch
    exists for — and 127 or 128 when git is absent or the project is not a repo,
    all before the JSON is printed. Any non-zero exit other than 2 is a
    non-blocking hook error, so the edit goes through: a silent, total bypass.
    The listing is `git -C "$project" tag --list 'v*' 2>/dev/null` with every
    failure tolerated, and stderr stays empty (`hook-test.sh:66-68` asserts it).
  - When the listing fails, the message is the steady-state one (Open question
    2).
  - Repo-local `GIT_*` variables are cleared for the listing: a `claude` started
    from inside a git hook can pass on a `GIT_DIR` that overrides the discovery
    `-C` would do.
  - Accepted bound, stated in a comment: a `CLAUDE_PROJECT_DIR` that is not
    itself a repo but sits inside one lists the enclosing repo's tags (observed
    while probing). It affects the wording only.
- The tag filter is duplicated from `release.sh`, not sourced. `release.sh` runs
  its flow at top level (`release.sh:493-508`) and cannot be sourced, and a
  shared helper file would be a new shipped path (`tests/dist-tree-test.sh`, the
  CLAUDE.md Layout list, `tests/doc-sync-test.sh`) for one `grep -E` line. Both
  test suites exercise the same tag set (`vnext`, `v1.2`, `v1.2.3`) so the two
  copies cannot drift unnoticed.

### `toolkit/release.just`

- Header comment (`release.just:23-29`): detection per rule 2. Signatures
  unchanged.

### `toolkit/check-version.sh`

- No change under Open question 1's default. On an initial release it compares
  the manifest against an existing entry exactly as today
  (`check-version.sh:53-57`), and skips when there is no entry
  (`check-version.sh:46-51`).

### Tests

- `tests/release-test.sh` (red first). Each scenario names what makes it red
  against unchanged code:
  - `make_virgin`'s comment (`release-test.sh:194-200`) loses "isolates the
    no-tags half of the conjunct". It gains a way to drop the tag locally only,
    leaving origin's.
  - "a marketplace entry with no tags is not a first release" (`:625`) inverts,
    and must run with **no argument**: with `patch` it is now the bump refusal.
    `new_sandbox "1.2.3"` + `make_virgin "1.2.3"`: publishes `v1.2.3`, manifest
    untouched, no new commit, marketplace still `1.2.3` with no new marketplace
    commit. Red: today it bumps to `1.2.4`.
  - Same state with `patch`: refused as a first release. Red: today it succeeds.
  - Lost tags, entry present: tag dropped locally only, plus one unpushed
    commit. Refused with the fetch hint; no local `v1.2.3`; origin `main` not
    advanced; `gh` not called; marketplace untouched. Red: today it bumps.
  - Lost tags, no entry: same assertions. Exit code alone is **not** red —
    today's code already exits 1, in `push_tag`, after tagging and pushing the
    branch. The fetch hint, the absent local tag and the unadvanced origin
    `main` are what fail.
  - Origin unreachable: virgin, `git remote set-url origin` to a missing path.
    Refused naming the unverifiable probe; no local tag; `gh` not called. Red
    via the message and the absent tag.
  - Origin absent: virgin with an entry at the manifest version, then
    `git remote remove origin`. Same assertions. With no entry
    `common_preflight` refuses first, so the entry is what reaches the probe.
  - Only non-semver `v` tags (`vnext`, `v1.2`) on a virgin `0.1.0`: publishes
    `v0.1.0`. Red: today it refuses on manifest vs latest tag `next`.
  - `vnext` beside `v1.2.3` (`new_sandbox "1.2.3"`): `patch` releases `v1.2.4`.
    Red: today `vnext` is `latest_tag`. Not `v1.2`, which sorts below.
  - `--resume` on a virgin repo: the hint names `just release` with no argument
    and not `<bump>`. Red. `:367` keeps the tagged-repo hint.
  - The bump-refusal loop (`:610-623`) also asserts the commit instruction. Red.
  - Initial release with the entry at a different version than the manifest: per
    Open question 1.
  - "tags with no marketplace entry is not a first release" (`:634`), the bump
    refusal loop, the verbatim scenario and the non-v tag scenario (`:721`)
    stay.
- `tests/hook-test.sh`:
  - Add `unset $(git rev-parse --local-env-vars)` as `release-test.sh:8-13`
    does. `just precommit` runs as this repo's own pre-commit hook
    (`justfile:132-139`), and a leaked `GIT_DIR` would make a fixture listing
    read this repo's own semver tags.
  - The existing `$proj` is not a git repo (`hook-test.sh:28`). Its scenarios
    therefore exercise the listing-failure fallback and must pass unchanged.
  - `run_guard` pins `CLAUDE_PROJECT_DIR="$proj"` (`hook-test.sh:50`); it gains
    a project argument so the scenarios below can use a second fixture.
  - New `git init` fixture, no tags: Edit bump denies with the initial-release
    wording, and without the steady-state "is the last released version".
    `assert_deny` also catches the exit-1 bypass and stray stderr. Red.
  - Same fixture with only `vnext`: initial-release wording. Red.
  - Same fixture tagged `v1.2.3`: steady-state wording. Green against unchanged
    code; a regression guard, not a red test.
  - Git absent, via a `git` stub exiting 127 on `guard_path`
    (`hook-test.sh:43`): still denies, steady-state wording. Also green today;
    it pins the fallback.

### Docs — inline

- `docs/references/release-flow.md`:
  - "Manifest version represents the *last released* version" (`:12-14`): "the
    latest tag" becomes the newest semver tag.
  - "First release publishes the manifest version as-is": rewrite detection
    (`:52-59`) in place, tags only, with the lost-tags case and its origin probe
    as the cost it accepts. Restate the scaffold paragraph (`:33-38`) as rule 1.
    The brief's rejected options become rejected alternatives, each with its
    reason: a guard that allows the edit, `--initial`, and a baseline tag. The
    existing `0.0.0` seeding rejection (`:73-79`) stays; rule 4 agrees with it.
- `docs/references/version-guard.md`: the initial-release message branch, why it
  names no recipe as a route to the proposed version, and why the listing can
  never turn a deny into an allow.
- `docs/references/recovery.md`:
  - "Recovery" (`:51-54`): the no-tag refusal points at `just release <bump>`,
    or at `just release` on an initial release.
  - "The refusal is where the operational knowledge lives" (`:138-144`): the
    lost-tags refusal joins the first-release and version-drift refusals.
  - "`check-version.sh`" (`:19-32`): its behaviour on an initial release, per
    Open question 1.
- `docs/design.md`: rewrite the release-flow conclusion line (`:105-107`), and
  add the message branch to the version-guard conclusion (`:146-150`).
- `toolkit/README.md` Conventions bullet (`:175-179`): detection by semver tag,
  the initial version coming from `/plugin-dev:create-plugin`'s manifest, and a
  different version being the maintainer's committed edit.
- Unchanged, checked: root `README.md` carries no first-release text, and
  `tests/doc-sync-test.sh` compares only the install/update command blocks,
  which this does not touch. No shipped file is added or removed, so the
  CLAUDE.md Layout list and `tests/dist-tree-test.sh` need no change.
- `docs/changelog/2026-09-15-initial-release-detected-by-semver-tag.md` plus its
  index line.
- Migration note: none. The consumers mounted beside this repo (`handoff`,
  `gitmoji`, `gitlore`, `cwd-safety`, `shell-gotchas`) carry only `vX.Y.Z` `v`
  tags, checked. Unreleased plugins behave as before, except that a marketplace
  entry no longer disqualifies them. The residual: a plugin released only under
  non-semver or non-`v` tags, with an entry, would now republish its manifest
  version. The origin probe does not catch it, since it checks `v$V` only. No
  known consumer is in that state.

## Scope

**IN:** item A, as the per-file changes above: `release.sh`, `version-guard.sh`,
the `release.just` header, both test suites, and the docs listed.

**OUT:**

- Item B, the sandbox `excludedCommands` README note.
- Choosing an initial version other than the manifest's through the recipe.
- Refusing a hand-seeded `0.0.0`.
- `install.sh`: it neither writes nor validates `.version`.
- Code changes to `check-version.sh`, unless Open question 1 is answered the
  other way.
- Root `README.md` and CLAUDE.md, per the check above.
- Editing `plugin-craft:toolkit-release`; only a note goes there after release.

## Open questions

1. **A marketplace entry that disagrees with the manifest on an initial
   release.** `check-version.sh` refuses it as drift (`release.sh:202-206`) and
   hints `just resume-release`. Resume finds no tag and points back at
   `just release` (`release.sh:283-288`), which refuses on drift again: a loop
   with no exit but a hand edit. Rule 2 settles detection, not this gate.
   **Default:** keep the refusal. On an initial release its hint names both
   versions and says the maintainer reconciles the entry or the manifest, since
   resume cannot help without a tag; add a red scenario for that hint.
   Alternative: skip `check-version.sh` when no semver tag exists, and let
   `bump_marketplace` overwrite the entry to the manifest version.
2. **The hook's message when the tag listing fails** (git absent, not a repo).
   The deny is unaffected either way. **Default:** the steady-state message,
   which is today's behaviour and keeps the existing non-repo scenarios valid.
   Alternative: the initial-release wording, or a third wording true in both
   states.

## Dependencies

`release.sh` and `version-guard.sh` are independent, but share the tag set their
tests use. Docs follow. Toolkit self-release (`minor`: detection semantics
change) last.

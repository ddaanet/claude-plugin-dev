# Runbook — the initial manifest version is the initial release

Design: [outline.md](outline.md). Triage:
[classification.md](classification.md). Recall:
[recall-artifact.md](recall-artifact.md). Source brief:
[../2026-09-07-brief-first-release-version-selection.md](../2026-09-07-brief-first-release-version-selection.md).

## Requirements

Rules 1-4 and Decisions 1-3 of the outline, given IDs for traceability.

- **FR-1** A plugin's initial release publishes the manifest version as it
  stands; a scaffold's version is adopted, never bumped past.
- **FR-2** A plugin is at its initial release exactly when no tag matches
  `^v[0-9]+\.[0-9]+\.[0-9]+$`. The marketplace entry plays no part.
- **FR-3** An initial release takes no bump argument and refuses one, naming the
  version it would publish and the maintainer's edit that changes it.
- **FR-4** When no local semver tag exists, `release_preflight` probes origin's
  tags before `check-version.sh` and before any side effect, and refuses both a
  lost-tags repo and a listing it could not perform.
- **FR-5** `resume_preflight`'s no-tag refusal picks its hint from one origin
  listing: fetch-then-resume, fetch-then-release, bare release, or
  release-with-bump.
- **FR-6** `common_preflight` refuses a diverged push route
  (`remote.origin.pushurl`, `branch.<name>.pushRemote`, `remote.pushDefault`),
  naming the setting and its value, on both `release` and `--resume`.
- **FR-7** The version guard's agent message branches on the same predicate,
  naming no recipe as a route to the proposed version; the human channel does
  not branch, and a failed listing yields the steady-state wording.
- **FR-8** An initial release whose marketplace entry disagrees with the
  manifest is still refused, with a hint that names both versions and points at
  the entry.
- **FR-9** Design nodes, hub, consumer manual and changelog record restated for
  the new semantics.
- **FR-10** Toolkit self-release shipping all of it.

| Requirement | Phase | Items | Notes |
|---|---|---|---|
| FR-1 | 1 | 1.1 | Slice 1 |
| FR-2 | 1, 2 | 1.1, 2.1 | Same predicate, duplicated filter |
| FR-3 | 1 | 1.1 | Existing behaviour; slice 1 adds the commit instruction |
| FR-4 | 1 | 1.2 | Slices 1-5 |
| FR-5 | 1 | 1.4 | Depends on 1.2's origin listing |
| FR-6 | 1 | 1.3 | What makes the origin listing evidence |
| FR-7 | 2 | 2.1 | Message-only branch |
| FR-8 | 1 | 1.2 | Slice 6; Decision 1's trust in the probe also rests on 1.3 |
| FR-9 | 3 | 3.1-3.6 | Inline |
| FR-10 | 4 | 4.1 | Human-authorised |

## Standing constraints (every item in Phases 1 and 2)

- **A no-match `grep` exits 1** and kills the script under `set -euo pipefail`.
  Every filter absorbs status 1 only — `{ grep -E '…' || [ $? -eq 1 ]; }` — so
  an empty result is a value and a real grep error still fails. The reason is
  written in the code comment.
- **`git ls-remote` exits 128** with no `origin` or an unreachable one. Its
  status is read inside an `if`, never a bare substitution.
- **A hook exiting non-zero for any reason other than 2 is non-blocking**, so
  nothing `version-guard.sh` computes after deciding to deny may fail.
- **Red first, against the code as it stands at that slice.** Each slice's tests
  land and are shown failing on their own assertion before its implementation.
  Where that failure is against unchanged code the slice says so; where it is
  against the narrowest implementation that passes every earlier slice, the
  `Red:` line names that implementation. A slice marked **guard** is green when
  it lands and must not be forced red — it pins a property the next plausible
  implementation would break.
- **`just precommit` green** before each slice commit. It runs `bash -n`,
  shellcheck, `_import-check`, the docs cap and the doc-sync check, and both
  suites via the repo's own pre-commit hook.
- **One fixture tag set across both suites** — `vnext`, `v1.2`, `v1.2.3`. It is
  what makes the duplicated semver filter safe; keep it in step when either side
  changes it. Item 1.2 slice 3 adds `v1.9.0`, `v1.10.0`, `v1.11.0` on top, for
  ordering rather than filtering — all three pass either filter.

## Phase 1: release.sh (type: tdd)

Post-phase state for Phase 3: `toolkit/release.sh` carries `semver_tags`,
`release_tags`, `origin_release_tags`, a restated header comment, and no
`marketplace_entry_exists` conjunct in the detection.

`tests/release-test.sh:592`, `:634` and `:721` stay green unmodified throughout
— the cheapest check that the new predicate did not shift the old contract.
`make_virgin` deletes origin's tag as well as the local one (`:201-202`,
verified), so no existing scenario reaches the origin probe with a tag on
origin: that is what lets Item 1.1 land before Item 1.2, green at each boundary.

- Item 1.1: toolkit/release.sh — detect the initial release by the absence of a
  semver tag, in `release_preflight`. Adds the `semver_tags` filter and the
  `release_tags` listing, replaces the two-part predicate at `:225`, routes
  `latest_tag` (`:250`) through the filter, drops the `marketplace_entry_exists`
  conjunct and the comment arguing it is load-bearing (`:215-221`), restates the
  header comment (`:11-14`), and adds the commit instruction to the bump
  refusal's hint (`:227-235`). The `marketplace_entry_exists` variable itself
  stays: `bump_marketplace` reads it (`:383`, `:455`) to choose between creating
  and bumping the entry. Only the detection conjunct goes. `bump_commit_tag`'s
  initial-release branch is unchanged.

  - Requirements: FR-1, FR-2, FR-3.
  - Slices:

    1. External contract: the scenario at `tests/release-test.sh:625` inverts
       and is renamed — a marketplace entry no longer disqualifies a first
       release. `new_sandbox "1.2.3"` + `make_virgin "1.2.3"` (no tag locally or
       on origin), no argument: asserts `Release v1.2.3 complete`, the manifest
       still `1.2.3`, `HEAD` unchanged from before the run,
       `refs/tags/v1.2.3^{commit}` equal to that `HEAD`, the marketplace still
       `1.2.3` and its `HEAD` unmoved. Second test, same fixture with `patch`:
       exit 1, output contains `never been released`, `git tag --list 'v*'`
       empty, `$GH_LOG` empty. Third, in the existing bump-refusal loop at
       `:610-623`: the hint contains `commit that edit` beside the existing
       `set .version in .claude-plugin/plugin.json`, because `.claude-plugin/`
       is not exempt from the clean-tree check. `make_virgin`'s comment
       (`:194-200`) loses "isolates the no-tags half of the conjunct".

    2. Non-semver `v` tags are not releases: new scenario, `new_sandbox ""` +
       `make_virgin "0.1.0"` then `git tag vnext` and `git tag v1.2` on `HEAD`,
       no argument: asserts `Release v0.1.0 complete` and that
       `refs/tags/v0.1.0` exists. Red: today the manifest-versus-latest-tag
       check refuses with `does not match latest tag (vnext)`.
    3. `latest_tag` skips a non-semver tag that sorts above the newest release:
       `new_sandbox "1.2.3"` (the fixture keeps `v1.2.3`), add `vnext` and
       `v1.2`, run `patch`: asserts `Release v1.2.4 complete` and the manifest
       at `1.2.4`. Red: today `vnext` is `latest_tag` and the run refuses.
  - Interfaces:

    - `semver_tags()` — stdin to stdout filter, keeps lines matching
      `^v[0-9]+\.[0-9]+\.[0-9]+$`, exits 0 on no match
    - `release_tags()` — no arguments, prints local semver tags newest first
      (`git tag --list 'v*' --sort=-v:refname | semver_tags`)
    - global `first_release` (0|1), `V` (version, no `v`), `tag` (`v$V`)

- Item 1.2: toolkit/release.sh — the lost-tags origin probe, first in
  `release_preflight`, before `check-version.sh` (`:202-206`) and so before
  `bump_commit_tag` and `push_branch`. Runs only when `release_tags` is empty.
  It also branches `release_preflight`'s `check-version.sh` failure hint
  (`:202-206`): with no semver tag locally or on origin the plugin is verifiably
  unpublished, so that hint follows Decision 1 instead of offering resume (slice
  6). `tests/release-test.sh` gains a helper that deletes a tag locally while
  leaving origin's in place, used by slices 1-4.

  - Requirements: FR-4, FR-8.
  - Depends on: Item 1.1
  - Slices:

    1. External contract: `new_sandbox "1.2.3"`, `v1.2.3` dropped locally only,
       one unpushed commit on `main`, run `patch`: exit 1, output names `v1.2.3`
       and `git fetch --tags` and does **not** name `never been released`,
       `git tag --list 'v*'` empty, origin's `refs/heads/main` still at the
       pre-run sha, `$GH_LOG` empty, marketplace still `1.2.3`. That absence is
       load-bearing: with Item 1.1 landed the bump refusal also exits 1 naming
       `v1.2.3`, so it is what pins the probe ahead of it. Second test,
       `new_sandbox ""` with the same local-only drop and no argument: same
       hint, and the same absent-tag and unadvanced-origin assertions — exit 1
       alone is not red, since today's code already exits 1 in `push_tag` after
       tagging and pushing.
    2. Any semver tag on origin refuses, not only `v$V`: `new_sandbox "1.3.0"`,
       manifest hand-advanced to `1.3.0`, committed and pushed, `v1.2.3` dropped
       locally only, no argument: exit 1, hint names `v1.2.3` and
       `git fetch --tags`, no `v1.3.0` tag locally or on origin, `$GH_LOG`
       empty, marketplace still `1.3.0`. Red: with Item 1.1 landed and no probe
       yet, this state reads as a first release and *publishes* `v1.3.0` — tag
       pushed, `gh release create` called — which is the outcome the probe
       exists to stop. (Unchanged code bumped to `1.3.1` instead; the danger
       arrives with Item 1.1.) Also fails an implementation probing only for
       `v$V`.
    3. The origin listing is version-sorted: `new_sandbox "1.2.3"`, `v1.2.3`
       dropped locally only, then `v1.9.0`, `v1.10.0` and `v1.11.0` created,
       pushed and dropped locally — run `patch`: the hint names `v1.11.0` and
       neither `v1.10.0` nor `v1.9.0`. Red without `--sort=-v:refname`:
       `ls-remote`'s own order is lexicographic by refname —
       `v1.10.0 v1.11.0 v1.9.0` (verified, git 2.47.3) — so the first line and
       the last are both the wrong tag. A `v1.2.3`/`v1.10.0` pair would not be
       red at all: there the lexicographically first line is already the newest.
       Nothing else tests the sort.
    4. The probe precedes the drift check: `new_sandbox "1.2.3"`, `v1.2.3`
       deleted locally and on origin, manifest hand-advanced to `1.2.4` and
       committed, `v1.2.4` created, pushed and dropped locally — entry still
       `1.2.3`, no argument: exit 1 with the fetch hint naming `v1.2.4`, and the
       output contains neither `version drift` nor `just resume-release`. Red:
       today `check-version.sh` gives drift advice whose remedy would commit
       `1.2.3` over a public `v1.2.4`.
    5. A listing that failed refuses, saying nothing was done: two tests, each
       asserting exit 1, a message naming the unverifiable probe,
       `git tag --list 'v*'` empty and `$GH_LOG` empty — (a)
       `new_sandbox "1.2.3"` + `make_virgin "1.2.3"` with origin's URL pointed
       at a path that does not exist; (b) the same fixture with
       `git remote remove origin`. Both breakages come after `make_virgin`,
       which pushes. The entry is what lets (b) reach the probe: with none,
       `common_preflight` refuses first at `:176-177`.
    6. Decision 1 — an initial release whose entry disagrees with the manifest
       is still refused: `new_sandbox "1.2.3"` + `make_virgin "0.1.0"`, no
       argument: exit 1, the hint names both `0.1.0` and `1.2.3`, says no
       release is recorded at either, points at the marketplace entry as the one
       to correct, mentions setting the manifest instead if that version is the
       intended one, and does not contain `just resume-release`. No tag created,
       `$GH_LOG` empty. Red: today the hint offers resume.
  - Interfaces:

    - `origin_release_tags()` — no arguments, prints origin's semver tags newest
      first from `git ls-remote --tags --sort=-v:refname origin` — the sort's
    reason (lexicographic refname order is not version order) belongs in its
    code comment, as the other shell constraints do — field 2 with `refs/tags/`
    stripped; exits non-zero when `ls-remote` failed, and that status is read by
    an `if`, never by a bare substitution

- Item 1.3: toolkit/release.sh — `common_preflight` refuses a diverged push
  route, before any side effect and in both modes. Each `git config --get` exits
  1 when unset, so each read absorbs that status.

  - Requirements: FR-6.
  - Slices:

    1. External contract, one test per setting in a loop over
       `remote.origin.pushurl`, `branch.main.pushRemote` and
       `remote.pushDefault`, each redirecting the push to a second bare repo.
       The two forms differ: `pushurl` takes that repo's path, while
       `pushRemote` and `pushDefault` take a remote *name*, so the fixture adds
       `git remote add other <that repo>` first and sets them to `other`. Fresh
       `new_sandbox "1.2.3"` per setting, `release.sh patch` — exit 1, output
       contains the setting's key and the value it was set to (the path, or
       `other`), no `v1.2.4` tag, `$GH_LOG` empty, marketplace still `1.2.3`.
       Red: none of the three is consulted today.
    2. The same refusal on resume: healthy fixture with `remote.origin.pushurl`
       set, `release.sh --resume` — exit 1, output names the key, `$GH_LOG`
       empty.

- Item 1.4: toolkit/release.sh — `resume_preflight`'s no-tag refusal
  (`:284-287`) picks its hint from one `origin_release_tags` listing. A failed
  listing falls through to the two local hints: the refusal has no side effect,
  so the probe only improves the advice.

  - Requirements: FR-5.
  - Depends on: Item 1.2
  - Slices:

    1. External contract, a virgin repo: `new_sandbox ""` +
       `make_virgin "0.1.0"`, `--resume` — exit 1, output contains
       `no tag v0.1.0 for plugin.json version 0.1.0` and a hint naming
       `just release` with no bump argument, and does not contain
       `just release <bump>`. Red: today it advises the bump form, which a first
       release refuses on sight.
    2. `v$V` on origin: this is the existing scenario at `:361-367`, whose
       fixture (`new_sandbox "1.2.3"`, `v1.2.3` deleted locally, origin's kept)
       already matches. Its assertions are rewritten in place, not duplicated
       beside it — its current `just release <bump>` assertion fails the moment
       this slice's branch lands, so leaving it would break the suite at this
       slice's green. `no tag v1.2.3 for plugin.json version 1.2.3` stays; the
       hint now names `git fetch --tags` and then `just resume-release`, and not
       `just release <bump>`. Slice 4 re-establishes the `<bump>` coverage this
       removes.
    3. A different semver tag on origin: `new_sandbox "1.3.0"`, manifest
       hand-advanced to `1.3.0` and committed, `v1.2.3` dropped locally only,
       `--resume` — the hint names `git fetch --tags` and then
       `just release <bump>`. Red: without this branch `release_tags` emptiness
       sends this state to slice 1's no-argument hint, which the release guard
       then refuses — two refusals to reach advice the first one had.
    4. The local hints survive: a new scenario re-establishes the `<bump>` hint
       slice 2 rewrote away — `new_sandbox "1.2.3"` keeping `v1.2.3` locally and
       deleting it from origin, manifest hand-advanced to `1.2.4` and committed
       — `--resume` gives `just release <bump>` and no `git fetch --tags`.
       Deleting origin's copy is what makes branch 4 fire rather than branch 2,
       and the kept local tag is what skips branch 3 (verified against both).
       Guard. Second test, `new_sandbox "1.2.3"` + `make_virgin "1.2.3"` +
       `git remote remove origin`, `--resume`: exit 1,
       `no tag v1.2.3 for plugin.json version 1.2.3`, the hint names
       `just release` with no argument, and the output carries no probe-failure
       wording. Guard against an implementation reading the listing in a bare
       substitution — errexit kills the script there — or refusing outright when
       it fails.

## Phase 2: version-guard.sh (type: tdd)

Independent of Phase 1 and takeable before it; the filter is duplicated rather
than sourced, because `release.sh` runs its flow at top level and cannot be
sourced, and a shared helper would be a new shipped path for one `grep -E` line.

- Item 2.1: toolkit/version-guard.sh — the deny reason branches on the same
  predicate. The listing runs only after the deny is established (after `:78`),
  clears repo-local `GIT_*` variables, and captures a failed listing separately
  from an empty one; a failed listing yields the steady-state wording. The
  `2>/dev/null` on the listing carries its justification inline: git's "not a
  repository" is an expected outcome here, not a diagnostic, and
  `tests/hook-test.sh:66-68` asserts the hook's stderr stays empty. The header
  comment (`:3-5`) is restated for both cases. The initial-release branch keeps
  the existing no-bypass sentence and offers no escape hatch. One accepted bound
  goes in a comment beside the listing: a `CLAUDE_PROJECT_DIR` that is not
  itself a repo but sits inside one lists the enclosing repo's tags, which
  changes the wording and never the decision. `tests/hook-test.sh` gains
  `unset $(git rev-parse --local-env-vars)` at the top as `release-test.sh:8-13`
  does, and `run_guard` (`:50`) gains a project argument (defaulting to the
  existing non-repo `$proj`) plus a way for a scenario to add environment
  variables. The existing `$proj` scenarios exercise the listing-failure
  fallback and must pass unchanged.

  - Requirements: FR-2, FR-7.
  - Slices:

    1. External contract: a `git init` fixture with a manifest at `1.2.3` and no
       tags, Edit payload `1.2.3` -> `9.9.9` — `assert_deny` (exit 0, deny JSON
       on stdout, `systemMessage` present, stderr empty), and the
       `permissionDecisionReason` contains `never been released` and
       `will publish`, and does not contain `last released version` — today's
       opening sentence, and the one claim that is false on a plugin with no
       releases. Red: the steady-state message is the only one there is today.
    2. The message offers no route to the proposed version: same scenario,
       `$proposed` (`9.9.9`) appears nowhere in the reason after its first line,
       the opening `1.2.3 -> 9.9.9` being the one legitimate mention. Guard —
       green against a slice-1 branch that named no version, failing one that
       offers the recipe as the route to `$proposed`.
    3. Only the agent channel branches: the `systemMessage` string from the
       tagless fixture is byte-identical to the one from a fixture tagged
       `v1.2.3`, for the same payload. Guard, on a branch that spread to
       `systemMessage`.
    4. The predicate, not the tag count: the same fixture tagged only `vnext`
       (and `v1.2`) gives the initial-release wording, while tagged `v1.2.3` it
       gives the steady-state wording. Red against an implementation keyed on
       `git tag --list 'v*'` emptiness rather than the semver filter — slice 1's
       tagless fixture cannot tell the two apart; the `v1.2.3` half is a guard.
    5. The guard clears leaked `GIT_*`: tagless fixture invoked with `GIT_DIR`
       pointed at a second fixture carrying `v1.2.3` — initial-release wording.
       Red: without the clearing the listing discovers the tagged repo. Tests
       the guard's own clearing, as distinct from the harness hygiene above.
    6. A failed listing is not an empty one: `git` stubbed to exit 127 through
       `guard_path`, against the tagless repo fixture — still denies, with the
       steady-state wording and empty stderr. It is the tagless fixture that
       discriminates: an implementation folding failure into emptiness answers
       initial-release here.

## Phase 3: docs (type: inline)

Each item rewrites in place — an overturned decision is restated with the new
reasoning, never struck through. `just format-docs` runs before the cap check,
and `tests/docs-test.sh` enforces 400 lines over `docs/` and `plans/`. No
shipped file is added or removed anywhere in this plan, so the CLAUDE.md Layout
list, `tests/dist-tree-test.sh` and `tests/doc-sync-test.sh` need no change.

- Item 3.1: docs/references/release-flow.md — "the latest tag" becomes the
  newest semver tag (`:12-14`); detection rewritten tags-only (`:52-59`), which
  today argues *for* the two-part conjunct and is itself the overturned decision
  — the origin probe covers the lost-tags case directly and strictly better, the
  conjunct only ever having protected a lost-tags repo that had an entry; the
  scaffold paragraph (`:33-38`) restated as FR-1; the brief's three mechanisms
  recorded as rejected alternatives with their reasons (a guard that allows the
  edit, `--initial`, a baseline tag). The `0.0.0` seeding rejection (`:73-79`)
  stays. Also why both listings carry `--sort=-v:refname`: refname order is
  lexicographic, where `v1.10.0` precedes `v1.2.3`, so the newest-first contract
  every caller reads them under is not free. Requirements: FR-9, FR-1, FR-2,
  FR-4. Depends on: Item 1.2
- Item 3.2: docs/references/version-guard.md — the initial-release message
  branch, why it names no recipe as a route to the proposed version, why only
  the agent channel branches, and why the listing can never turn a deny into an
  allow. Requirements: FR-9, FR-7. Depends on: Item 2.1
- Item 3.3: docs/references/recovery.md — the no-tag refusal's four hints
  (`:51-54`); the lost-tags and diverged-push-route refusals joining the list at
  `:138-144`, with why the probe runs before the drift check; resume on a clone
  missing tags; `check-version.sh` on an initial release (`:19-32`) per FR-8.
  - Requirements: FR-9, FR-4, FR-5, FR-6, FR-8.
  - Depends on: Item 1.4
- Item 3.4: docs/design.md — rewrite the release-flow conclusion (`:105-107`)
  and add the message branch to the version-guard conclusion (`:146-150`).
  - Requirements: FR-9.
  - Depends on: Items 3.1, 3.2
- Item 3.5: toolkit/release.just and toolkit/README.md — the two consumer-facing
  statements of the predicate. The `release.just` header (`:23-29`) already
  states FR-1, FR-3 and the scaffold source; it gains one sentence naming the
  predicate and saying the marketplace entry plays no part, signatures
  unchanged. The README Conventions bullet (`:175-179`) states detection by
  semver tag, the initial version coming from `/plugin-dev:create-plugin`'s
  manifest, and a different version being the maintainer's committed edit.
  - Requirements: FR-9, FR-2.
- Item 3.6: docs/changelog/2026-MM-DD-first-release-is-the-manifest-version.md
  plus its index line in docs/changelog.md — dated the day it is written, newest
  first. The index line says outright that detection semantics change: a
  marketplace entry no longer disqualifies a first release. The changelog does
  not ship, so the pointer is the only place a consumer learns it. No migration
  note: the consumers beside this repo carry only `vX.Y.Z` tags, and the
  residual — a plugin released only under non-semver or non-`v` tags, with an
  entry — matches none of them. Requirements: FR-9. Depends on: Items 3.1-3.5

## Phase 4: release (type: inline)

- Item 4.1: toolkit/VERSION — `just precommit`, then `just release minor`. Minor
  because the toolkit is pre-1.0, where a minor bump is the conventional home
  for a behaviour change, and a marketplace entry no longer disqualifying a
  first release is one. Outward-facing and irreversible: run only on my human
  partner's explicit go-ahead, never as an autonomous dispatch. Requirements:
  FR-10. Depends on: Item 3.6

## Out of scope

Item B of the brief (the `sandbox.excludedCommands` README note); choosing an
initial version other than the manifest's through the recipe; refusing a
hand-seeded `0.0.0`; `install.sh`; code changes to `check-version.sh`; the root
`README.md` and `CLAUDE.md`; editing `plugin-craft:toolkit-release`, which gets
a note after the release lands. Partial tag loss — a clone holding `v1.0.0` over
origin's `v1.2.3` still reads as released — is pre-existing and unchanged.

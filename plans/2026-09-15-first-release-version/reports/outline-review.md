# Outline Review: 2026-09-15-first-release-version

- **Artifact**: `plans/2026-09-15-first-release-version/outline.md`
- **Date**: 2026-09-15
- **Mode**: review + fix-all

## Summary

The outline's direction matches the Rules and the per-file split is right, but
several load-bearing mechanics were stated loosely enough to ship a regression.
The worst of them: a naive tag listing in `version-guard.sh` turns the new
initial-release case into a silent allow. The lost-tags probe also had no
placement or failure semantics, the `grep -E` handling was unspecified, and
several proposed tests would not fail against unchanged code. All findings are
fixed in the outline. Two needed a decision from my human partner and went to a
new Open questions section, each with a default.

**Overall Assessment**: Ready. Open questions 1 and 2 carry defaults, so
implementation can start without them.

Grounding: git 2.47.3, jq 1.7, bash 5.2.37. Exit codes, ls-remote pattern
matching and `-v:refname` order were probed in a scratch repo, not assumed.

## Requirements Traceability

The Rules section (1-4) is the requirement set. It was not altered. `rumdl fmt`
re-wrapped two of its lines, which moved line breaks but no words.

| Requirement | Outline Section | Coverage | Notes |
|---|---|---|---|
| Rule 1: initial manifest version is the initial release | release.sh; docs release-flow.md | Complete | Unchanged code path (`bump_commit_tag` initial branch) |
| Rule 2: detection by semver `v` tag absence only | release.sh `release_tags`; version-guard.sh; tests | Complete | Added `grep` status handling, sort order, lost-tags probe |
| Rule 3: no argument on initial release, publishes manifest | release.sh bump refusal; `resume_preflight` hint | Partial, fixed | `resume_preflight` hint contradicted it (M3) |
| Rule 4: toolkit writes no version | Scope OUT (`install.sh`); hook wording | Complete | Hook message must not route the agent to `just release` (M5) |

**Traceability Assessment**: One gap against Rule 3 was found and fixed. Nothing
in the outline contradicts the Rules. The `check-version.sh` gate is outside
Rule 2's scope (detection only), so it went to Open question 1 rather than being
decided.

## Scope-to-Component Traceability

| Scope IN Item | Component | Notes |
|---|---|---|
| Item A: detection by semver tag | `toolkit/release.sh` | Direct |
| Item A: hook message branch | `toolkit/version-guard.sh` | Direct |
| Item A: header comment | `toolkit/release.just` | Direct |
| Item A: tests | `tests/release-test.sh`, `tests/hook-test.sh` | Direct |
| Item A: docs | Docs section | Direct; recovery.md was missing (m2) |

**Scope Assessment**: The Scope IN line was "item A as above". It now names the
components. There are no orphans.

## Review Findings

### Critical Issues

1. **The hook's tag listing can turn a deny into an allow**
   - Evidence: `toolkit/version-guard.sh:8` (`set -euo pipefail`), `:78-102`
     (the JSON is printed last). Probed: a grep substitution with no match exits
     1, an absent git exits 127, and a non-repo directory exits 128.
   - Problem: `grep` finds nothing on a project with no semver tag, which is the
     exact case the new branch serves. So a straightforward listing kills the
     hook before it prints the deny. Claude Code treats any non-zero exit other
     than 2 as a non-blocking error, so the edit goes through. The outline said
     only that the listing was duplicated.
   - Fix: the listing runs after the deny is established and tolerates every
     failure. It keeps stderr empty (`tests/hook-test.sh:66-68` asserts that)
     and falls back to a stated message (Open question 2). A new no-tag
     `git init` fixture is red on unchanged code, and `assert_deny` fails it on
     the bypass as well.
   - **Status**: FIXED

### Major Issues

1. **The lost-tags probe had no placement or failure semantics (M1)**
   - Evidence: `release.sh:297` (local tag), `:342` (branch push), `:355-361`
     (push_tag), `:176-177` (origin validated only without an entry). Probed:
     `ls-remote --exit-code` returns 0 found, 2 absent, 128 for no remote or an
     unreachable one. A bare `v0.1.0` pattern also matches
     `refs/tags/foo/v0.1.0`.
   - Problem: "Before tagging" left room to place the probe after
     `bump_commit_tag`. Under errexit a 128 would die with only git's fatal. The
     outline's backstop note also missed two things. `push_tag` fires only after
     the branch is pushed, and a re-created annotated tag never matches origin's
     sha. The stray local tag then flips detection on a re-run and blocks
     `git fetch --tags`.
   - Fix: the probe sits in `release_preflight`'s initial branch before
     `return`, on the exact ref, and branches on status: 0 refuses with a fetch
     hint, 2 proceeds, anything else refuses (fail closed). The rationale is
     recorded in the outline.
   - **Status**: FIXED

2. **`grep -E` under pipefail was "handled", with no mechanism given (M2)**
   - Evidence: `release.sh:2`, `:250`; probe above.
   - Problem: `tags=$(release_tags)` exits the script silently on no match, and
     an unconditional `|| true` would also hide grep error 2. The outline did
     not say the helper sorts, which `latest_tag` needs.
   - Fix: the helper sorts with `-v:refname`, then runs
     `{ grep -E … || [ $? -eq 1 ]; }`. The outline notes that
     `release-test.sh:592` catches a helper that gets this wrong.
   - **Status**: FIXED

3. **`resume_preflight`'s hint contradicts Rule 3 (M3)**
   - Evidence: `release.sh:284-287` hints `just release <bump>`; also
     `docs/references/recovery.md:51-54`, `tests/release-test.sh:367`.
   - Problem: on an initial release that command is refused.
   - Fix: when there is no semver tag, the hint names `just release` with no
     argument. A red scenario and the recovery.md edit were added.
   - **Status**: FIXED

4. **`check-version.sh` drift refusal loops on an initial release (M4)**
   - Evidence: `release.sh:202-206` hints `just resume-release`.
     `check-version.sh:53-57` refuses on drift. `release.sh:283-288` sends
     resume back to `just release`.
   - Problem: take an entry at X, a manifest at Y and no tags. Every hint then
     leads back to the same refusal. Rule 2 does not settle this gate.
   - Fix: added as Open question 1. Default: keep the refusal and make its hint
     initial-release aware. The alternative is to skip the check with no semver
     tag.
   - **Status**: FIXED (decision deferred with a default)

5. **The hook message pointed the agent at a public release (M5)**
   - Evidence: old outline lines 59-63 ("`just release`, with no argument,
     publishes it"); `docs/references/version-guard.md:11-20`; CLAUDE.md "Hook
     output is dual-channel".
   - Problem: take an agent asked to set a different version. It reads the
     recipe as the route and publishes the scaffold's version, which is
     irreversible.
   - Fix: the message names `$current` as what the initial release publishes and
     says setting it is the maintainer's edit. It must not offer `just release`
     as a route to `$proposed`.
   - **Status**: FIXED

6. **The inverted lost-tags test used the wrong invocation (M6)**
   - Evidence: `tests/release-test.sh:628` runs `patch`, and `make_virgin`
     deletes the origin tag too (`:202`).
   - Problem: with `patch` the inverted scenario hits the bump refusal and never
     shows the entry being ignored. "`v$V` on origin but not locally" cannot be
     built with `make_virgin`. In the no-entry variant, unchanged code already
     exits 1 in `push_tag`, so an exit-code assertion is not red.
   - Fix: the inverted scenario runs with no argument, and a separate `patch`
     variant was added. `make_virgin` gains a local-only drop. Each scenario now
     names the assertion that makes it red.
   - **Status**: FIXED

7. **A tag example that would not exercise `latest_tag` (M7)**
   - Evidence: probed `-v:refname` order: `vnext`, `v9.9`, `v1.2.3`, `v1.2`,
     `v0.1.0`.
   - Problem: `v1.2` sorts below `v1.2.3`, so a test built on it passes on
     unchanged code.
   - Fix: the sorted-above scenario uses `vnext`, and the outline says why
     `v1.2` does not work there.
   - **Status**: FIXED

8. **`hook-test.sh` is exposed to leaked git env (M8)**
   - Evidence: `justfile:132-139` runs `just precommit` from this repo's
     pre-commit hook. `tests/release-test.sh:8-13` unsets the leak for that
     reason; `tests/hook-test.sh` does not. `$proj` is not a repo
     (`hook-test.sh:28`) and `run_guard` pins it (`:50`).
   - Problem: under the hook, a fixture listing can read this repo's own `v0.x`
     tags. The no-tag test would then fail at commit time and pass by hand. The
     existing scenarios silently become fallback tests.
   - Fix: the outline adds the unset and a project argument to `run_guard`. It
     states that the existing scenarios cover the fallback.
   - **Status**: FIXED

9. **Missing test scenarios (M9)**
   - Problem: nothing covered an unreachable or absent origin, the resume hint,
     the commit instruction, a non-semver-only hook fixture, or the hook with
     git absent. "Both still deny" and the steady-state hook test are green on
     unchanged code but were not labelled as regression guards.
   - Fix: all were added, each red or explicitly labelled green.
   - **Status**: FIXED

### Minor Issues

1. **Rationale for duplicating the filter was inaccurate (m1)**
   - Evidence: `release.sh:493-508` runs at top level;
     `tests/dist-tree-test.sh`.
   - Problem: "runs from `plugin-dev/` by path" does not rule out sourcing a
     sibling file.
   - Fix: the real reasons are now given: `release.sh` cannot be sourced, and a
     shared file would be a new shipped path. Shared test tag sets guard against
     drift between the two copies.
   - **Status**: FIXED

2. **Doc nodes missed (m2)**
   - Evidence: `recovery.md:19-32, :51-54, :138-144`; `release-flow.md:12-14`
     ("latest tag"); `design.md:146-150`; `version-guard.sh:3-5`;
     `release-test.sh:194-200` (`make_virgin` comment).
   - Fix: all were added to the Docs and Tests sections.
   - **Status**: FIXED

3. **Unchanged docs not stated as checked (m3)**
   - Evidence: root `README.md` has no first-release text (grep).
     `doc-sync-test.sh:55-79` compares only install/update command blocks, and
     `:81-107` checks Layout paths. No shipped file is added.
   - Fix: an explicit "Unchanged, checked" bullet was added.
   - **Status**: FIXED

4. **Migration-note claim ungrounded (m4)**
   - Evidence: the mounted consumers `handoff` (33), `gitmoji` (8), `gitlore`
     (21), `cwd-safety` (8) and `shell-gotchas` (5) carry only `vX.Y.Z` tags. No
     non-semver `v` tags were found.
   - Fix: the claim now cites the check and names the residual case: a plugin
     with non-`v` tags and an entry would republish.
   - **Status**: FIXED

5. **Hook listing edge cases unstated (m5)**
   - Evidence: observed while probing. A non-repo directory nested in a repo
     lists the enclosing repo's tags. A `GIT_DIR` inherited from a hook
     overrides discovery.
   - Fix: the outline clears repo-local `GIT_*` for the listing and records the
     nesting case as an accepted, wording-only bound.
   - **Status**: FIXED

6. **Scope vague and no Open questions section (m6)**
   - Fix: Scope IN names the components. Scope OUT adds `check-version.sh` code,
     root `README.md` and CLAUDE.md. An Open questions section was added.
   - **Status**: FIXED

## Fixes Applied

- What changes: cited lines; added the lost-tags guard and the two wrong hints.
- `release.sh`: sorting helper with rc-1-only absorption; probe placement, exact
  ref, status branching, fail-closed rationale; `resume_preflight` hint;
  `check-version` hint ordering.
- `version-guard.sh`: message constraint against routing to `just release`;
  listing after the deny, failure-tolerant, git env cleared; nesting bound;
  corrected duplication rationale.
- New `check-version.sh` section (no change under default).
- Tests: every scenario states its red assertion; nine scenarios added or
  corrected; `hook-test.sh` env unset and `run_guard` project argument.
- Docs: `recovery.md`, `release-flow.md:12-14`, `design.md` version-guard line,
  README commit instruction, "Unchanged, checked" bullet, grounded migration
  note.
- Scope, Open questions 1-2, Dependencies (shared tag set).
- `rumdl fmt` reflow; 282 lines.

## Positive Observations

- It keeps the hook's decision unchanged and branches only the wording, which
  honours the brief's rejected "guard allows the edit" path.
- Filtering `latest_tag` through the same helper closes a real stray-tag bug.
- It already spotted that dropping the conjunct reopens the lost-tags case.
- It avoids a new shipped file, so `dist-tree-test` and doc-sync stay untouched.

## Recommendations

- Answer Open question 1 before the red phase, because it decides one scenario
  and one recovery.md paragraph.
- Dogfood on a scratch plugin scaffolded by `/plugin-dev:create-plugin` the day
  the toolkit ships, including one run with tags deleted locally.

## Process note

The first probe ran with `$TMPDIR` empty in this sandbox. Its scratch repo
landed at the repo root as `lrt/`, with its own local bare origin. It was
removed, and `git status` and `git tag` were verified unchanged. Nothing else
outside the outline and this report was written.

---

**Ready for user presentation**: Yes. Two open questions carry defaults.

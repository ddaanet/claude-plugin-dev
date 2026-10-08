# claude-plugin-dev Changelog

How the design got to its current shape. Each entry is a write-time record of
one change: what moved, and the reasoning available at the time. Entries are
never revised — a dated record is correct forever precisely because it is dated.
`just format-docs` re-wraps them at 80 columns, which changes line breaks and
not words. The living design is [design.md](design.md); when a decision there is
overturned, it is rewritten in place and the reversal gets an entry here.

Newest first.

- [2026-10-08 — Four dogfood claims left unprobed are probed, and one was wrong](changelog/2026-10-08-probed-dogfood-claims.md)
  — hooks registered by a plugin and by settings both fire, so a script that
  wires them runs them twice; an empty `.mcp.json` is accepted silently and
  fails only `plugin validate`; `/reload-plugins` makes commands, `.mcp.json`
  and output styles live; jq 1.6 exits 4 on a parse error by its source, not 2,
  and the guard's exit 1 holds either way
- [2026-10-08 — The no-copy session warning names `just dogfood`, and the sync honours submodule ignores](changelog/2026-10-08-dogfood-no-copy-remedy-and-submodule-ignores.md)
  — with no copy, `session-start` named a launch through the shim, which is how
  the session started; it now names `just dogfood` and a relaunch, and tells the
  agent only that no copy exists. The sync's ignore list is now built per repo,
  recursing into initialised submodules, so a path a submodule ignores no longer
  reaches the copy
- [2026-10-05 — The dogfood shim stops syncing: `just dogfood` is the only promotion](changelog/2026-10-05-the-shim-stops-syncing.md)
  — a launch, a relaunch or any `claude` through the shim no longer promotes the
  working tree, a launch with no copy warns with a line naming `just dogfood`
  and starts `claude` without it, and the sync refuses without `rsync` before it
  makes the copy. Also corrects the 2026-10-03 record: its premise that an
  agent's nested `claude -p` re-promoted the tree (the shim's exported PATH
  strip already kept it off the shim), its overstated m2 probe, and its "names"
  for what was a whole-value match
- [2026-10-03 — The dogfood launcher reviewed: a `claude` inside a dogfood session does not promote](changelog/2026-10-03-dogfood-review-fixes.md)
  — the shim synced on every `claude` it fronted, so a scripted `claude -p` an
  agent ran inside a dogfood session re-promoted the tree under it; it now skips
  the sync when `CLAUDE_CODE_PLUGIN_DIRS` already names its own copy, with no
  argv rule and no opt-out. Also records the rest of the review's fixes: a
  failed launch sync says `claude` was not started, `pre-tool` never exits 2 on
  a `jq` failure, four test gaps pinned, and the doc fixes m2 and m4–m9
- [2026-09-30 — The dogfood launcher: consumers load their plugin from a synced copy](changelog/2026-09-30-dogfood-launcher.md)
  — a session loading a plugin from its working tree prompts on every agent edit
  and runs half-edited hook scripts; the toolkit ships a `claude` shim that
  loads a copy at `dist/plugin/`, promoted only at launch and by `just dogfood`,
  with a copy guard and a `SessionStart` check wired by `install.sh`. Records
  why sync-on-edit was designed first and rejected in review, the three probe
  sets, and where the shipped code departs from the outline
- [2026-09-20 — The first-release pass reviewed, and what the diff does not say](changelog/2026-09-20-deliverable-review-fixes.md)
  — `/deliverable-review` of the first-release-version pass returned 6 Major, 15
  Minor and one baseline defect, executed over four phases. Three things the
  diff does not carry: citing a script by line number is now refused by
  `tests/citation-test.sh` rather than by a `CLAUDE.md` bullet that would rot
  the day upstream ships the same rule, with its `.md` residual bound stated;
  the comment volume of the shipped scripts is accepted, with the measured
  figures here and only a proportion in the hub; and the baseline defect, a
  three-versus-four hint count in a frozen outline, was seen and deliberately
  left standing
- [2026-09-17 — One script under test per suite file](changelog/2026-09-17-one-script-under-test-per-suite.md)
  — `tests/hook-test.sh` covered two unrelated scripts under a name that fit
  one; split into `version-guard-test.sh` and `check-version-test.sh`, each
  carrying its own assertion harness rather than sourcing a shared one. The
  version-guard half stays over the line guideline, and the argument for leaving
  it there is recorded rather than the number fixed
- [2026-09-17 — `recovery.md` splits off this repo's own release](changelog/2026-09-17-recovery-splits-off-the-self-release.md)
  — the node was at 389 of 400 lines with two audiences in it; consumer recovery
  stays and the self-release moves to `docs/references/self-release.md`, with
  the clean-tree exclusions placed rather than assigned. The split surfaced a
  paragraph still arguing the self-release has no `resume-release`, thirty lines
  above the section describing the one it grew that morning
- [2026-09-17 — Probes that fail closed on their own, and a pointer a consumer cannot follow](changelog/2026-09-17-probes-that-fail-closed-on-their-own.md)
  — `release.sh`'s three `ls-remote | cut` captures become one `ls_remote_sha`
  helper, so a failed probe can no longer be read as "the ref is not on origin"
  if `set -o pipefail` ever lapses, pinned by a test that runs a
  pipefail-stripped copy; and a shipped comment drops a citation of a `plans/`
  document a consumer has no way to open
- [2026-09-17 — The self-release gets the recovery it had been shipping to consumers](changelog/2026-09-17-self-release-gets-a-resume.md)
  — the root `justfile`'s unguarded release tail moves to
  `scripts/self-release.sh` with an idempotent tail and a `resume-release`
  counterpart, plus one guard consumers do not need: a bump is refused while the
  version in `toolkit/VERSION` is tagged but not fully published, the state a
  failed push leaves and the only one the previous guard set read as healthy
- [2026-09-17 — Refusals that end in an act, and a bound the wording implied away](changelog/2026-09-17-refusals-that-end-in-an-act.md)
  — an unreadable `marketplace.json` no longer reads as an absent entry, which
  on `--resume` had let a run reach `create_github_release` before dying; the
  version-drift refusal drops two remedies that were dead on every path reaching
  it, keeping the one that works; and `url.<base>.pushInsteadOf` is recorded as
  a stated bound of the diverged-push-route check rather than left
  implied-covered
- [2026-09-17 — The first release is the manifest version, detected by tag alone](changelog/2026-09-17-first-release-is-the-manifest-version.md)
  — **detection semantics change: a marketplace entry no longer disqualifies a
  first release.** A plugin is at its first release exactly when no `vX.Y.Z` tag
  exists locally or on origin; the lost-tags case the old conjunct proxied for
  is now probed on origin directly, before the drift check and any side effect.
  The version-guard hook's agent message branches on the same predicate and
  names no route to the proposed version, and `common_preflight` refuses a push
  route redirected away from origin
- [2026-09-07 — The README absorbs the post-pull check, and memory shrinks](changelog/2026-09-07-readme-absorbs-the-post-pull-check.md)
  — `toolkit/README.md`'s update section gains `just --list` as a verification
  step and the separate-commit rule; the ddaanet memory entry drops from 4025
  bytes to what the shipped manual cannot own, the routing line and the
  changelog that is not in the dist tree
- [2026-09-07 — Two CLAUDE.md rules became static checks](changelog/2026-09-07-doc-sync-static-checks.md)
  — `tests/doc-sync-test.sh` compares the command blocks the two READMEs share
  and CLAUDE.md's `toolkit/` paths against the shipped tree; it found the
  `just update-plugin-dev` block already diverged
- [2026-09-07 — A refused marketplace commit rolls the bump back too](changelog/2026-09-07-marketplace-refusal-rolls-back.md)
  — the leftover staged bump blocked `resume-release` on `common_preflight`, the
  one command that finishes a release already public through its GitHub release;
  the printed two-command recovery is now `just resume-release` alone
- [2026-09-05 — The bootstrap stops cloning the repo to get one file](changelog/2026-09-05-the-bootstrap-stops-cloning-the-repo.md)
- [2026-09-03 — Release refusals carry the diagnosis and the next command](changelog/2026-09-03-release-messages-carry-the-diagnosis.md)
  — the lore about `uncommitted changes`, what is already public at the
  marketplace step, and the `/add-dir` denial moved out of a ddaanet memory file
  into the messages `release.sh` prints at each failure; paths are read
  NUL-delimited and the exemptions named are the ones that copy applies
- [2026-09-02 — The design doc became a hub, and docs got a gate](changelog/2026-09-02-design-hub-and-docs-gate.md)
  — `design.md` was 837 lines; its arguments moved into four `docs/references/`
  nodes and it kept one-line conclusions. `just format-docs` wraps `docs/` and
  `plans/` at 80 columns and `tests/docs-test.sh` caps them at 400 lines and
  resolves pointers
- [2026-09-01 — The clean-tree check exempts `.claude/`](changelog/2026-09-01-clean-tree-excludes-dot-claude.md)
  — a staged handoff frame refused every release on `uncommitted changes`;
  `.claude` is now excluded alongside the memory gitlink, in `release.sh` and in
  this repo's own release recipe
- [2026-09-01 — version-guard: output channel, manifest location, edit shape](changelog/2026-09-01-version-guard-channel-and-path.md)
  — the deny JSON moves to stdout with exit 0; `CLAUDE_PROJECT_DIR` replaces the
  drifting payload `cwd`; `realpath -m` dropped (it inverted the guard on
  macOS); an Edit of the bare version value no longer passes
- [2026-09-01 — Fixes from a whole-toolkit shell-gotchas audit](changelog/2026-09-01-shell-gotchas-audit-fixes.md)
  — `install.sh` could replace a consumer's whole `settings.json`; `mktemp`+`mv`
  narrowed file modes; the drift check read any tag as the last release;
  `quote()` for recipe arguments; `unset CDPATH` in three suites
- [2026-09-01 — `update.sh` owns the update flow](changelog/2026-09-01-update-sh-ref-resolution-migration-notes.md)
  — ref defaults to the newest dist tag at both call sites; migration notes ship
  in the dist tree and are printed after the pull, never applied
- [2026-08-28 — The memory submodule's path is read, not assumed](changelog/2026-08-28-memory-path-read-from-gitmodules.md)
  — `common_preflight` excluded the literal path `memory`, which is only
  gitlore's default mount point; now read from `.gitmodules` by submodule name
- [2026-08-28 — A refused push resumes; the release commit is never amended](changelog/2026-08-28-refused-push-resumes-never-amends.md)
  — why no `refresh_release_commit` amend step exists, and the hint
  `push_branch` now prints instead
- [2026-08-28 — The marketplace writability probe keeps mktemp's own words](changelog/2026-08-28-writability-probe-keeps-mktemps-words.md)
  — the probe discarded `mktemp`'s stderr and then asserted a sandbox cause it
  never established; also comments why the release-only check must not be
  `common_preflight`'s last line
- [2026-08-28 — A refused release commit rolls the manifest back](changelog/2026-08-28-refused-commit-rolls-back.md)
  — a consumer's `pre-commit` hook refusing the release commit left the bump
  staged and uncommitted, which then blocked both a re-run and `resume-release`
  on `uncommitted changes`
- [2026-08-14 — Consumers vendor a split `dist-` ref](changelog/2026-08-14-dist-ref-stops-squash-leak.md)
  — `subtree` copies a ref's whole root tree, so consumers were receiving this
  repo's working environment; shipped files moved under `toolkit/` and releases
  cut a `dist-vX.Y.Z` split tag
- [2026-08-13 — `install.sh` subtree add recursion scoping](changelog/2026-08-13-install-subtree-add-recursion.md)
  — v0.5.2 fixed one of two subtree call sites; `install.sh`'s add hit the same
  collision, and the test covering the fix could pass vacuously on same-second
  seed commits
- [2026-08-11 — First release publishes the manifest version](changelog/2026-08-11-first-release-manifest-verbatim.md)
  — a never-released plugin has no version to bump from, so `just release` ships
  the version `plugin.json` already holds (v0.5.3)
- [2026-08-11 — `update-plugin-dev` submodule collision](changelog/2026-08-11-subtree-submodule-collision.md)
  — a consumer's own `memory` submodule at the same path broke
  `git subtree pull`'s on-demand submodule fetch (v0.5.2)
- [2026-07-29 — `resume-release`](changelog/2026-07-29-resume-release.md) — the
  release tail became an idempotent block both `release` and a recovery path run
  (v0.5.0)
- [2026-07-27 — `check-version.sh`](changelog/2026-07-27-check-version.md) —
  detects a release that tagged and pushed but never bumped the marketplace
  (v0.4.1, v0.4.2)
- [2026-07-23 — `prerelease` gate](changelog/2026-07-23-prerelease-gate.md) —
  `release` binds to a consumer-defined gate; breaking, every consumer adds a
  recipe (v0.4.0)
- [2026-07-01 — Non-interactive release](changelog/2026-07-01-non-interactive-release.md)
  — dropped the confirmation prompt and `--yes`; the outer permission gate
  already asks (v0.3.0)
- [2026-06-11 — Marketplace entry creation](changelog/2026-06-11-marketplace-entry-creation.md)
  — first publication creates the entry instead of aborting; the bump commit
  became idempotent (v0.2.1)
- [2026-04-29 — `VERSION` file and marketplace bump](changelog/2026-04-29-version-file-and-marketplace-bump.md)
  — the toolkit can identify itself inside a subtree, and `release` treats tag +
  marketplace as one release (v0.2.0)
- [2026-04-27 — Initial extraction](changelog/2026-04-27-initial-extraction.md)
  — toolkit broken out of handoff and gitmoji, the two release recipes unified
  (v0.1.0)

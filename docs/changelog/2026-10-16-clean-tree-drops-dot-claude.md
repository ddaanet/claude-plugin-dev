# 2026-10-16 — The clean-tree check stops exempting `.claude/`

This supersedes
[2026-09-01 — The clean-tree check exempts `.claude/`](2026-09-01-clean-tree-excludes-dot-claude.md),
which stays as it was written. The check now exempts only the gitlore memory
gitlink. A tracked file under `.claude/` that differs from HEAD refuses a
release, in the plugin repo and in `MARKETPLACE_DIR` alike, and in this repo's
own self-release.

## Why it could go

The 2026-09-01 exemption existed because the `handoff` and `precompact` skills
staged `.claude/handoff-task.md` and `.claude/handoff-todo.md` for whatever
commit lands next, and a release died on them with `error: uncommitted changes`.
`handoff` has moved both frames to tracked root files, `TASK.md` and `TODO.md`,
no longer gitignored and no longer force-staged by a hook, and every repo
carrying the toolkit has migrated. With the frames gone, the exemption's
remaining effect is that an edit to a tracked file under `.claude/` rides the
release commit unnamed.

The earlier entry's argument for excluding the directory whole — the set of
files written there is a function of which skills the maintainer runs — is not
answered by `handoff` leaving. It is overridden by my human partner's decision.

## What it costs

- An uncommitted edit to a tracked `.claude/settings.json` (the version-guard
  wiring) stops a release again. The 2026-09-01 entry named losing that as the
  cost it accepted.
- So does an uncommitted edit to `.claude/gitlore-hook-setup`, gitlore's tracked
  install state, and to any other tracked file a skill moves under `.claude/`
  between commits. Untracked and gitignored files (`settings.local.json`,
  `gitlore-memory-message`) never appeared in `git diff HEAD` and are
  unaffected.
- A dirty `TASK.md` or `TODO.md` refuses too. No replacement exemption: they are
  ordinary tracked files and the routine flow is handoff, commit, release.

## What changed

- `clean_pathspecs` in `toolkit/release-preflight.sh` loses
  `':(exclude).claude'` and its `clean_exempt` line, and the comment block loses
  the paragraph arguing for them. A repo with no memory submodule has no
  exclusion at all.
- `report_dirty` prints the "exempt from this check" list only when an exemption
  applies. The closing note that `.claude-plugin/` is NOT exempt is removed: it
  disambiguated that directory from the `.claude` pathspec, and with none there
  is nothing to disambiguate.
- `common_preflight` in `scripts/self-release.sh` excludes `memory` alone.
- The scenarios 2026-09-01 added (a staged frame in the plugin repo, one in the
  marketplace repo, the `.claude-plugin` decoy) are inverted or removed: a dirty
  tracked file under `.claude/` now refuses, and the consumer refusal names it.
- `install.sh` and `update.sh` already ran a bare `git diff --quiet HEAD` with
  no exclusions, so they already refused a dirty `.claude/`; nothing changed
  there.
- `docs/design.md`, `docs/references/recovery.md`,
  `docs/references/self-release.md` and `toolkit/README.md` are rewritten in
  place.

A consumer picks this up through `just update-plugin-dev dist-vX.Y.Z`. One whose
vendored copy predates it, and whose `handoff` still writes under `.claude/`,
keeps the old behaviour until it updates.

# Preflight — claude-plugin-dev toolkit v0.9.0

Run 2026-10-04 via `ddaa:preflight`, read-only, against the state that
`just resume-release` will publish. `just release minor` already created the
release commit and both tags locally; nothing is pushed yet.

**Verdict: GO with notes.** No blocker. The notes are informational or pending
follow-ups that need not hold the release.

## Preflight Report

| Check | Status |
| --- | --- |
| Branch | pass: `main` |
| Clean tree | pass: only ` M memory` (gitlore resting state, merge in progress) and the sandbox-mask dotfiles |
| Remote sync | warn (expected): 88 commits ahead of `origin/main`, 0 behind, fast-forward |
| Quality checks | pass: all non-mutating parts of `just precommit` re-run on HEAD |
| Pending tasks | warn: 1 follow-up review not run, plus a stale task frame |
| Documentation | pass: nothing to update |

**Current version:** `toolkit/VERSION` = 0.9.0 (previous release 0.8.0)
**Commits in the release (`v0.8.0..v0.9.0`):** 88 **Release command:**
`just resume-release` (pushes `main`, `v0.9.0`, `dist-v0.9.0`, then creates the
GitHub release)

## Release artifacts

- HEAD = `0ca385f` = `v0.9.0^{commit}`. `v0.9.0` is an annotated tag ("Release
  0.9.0"). The release commit only changes `toolkit/VERSION` (0.8.0 to 0.9.0).
- `dist-v0.9.0` is an annotated tag ("Dist 0.9.0") on `b7bb058`. A fresh
  `git subtree split --prefix=toolkit v0.9.0` gives the same `b7bb058`. Its tree
  `8be9f8f` is identical to `v0.9.0:toolkit`.
- `dist-v0.8.0` is an ancestor of `dist-v0.9.0`, so the dist lineage is
  continuous and `update.sh` accepts it.
- Dist tree contents:
  `LICENSE README.md VERSION bin/claude check-version.sh dogfood.sh install.sh migrations/v0.9.0.md release.just release.sh update.sh version-guard.sh`.
  `VERSION` reads 0.9.0. `bin/claude` and `dogfood.sh` are 100755, as the shim
  and the hook commands need.
- On origin: `main` = `389e8b0`, which is an ancestor of HEAD, so the push is a
  fast-forward. Neither `v0.9.0` nor `dist-v0.9.0` is on origin and there is no
  GitHub release for `v0.9.0`, so `push_tag` cannot hit the "refusing to move a
  published tag" case. `v0.8.0` and `dist-v0.8.0` on origin match the local
  tags, and the v0.8.0 GitHub release exists.
- `gh` is logged in as `ddaanet` with `repo` scope.

## Quality checks

The gate was not re-run as `just precommit`, because its `whitespace` step can
`git add` and `format-docs` rewrites files, and this run was read-only. Instead
every other part was run in the foreground on HEAD. All passed:

- shellcheck on the 8 scripts
- `bash -n` on every `tests/*.sh`
- `just _import-check`
- all 15 suites: version-guard, check-version, release, self-release,
  update-plugin-dev, install, dist-tree, docs, doc-sync, citation, dogfood-sync,
  dogfood-sync-refusal, dogfood-pre-tool, dogfood-session-start,
  dogfood-launcher

The two mutating steps were checked without writing:

- `git stripspace` over the same file set: no differences.
- `rumdl fmt --check docs plans` exits 0. It lists 83 issues it cannot fix,
  which `fmt` also leaves in place and which do not fail the gate.

After the run the tree was unchanged (` M memory` only). Already verified before
this run: the `just precommit` inside `just release`, and the macOS
`dogfood.sh sync` suites.

## Documentation audit

- `toolkit/migrations/v0.9.0.md` exists in the dist tree, and the file in the
  tree matches the one at `v0.9.0`. Its claims match the code:
  - `install.sh` wires `dogfood.sh pre-tool` and `session-start`, and
    `update-plugin-dev` does not re-run it.
  - The sync refuses while `dist/plugin/` is not git-ignored
    (`require_ignored_copy`).
  - The shim's abort message is exactly
    `dogfood: sync failed, so claude was not started`.
  - `rsync` is listed as a requirement.
- `toolkit/README.md` has a Dogfooding section (Setup, Launching, Promoting
  changes, Hooks) that points at the migration note. Requirements list `rsync`.
- Root `README.md` points at that Dogfooding section and at `just dogfood`.
  `doc-sync-test.sh` passes, which covers the shared install/update blocks and
  the CLAUDE.md Layout list.
- Neither README has a stale pinned version (no `dist-v0.8.0` or similar install
  pins).
- Every `docs/changelog/*.md` record has an entry in `docs/changelog.md`. The
  two records for this release (2026-09-30 dogfood launcher, 2026-10-03 review
  fixes) are at the top.
- `docs/design.md` and the new `docs/references/dogfood.md` are in the diff.
  `docs-test.sh` passes, covering the line cap and pointer resolution.

## Release scope (`v0.8.0..v0.9.0`, 88 commits)

- **Dogfood launcher (new, ships to consumers):**
  - `toolkit/dogfood.sh` with `sync`, `pre-tool` and `session-start`.
  - The `toolkit/bin/claude` shim.
  - A `just dogfood` recipe in `release.just`.
  - `install.sh` wires the two dogfood hooks.
  - The v0.9.0 migration note.
- **Dogfood review fixes:**
  - The shim skips the sync inside a dogfood session of its own repo.
  - A failed launch sync says `claude` was not started.
  - `pre-tool` never exits 2 when `jq` fails.
  - Test gaps for the payload `cwd`, `CLAUDE_PROJECT_DIR` and session-start
    symlink cases are now pinned.
- **Self-release:**
  - New `scripts/self-release.sh` with `--resume`.
  - It refuses to bump past an unfinished release.
  - Its probes fail closed.
- **Consumer release flow:** `toolkit/release.sh`, `version-guard.sh` and
  `release.just` adjustments.
- **Tests:**
  - The one-script-per-suite split: `hook-test.sh` became
    `version-guard-test.sh`, and the dogfood suite was split by subcommand.
  - New `citation-test.sh`, `install-test.sh` and `self-release-test.sh`.
- **Docs:**
  - Design hub plus the new `dogfood` and `self-release` nodes.
  - Six changelog records.
  - `toolkit/README.md` rewritten (80-column reflow and the Dogfooding section).

## Notes (none blocking)

1. **Follow-up review not run.** `build-summary.md` ("Left open") lists
   `/deliverable-review plans/2026-10-03-dogfood-review-fixes` (opus, fresh
   session) as a follow-up. No such report is in this job's `reports/`. It can
   run after the release, and a finding would then go into a patch release.
2. **Stale task frame.** `.claude/handoff-task.md` and `.claude/handoff-todo.md`
   (last touched in `91016e4`) still describe the state before the review: a
   deliverable review "next" and the macOS sync run "remaining". Both have since
   been done. These files are not shipped, and `common_preflight` excludes
   `.claude`. Suggested fix after the release: refresh or clear the frame (for
   example with `/handoff:handoff`).
3. **Release commit subject.** The subject is `🔖 0.9.0`, not the
   `release: 0.9.0` that CLAUDE.md and `self-release.sh` name. The gitmoji
   commit-msg hook rewrote it, the same way as `🔖 0.8.0` and `🔖 0.7.0`.
   Nothing probes the subject, so `resume-release` is unaffected. Optional fix:
   make CLAUDE.md "Releasing the toolkit" say the hook rewrites it.
4. **Memory gitlink.** `v0.9.0` pins `memory` at `e931f5e`, which is already
   contained in memory's `origin/live` (going by the local tracking ref), so
   clones of the source tag will resolve it. The memory checkout is now at
   `01a5e88` ("Update MEMORY.md for ddaanet tier merge"), a descendant of that
   commit, because the merge is in progress. If that merge adds a gitlink commit
   on `main` after `0ca385f`, `resume-release` pushes it with the branch and the
   tags stay on the release commit, as the script intends. The dist tree has no
   `memory` gitlink, so consumers are unaffected.
5. **Near-cap node.** `docs/references/dogfood.md` is 399 of 400 lines, so its
   next addition needs a split. Not a release issue.
6. **Unprobed questions.** The open questions recorded in the node, the manual
   and the changelog are unchanged: hook double-firing in the gitlore evals, an
   empty `.mcp.json`, the `/reload-plugins` scope, and the jq 1.6 parse-error
   status. They are documented as unprobed, not claimed.

## Next step

Once the memory merge is resolved and the gitlore pre-push will accept the push,
run `just resume-release`. It runs no gate. Then dogfood the same day: in one
consumer, run `just update-plugin-dev dist-v0.9.0` and follow
`plugin-dev/migrations/v0.9.0.md`.

## Open decisions

- The migration note is `toolkit/migrations/v0.9.0.md`; `v0.9.0` also appears in `toolkit/README.md`, `docs/references/dogfood.md` and the changelog entry. A bump other than minor means renaming all four, since `update.sh` prints notes in (old, new] only.
- Whether `dogfood.sh sync` gets an explicit `[[ -L ]]` refusal on `dist` / `dist/plugin`. Today `require_ignored_copy`'s git-error branch is the only guard against `dist/plugin -> ..` deleting the root's `.git` via `--delete-excluded`; now pinned by `a symlinked dist/plugin is refused and the root survives`. Default: leave it.

## Remaining

- `/edify:build plans/2026-09-26-dist-copy-dogfood-launcher` is complete (Finish done, no release cut). Run summary: `/tmp/claude/dogfood-build/orchestrator-3-report.md`; Finish's reviews under the job's `reports/`.
- `/deliverable-review plans/2026-09-26-dist-copy-dogfood-launcher` on opus, in a fresh session. The strengthened `the shim exports the copy` scenario has had no separate test review.
- Before cutting the release, run the `sync` suites (`tests/dogfood-sync-test.sh`, `tests/dogfood-sync-refusal-test.sh`) on a macOS consumer: openrsync or rsync 2.6.9 may reject `--from0 --exclude-from=-` (outline Risks).

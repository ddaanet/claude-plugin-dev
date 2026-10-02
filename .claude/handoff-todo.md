## Remaining

- `/edify:build plans/2026-09-26-dist-copy-dogfood-launcher` is complete (Finish done, no release cut). Run summary: `/tmp/claude/dogfood-build/orchestrator-3-report.md`; Finish's reviews under the job's `reports/`. Decided: release as a minor bump, v0.9.0 (matches `toolkit/migrations/v0.9.0.md`); no explicit symlink refusal in `dogfood.sh sync` while `require_ignored_copy`'s git-error branch holds; the 80-column README reflow stays.
- `/deliverable-review plans/2026-09-26-dist-copy-dogfood-launcher` on opus, in a fresh session. The strengthened `the shim exports the copy` scenario has had no separate test review.
- Before cutting the release, run the `sync` suites (`tests/dogfood-sync-test.sh`, `tests/dogfood-sync-refusal-test.sh`) on a macOS consumer: openrsync or rsync 2.6.9 may reject `--from0 --exclude-from=-` (outline Risks).

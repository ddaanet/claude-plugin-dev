## Open decisions

- The migration note is planned as `toolkit/migrations/v0.9.0.md` (minor bump from 0.8.0, runbook Item 3.2). Rename it if the release picks another bump, since `update.sh` prints notes in (old, new] only.

## Remaining

- `/edify:build plans/2026-09-26-dist-copy-dogfood-launcher` runs in delegated orchestrators (unnamed opus, general-purpose; unnamed executors; new orchestrator at ~200k context). Each writes `/tmp/claude/dogfood-build/orchestrator-N-report.md` with the exact next step and the carried run-summary items — resume from the highest-numbered one; it names the next step.
- Before cutting the release, run the `sync` suites on a macOS consumer: openrsync or rsync 2.6.9 may reject `--from0 --exclude-from=-` (outline Risks).

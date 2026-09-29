## Open decisions

- The migration note is planned as `toolkit/migrations/v0.9.0.md` (minor bump from 0.8.0, runbook Item 3.2). The proof that would have confirmed the bump was skipped; rename the note if the release picks another bump, since `update.sh` prints notes in (old, new] only.

## Remaining

- Run `/edify:build plans/2026-09-26-dist-copy-dogfood-launcher`, starting at Item 1.1.
- At the end of Phase 1, measure `tests/dogfood-test.sh`; over 400 lines, decide whether to split it before Phase 2 (runbook Phase 1 preamble).
- Before cutting the release, run the `sync` suite on a macOS consumer: openrsync or rsync 2.6.9 may reject `--from0 --exclude-from=-` (outline Risks).

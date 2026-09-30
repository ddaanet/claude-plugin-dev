## Open decisions

- `tests/dogfood-test.sh` is 880 lines, against the 400 soft cap. The runbook's Phase 1 preamble sends the split to the planner at the end of Phase 1, before Phase 2, since it changes Item 3.6's suite list. The obvious seam is `sync` versus the two hook subcommands, as two suites. Ask my human partner at the phase boundary.
- The migration note is planned as `toolkit/migrations/v0.9.0.md` (minor bump from 0.8.0, runbook Item 3.2). Rename it if the release picks another bump, since `update.sh` prints notes in (old, new] only.

## Remaining

- Slice 1.2/6 (leaf symlink via `readlink -f`) through RED, test review, GREEN and code review. Then add it to `runbook.md`'s Item 1.2 slice list, line-neutral.
- Phase 1 boundary per `references/phase-boundary.md`, then Phases 2–3 and Finish.
- Put in the run summary: `require_ignored_copy`'s git-error branch (`check-ignore` exit 128) has no test, flagged by the 1.1/6 code review and left unpinned. Also: the literal-compare rule for an unresolved `CLAUDE_CODE_PLUGIN_DIRS` entry is unpinned, and the orchestrator judged it unneeded, since a missing copy warrants the warning anyway. Also: a pre-commit `self-release-test.sh` failure that passed standalone and on retry, recorded in memory `precommit-intermittent-suite-failure`. List revisions: 1.2/4, 1.2/5 and 1.3/2 are revised in `runbook.md`; 1.3/1, 1.3/3 and 1.3/4 have none.
- Before cutting the release, run the `sync` suite on a macOS consumer: openrsync or rsync 2.6.9 may reject `--from0 --exclude-from=-` (outline Risks).

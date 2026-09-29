## Open decisions

- `tests/dogfood-test.sh` is already 532 lines, against the 400 soft cap, and Items 1.2/4–5 and 1.3 will add more. The runbook's Phase 1 preamble sends the split to the planner at the end of Phase 1, before Phase 2, since it changes Item 3.6's suite list. The obvious seam is `sync` versus the two hook subcommands, as two suites. Ask my human partner at the phase boundary.
- The migration note is planned as `toolkit/migrations/v0.9.0.md` (minor bump from 0.8.0, runbook Item 3.2). Rename it if the release picks another bump, since `update.sh` prints notes in (old, new] only.

## Remaining

- Continue `/edify:build` from Item 1.2/4 RED through Phases 1–3 and Finish.
- Put in the run summary that `require_ignored_copy`'s git-error branch (`check-ignore` exit 128) has no test. The 1.1/6 code review flagged it, and it was left unpinned.
- Before cutting the release, run the `sync` suite on a macOS consumer: openrsync or rsync 2.6.9 may reject `--from0 --exclude-from=-` (outline Risks).

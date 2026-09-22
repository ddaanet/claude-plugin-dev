## Open decisions

- Whether the fix pass warrants a toolkit release: it changed shipped files
  (`toolkit/release.sh` and `toolkit/version-guard.sh` in comments and deny
  wording only, `toolkit/README.md` in prose). No behaviour changed, so the
  case for a release is the manual's new text reaching consumers.

## Remaining

- Open findings from the run that nobody acted on: `reports/item-3-5.md`'s
  heading calls the fifth citation "stale" against its own opening line (frozen
  record, the changelog carries the right number); Item 3.4's `grep -q --`
  conversion is safe by construction, not by measurement; three Phase 1
  test-only slices have no GREEN report.
- `/gitlore:index-audit` on the root `memory/MEMORY.md`: the gitlore hook
  reports it at 89% of the 25600-byte budget after the 2026-09-22 pass, so it
  loads again, but the audit was queued as a curation pass and is still owed.
- An intermittent suite failure that appears only inside a combined `just
  precommit` and passes standalone immediately after. First seen 2026-09-17 in
  `tests/release-test.sh`, at `release: still refuses a genuinely dirty
  non-memory path in the marketplace repo`; on 2026-09-20 three more sightings
  in that suite at different scenarios, and one in
  `tests/version-guard-test.sh`, where a steady-state scenario got the
  initial-release wording — it saw no tags where its fixture provides them. Two
  suites and a combined-run-only signature point at cross-suite interference (a
  shared scratch path, a leaked git environment, a `PATH` stub outliving its
  scenario) and not at any one assertion. Uninvestigated; about one run in ten.

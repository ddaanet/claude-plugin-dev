## Open decisions

- Whether `toolkit/release.sh` gets split. Phase 1 takes it from 508 to roughly 570 lines, past the 400-line guideline, and no gate measures source files — only `docs/` and `plans/`. The runbook's corrector judged a mid-plan split scope creep and left it. Decide after Phase 1 lands, on the file as it actually reads.
- Phase 4 publishes the toolkit and needs my human partner's explicit go-ahead; it is marked in the runbook as never an autonomous dispatch.
- Item B of the brief — a `toolkit/README.md` note on `sandbox.excludedCommands` for the marketplace push — is out of the runbook's scope. The claim comes from another agent and was checked against CC 2.1.263; verify against current Claude Code before writing it.
- Whether edify's `skills/runbook/references/runbook-format.md` should prescribe item fields (`Requirements:`, `Depends on:`, `Slices:`, `Interfaces:`) as nested list items rather than bare `Key: value` paragraph lines. As paragraph lines they are reflow food: `rumdl` in normalize mode glues them onto neighbouring prose, silently changing what a field says. A nested list is immune, verified, and this runbook now uses it. `/Users/david/code/edify` is outside this session's write scope, so a proposal there is a separate session's work.

## Remaining

- Execute the runbook: Phase 1 (Items 1.1-1.4), Phase 2 (Item 2.1), Phase 3 (Items 3.1-3.6), Phase 4 (Item 4.1). `/proof` over the runbook was deliberately skipped; the corrector's report is `plans/2026-09-15-first-release-version/reports/runbook-review.md`.
- The runbook sits just under the 400-line cap `tests/docs-test.sh` enforces over `plans/`, so anything added to it has to buy the space back.
- After the toolkit release, drop a note — not an edit — for `plugin-craft:toolkit-release`, whose first-release wording changes.
- Root `memory/MEMORY.md` is over Claude Code's loader cap, so entries past the cutoff never reach a session. `/gitlore:index-audit` is the pass that addresses it. Parked; raise only if asked.

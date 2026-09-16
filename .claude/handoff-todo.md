## Open decisions

- **Whether `toolkit/release.sh` gets split.** Now 543 lines against a 400-line
  soft guideline; no gate measures source files. Two code reviews named the same
  seam — the tag-listing helpers (`semver_tags`, `release_tags`, and Item 1.2's
  `origin_release_tags`) are the one cohesive unit with no dependency on the
  release flow's globals — and both declined, because a second file is a new
  **shipped path** (`tests/dist-tree-test.sh`, the CLAUDE.md Layout list), i.e.
  a distribution change rather than a refactor. Decide after Phase 1 lands, on
  the file as it actually reads.
- **The marketplace-writability false refusal.** Flagged by the Item 1.1 slice 1
  code review: a first release whose entry already agrees passes through
  `check_marketplace_writable` for a write that never happens (`bump_marketplace`
  short-circuits on `cmp -s`), so a read-only `MARKETPLACE_DIR` refuses it with
  advice about a write it would not do. Fails closed, recovery works, but it is
  a false refusal that did not exist before. Fixing it means moving the check
  after `release_preflight`. Item 1.2 edits `release_preflight`'s head anyway —
  natural place to decide. Raise at the Phase 1 boundary if not sooner.
- **Phase 4 needs my human partner's explicit go-ahead.** `just release minor`
  is outward-facing and irreversible; the runbook marks it never an autonomous
  dispatch. Stop at the end of Phase 3 and ask.
- **Item B of the brief** (a `toolkit/README.md` note on
  `sandbox.excludedCommands` for the marketplace push) is out of the runbook's
  scope. The claim came from another agent, checked against CC 2.1.263; verify
  against current Claude Code before writing it.
- **edify's `skills/runbook/references/runbook-format.md`** should arguably
  prescribe item fields as nested list items rather than bare `Key: value`
  paragraph lines, which `rumdl` in normalize mode glues onto neighbouring
  prose. Verified; this runbook already uses the nested form.
  `/Users/david/code/edify` is outside this session's write scope — a separate
  session's proposal.

## Remaining

- **Phase 1 (tdd), continuing:** Item 1.2 (6 slices — origin probe), Item 1.3
  (2 slices — `common_preflight` refuses a diverged push route), Item 1.4
  (4 slices — `resume_preflight`'s no-tag hint ladder). Item 1.4 depends on 1.2.
- **Phase 2 (tdd):** Item 2.1, `toolkit/version-guard.sh` message branch, 6
  slices. Independent of Phase 1.
- **Phase 3 (inline, orchestrator executes):** Items 3.1-3.6 — docs. 3.4 edits
  `docs/design.md`; 3.6 is the changelog record plus its index line.
- **Phase 4:** Item 4.1, toolkit self-release at `minor`. Gated on go-ahead.
- **Phase boundary after each phase:** `just precommit`, `git diff --name-only`,
  then an `edify:corrector` checkpoint dispatch (`phase-P-corrector`) with
  non-empty IN/OUT and a changed-files list.
- **At completion:** `edify:tdd-auditor` (`tdd-audit`) over every slice's RED,
  GREEN and review reports; then the run summary; follow-up is
  `/deliverable-review plans/2026-09-15-first-release-version` (opus, fresh
  session).
- After the toolkit release, drop a **note — not an edit —** for
  `plugin-craft:toolkit-release`, whose first-release wording changes.
- The runbook sits just under the 400-line cap `tests/docs-test.sh` enforces
  over `plans/`; anything added has to buy the space back.
- Root `memory/MEMORY.md` is over Claude Code's loader cap, so entries past the
  cutoff never reach a session. `/gitlore:index-audit` addresses it. Parked;
  raise only if asked.

## Open decisions

Three findings referred up by the **Phase 1** checkpoint and put to my human
partner, who has not answered. Decisions 2 and 3 are Phase 3 content; decision 1
is a code change that fits no remaining phase. My stated recommendations:

1. **`release.sh:235` — a live latent fail-open, outside the runbook's scope.**
   `if jq -e --arg n "$plugin_name" 'any(.plugins[]; .name == $n)'
   "$marketplace_json"` reads jq's *error* status (5 on malformed JSON) as "no
   entry". In `--resume` mode nothing catches it and the run dies inside
   `bump_marketplace` **after the GitHub release is already public**. Same
   family Phase 1 fixed five times; the one remaining site with a live
   consequence. **Recommended: fix now as a small scoped addition.**
2. **Both new hint branches dead-end.** Item 1.2's lost-tags hint and Item 1.4's
   branch 2 both terminate in the pre-existing drift refusal at
   `release.sh:474`, whose remedies are useless for a *committed* hand-advance:
   `git checkout HEAD -- .claude-plugin/plugin.json` is a no-op, and "`git fetch
   --tags` and re-run" is the fetch the operator just performed on the previous
   hint's instruction. Measured in both modes; two scenarios assert that text.
   **Recommended: fold the rewording into Phase 3.**
3. **FR-6 names three push-redirect keys; `url.<base>.pushInsteadOf` is a
   fourth** the refusal's wording implies is covered and isn't.
   **Recommended: record as a known bound in Phase 3's docs.**

## Remaining

- **Phase 3 (inline, orchestrator executes, no dispatch):** Items 3.1-3.6 docs.
  3.4 edits `docs/design.md`; 3.6 is the changelog record plus its index line.
  Also carries open decisions 2 and 3 above if approved.
- **Phase 3 records these settled bounds rather than reopening them:**
  `toolkit/release.sh` is not split (791 lines = 380 code / 381 comment / 30
  blank; the executable artifact is under the cap, the overage is argument prose
  CLAUDE.md forbids shaving, and a second file is a new *shipped* path); the
  marketplace-writability false refusal stays (fails closed, recovery works,
  code and comment agree it is deliberate); the steady-state deny wording
  doubles as the "don't know" answer and ships unqualified (argued in
  `reports/item-2-1-s5-s6-code-review.md` §6 — a qualifier turns a directive
  into a conditional the agent can only resolve by doing the git work the hook
  just failed at); the hardcoded eight-name `GIT_*` `unset` list is right over
  `unset $(git rev-parse --local-env-vars)`, because that discovery call is
  itself a `git` invocation and would clear nothing in exactly the runs where
  the listing is unreliable.
- **Phase 4:** Item 4.1, toolkit self-release at `minor` — **outward-facing and
  irreversible. Stop at the end of Phase 3 and ask explicitly. Never an
  autonomous dispatch.**
- **At completion:** `edify:tdd-auditor` (`tdd-audit`) over every slice's RED,
  GREEN and review reports; then the run summary; follow-up is
  `/deliverable-review plans/2026-09-15-first-release-version` (opus, fresh
  session).
- **After the toolkit release:** drop a **note — not an edit —** for
  `plugin-craft:toolkit-release`, whose first-release wording changes.
- **Run-summary note (list revision):** the runbook was NOT edited to record
  that Item 1.2 slices 2-5, all of Item 1.4, and Item 2.1 slices 2-4 ran as
  batched characterization-guard slices — it sits at 396 lines against the
  400-line cap `tests/docs-test.sh` enforces over `plans/`, and anything added
  has to buy the space back. The deviation is recorded in the committed reports
  instead. Carry it into the run summary.
- **`toolkit/release.sh:151` cites `outline.md` from shipped code.** `toolkit/`
  is the dist boundary; a consumer vendors the file and reads a pointer at a
  document they do not have. The Phase 2 sweep confirms it is now the only
  remaining such citation anywhere under `toolkit/`.
- **Three pre-existing `ls-remote | cut` captures** at
  `release.sh:438,466,562` — measured to fail closed, but only via `pipefail`.
  `:466` would skip the "refusing to move a published tag" guard if that ever
  lapsed. Out of scope throughout Phases 1-2; still open.
- **Split `tests/hook-test.sh` (498 lines) by script under test, as its own item
  after this plan.** Decided not to do it inside Phase 2: the `check-version`
  scenarios are self-contained apart from `$proj` and `assert_eq`, but removing
  them still leaves ~440, and a second cut inside the version-guard half needs a
  sourced helper file plus renaming what `justfile:9,11` invokes by name — a
  refactor, not a checkpoint. Evidence in `reports/phase-2-corrector.md` §(b).
- Root `memory/MEMORY.md` is over Claude Code's loader cap, so entries past the
  cutoff never reach a session; `/gitlore:index-audit` addresses it. Parked —
  raise only if asked. The durable lesson this run produced (mutation-test a
  refusal's *prose*, not just its decision) is unwritten for that reason.

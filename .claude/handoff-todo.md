# Todo

## Open decisions

Three findings were referred up by the Phase 1 checkpoint and put to my human
partner in the last message; **none blocks Phase 2**. My stated recommendations:

1. **`release.sh:235` — a live latent fail-open, outside the runbook's scope.**
   `if jq -e --arg n "$plugin_name" 'any(.plugins[]; .name == $n)'
   "$marketplace_json"` reads jq's *error* status (5 on malformed JSON) as "no
   entry". In `--resume` mode nothing catches it and the run dies inside
   `bump_marketplace` **after the GitHub release is already public**. Same
   family this phase fixed five times; the one remaining site with a live
   consequence. **Recommended: fix now as a small scoped addition to Phase 1.**
2. **Both new hint branches dead-end.** Item 1.2's lost-tags hint and Item 1.4's
   branch 2 both terminate in the pre-existing drift refusal at `release.sh:474`,
   whose remedies are useless for a *committed* hand-advance:
   `git checkout HEAD -- .claude-plugin/plugin.json` is a no-op, and "`git fetch
   --tags` and re-run" is the fetch the operator just performed on the previous
   hint's instruction. Measured in both modes. Two scenarios assert that text.
   **Recommended: fold the rewording into Phase 3.**
3. **FR-6 names three push-redirect keys; `url.<base>.pushInsteadOf` is a
   fourth** the refusal's wording implies is covered and isn't.
   **Recommended: record as a known bound in Phase 3's docs.**

**Settled this session — do not relitigate:**

- **`toolkit/release.sh` is NOT split.** Measured 791 lines = 380 code / 381
  comment / 30 blank. The executable artifact is under the 400-line cap; the
  overage is argument prose CLAUDE.md forbids shaving. The tag-listing seam four
  reviews named is 61 lines and static; growth is in the three preflights, which
  share nine globals. A second file is a new *shipped* path
  (`tests/dist-tree-test.sh`, the CLAUDE.md Layout list).
- **The marketplace-writability false refusal stays.** Reproduced: a read-only
  `MARKETPLACE_DIR` refuses a first release whose entry already agrees, for a
  write `bump_marketplace` would skip on `cmp -s`. Fails closed, recovery works,
  code and comment agree it is deliberate. Phase 3 records the bound.

## Remaining

- **Phase 2 (tdd):** Item 2.1, `toolkit/version-guard.sh` message branch, 6
  slices. Independent of Phase 1 — start here.
- **Phase 3 (inline, orchestrator executes, no dispatch):** Items 3.1-3.6 docs.
  3.4 edits `docs/design.md`; 3.6 is the changelog record plus its index line.
  Also carries open decisions 2 and 3 above if approved.
- **Phase 4:** Item 4.1, toolkit self-release at `minor` — **outward-facing and
  irreversible. Stop at the end of Phase 3 and ask explicitly. Never an
  autonomous dispatch.**
- **Phase boundary after each phase:** `just precommit`, `git diff --name-only`,
  then an `edify:corrector` checkpoint (`phase-P-corrector`) with non-empty
  IN/OUT and a changed-files list. The Phase 1 one found two real defects the
  per-slice reviews could not see, so do not skip it.
- **At completion:** `edify:tdd-auditor` (`tdd-audit`) over every slice's RED,
  GREEN and review reports; then the run summary; follow-up is
  `/deliverable-review plans/2026-09-15-first-release-version` (opus, fresh
  session).
- **After the toolkit release:** drop a **note — not an edit —** for
  `plugin-craft:toolkit-release`, whose first-release wording changes.
- **Run-summary note (list revision):** the runbook was NOT edited to record
  that Item 1.2 slices 2-5 and all of Item 1.4 ran as batched
  characterization-guard slices — it sits at 396 lines against the 400-line cap
  `tests/docs-test.sh` enforces over `plans/`, and anything added has to buy the
  space back. The deviation is fully recorded in the committed reports instead.
  Carry it into the run summary.
- **Three pre-existing `ls-remote | cut` captures** at `release.sh:438,466,562`
  — measured to fail closed, but only via `pipefail`. `:466` would skip the
  "refusing to move a published tag" guard if that ever lapsed. Out of scope
  throughout Phase 1; still open.
- Root `memory/MEMORY.md` is over Claude Code's loader cap, so entries past the
  cutoff never reach a session. `/gitlore:index-audit` addresses it. Parked;
  raise only if asked.

## Open decisions

- **Run Phase 4?** Item 4.1 cuts the toolkit's own `minor` release —
  outward-facing and irreversible, and the runbook requires an explicit
  go-ahead. Nothing else in the run is blocked on it.
- **`release.sh:235` — a live latent fail-open, outside the runbook's scope.**
  `if jq -e --arg n "$plugin_name" 'any(.plugins[]; .name == $n)'
  "$marketplace_json"` reads jq's *error* status (5 on malformed JSON) as "no
  entry". In `--resume` mode nothing catches it and the run dies inside
  `bump_marketplace` **after the GitHub release is already public**. Same family
  Phase 1 fixed five times; the one remaining site with a live consequence.
  Recommended: fix now as a small scoped addition.
- **Reword the drift refusal at `release.sh:477`?** Item 1.2's lost-tags hint
  and Item 1.4's branch 2 both dead-end there, and its two remedies are useless
  for a *committed* hand-advance: `git checkout HEAD --
  .claude-plugin/plugin.json` is a no-op, and "`git fetch --tags` and re-run" is
  the fetch the operator just performed on the previous hint's instruction.
  Measured in both modes; two scenarios assert that text. Recommended: reword.
  Phase 3's docs are complete either way.
- **Record `url.<base>.pushInsteadOf` as a stated bound?** FR-6 names three
  push-redirect keys; this is a fourth that the refusal's wording implies is
  covered and is not. Recommended: state the bound in
  `docs/references/recovery.md` and in the code comment, no code change. Phase
  3's docs are complete either way.

## Remaining

- **Phase 4:** Item 4.1, the toolkit self-release at `minor`.
- **At completion:** `edify:tdd-auditor` (`tdd-audit`) over every slice's RED,
  GREEN and review reports; then the run summary. Follow-up is
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
  document they do not have. The Phase 2 sweep confirmed it is the only
  remaining such citation anywhere under `toolkit/`.
- **Three pre-existing `ls-remote | cut` captures**, recorded at
  `release.sh:438,466,562` during Phase 1 and possibly shifted since — measured
  to fail closed, but only via `pipefail`. `:466` would skip the "refusing to
  move a published tag" guard if that ever lapsed. Out of scope throughout
  Phases 1-3; still open.
- **Split `tests/hook-test.sh` (498 lines) by script under test**, as its own
  item after this plan. Decided against doing it inside Phase 2: removing the
  `check-version` scenarios still leaves ~440, and a second cut inside the
  version-guard half needs a sourced helper file plus renaming what
  `justfile:9,11` invokes by name — a refactor, not a checkpoint. Evidence in
  `reports/phase-2-corrector.md` section (b).
- Root `memory/MEMORY.md` is over Claude Code's loader cap, so entries past the
  cutoff never reach a session; `/gitlore:index-audit` addresses it. Parked —
  raise only if asked. The durable lesson this run produced (mutation-test a
  refusal's *prose*, not just its decision) is unwritten for that reason.

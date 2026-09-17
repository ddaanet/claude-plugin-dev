## Open decisions

Three findings were referred up by the **Phase 1** checkpoint and put to my
human partner, who has not yet answered. None blocks Phase 3. My stated
recommendations:

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

From the Item 2.1 slice 5-6 code review, both minor and both mine to call:

4. **Restructure the filter's status capture** to
   `release_tags="$(grep … <<<"$listing")" || grep_status=$?` with
   `grep_status=0` initialised above it, replacing the `if`/`else` form. It
   binds the capture to the status in one statement, so no later insertion can
   separate them — today a single `[[ … ]]` inserted above `grep_status=$?`
   both clobbers `$?` and kills the hook (measured: rc 1, no stdout, bypass).
   Currently a comment guards it instead. Rewrites control flow three reports
   document by shape, for no present behaviour change.
5. **Whether to split `tests/hook-test.sh`** (439 lines, past CLAUDE.md's
   400-line guidance; `tests/docs-test.sh` caps only `docs/` and `plans/`, so
   no gate fails). A clean seam exists: version-guard scenarios vs
   check-version ones, sharing only `$proj`, `$market` and three generic assert
   helpers.

## Remaining

- **Close the M1 coverage gap (major, test-side).** No scenario covers a
  failing *filter*. Dropping
  `[[ "$grep_status" -eq 1 ]] || listing_failed=1` from
  `toolkit/version-guard.sh` leaves the suite green, and under that mutation a
  plugin that **has** released gets the permissive initial-release wording —
  the exact failure Item 2.1 exists to prevent. Fix: a scenario prepending a
  `grep` stub that exits 2 to `guard_path` (same mechanism the existing 127
  `git` stub uses), asserting steady-state wording against
  `$git_tagged_proj`. Detail in
  `plans/2026-09-15-first-release-version/reports/item-2-1-s5-s6-code-review.md`
  §2.
- **Phase 2 boundary:** `just precommit`, `git diff --name-only`, then an
  `edify:corrector` checkpoint (`phase-2-corrector`) with non-empty IN/OUT and
  a changed-files list. The Phase 1 checkpoint found two real defects the
  per-slice reviews could not see — do not skip it.
- **Phase 3 (inline, orchestrator executes, no dispatch):** Items 3.1-3.6 docs.
  3.4 edits `docs/design.md`; 3.6 is the changelog record plus its index line.
  Also carries open decisions 2 and 3 above if approved.
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
  document they do not have. The same issue was fixed in
  `toolkit/version-guard.sh`. Worth a sweep.
- **Three pre-existing `ls-remote | cut` captures** at
  `release.sh:438,466,562` — measured to fail closed, but only via `pipefail`.
  `:466` would skip the "refusing to move a published tag" guard if that ever
  lapsed. Out of scope throughout Phases 1-2; still open.
- Root `memory/MEMORY.md` is over Claude Code's loader cap, so entries past the
  cutoff never reach a session. `/gitlore:index-audit` addresses it. Parked;
  raise only if asked.

**Settled — do not relitigate:**

- **`toolkit/release.sh` is NOT split.** 791 lines = 380 code / 381 comment /
  30 blank. The executable artifact is under the cap; the overage is argument
  prose CLAUDE.md forbids shaving. A second file is a new *shipped* path.
- **The marketplace-writability false refusal stays.** Fails closed, recovery
  works, code and comment agree it is deliberate. Phase 3 records the bound.
- **The steady-state wording doubling as the "don't know" answer ships
  unqualified.** Two of its sentences can be false when the listing failed, but
  both push the agent toward the recipe and away from editing; a qualifier
  converts a directive into a conditional the agent can only resolve by doing
  the git work the hook just failed at. Argued in the slice 5-6 code review §6.
- **The hardcoded eight-name `GIT_*` list** is right over
  `unset $(git rev-parse --local-env-vars)`: that discovery call is itself a
  `git` invocation, and it would clear nothing in exactly the runs where the
  listing is unreliable. Measured: `GIT_DIR` is the only variable of any kind
  that redirects the listing, and it is cleared.

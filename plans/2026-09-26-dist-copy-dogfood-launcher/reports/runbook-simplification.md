# Simplification Report

**Runbook:** plans/2026-09-26-dist-copy-dogfood-launcher/runbook.md **Date:**
2026-09-29

## Summary

- Items before: 11 (1.1–1.3, 2.1–2.2, 3.1–3.6)
- Items after: 11
- Consolidated: none
- Other change: the requirements mapping table and the items' `Requirements:`
  lines disagreed. I reconciled them (see below).
- Length after `just format-docs`: 395 lines (cap 400; 392 before).

## Consolidations Applied

None. None of the candidates saves a dispatch without costing something the
runbook protects on purpose.

## Patterns Not Consolidated

- **1.2 + 1.3 (independent same-module functions).** Both are `dogfood.sh`
  subcommands in `tests/dogfood-test.sh`, and both depend only on 1.1. The
  outline's item 2 groups them. Reasons not to merge:
  - Neither is a small function. Together they have 9 slices and far more than
    the ≤8-assertion bound.
  - They carry different requirements (D6 and D7).
  - Dispatch cost is per slice, not per item, so merging saves nothing.
- **Folding later slices into a slice 1 (identical-pattern at slice level).**
  Candidates: 1.2/3's extra allow paths into 1.2/1, and 2.1/2's
  inherited-variable case into 2.1/1's export assertion. These look like
  same-assertion, varied-data cases.
  - Left alone because folding would replace a real discrimination proof with an
    empty one. As separate slices, each must fail against the previous GREEN, or
    be proven by a named mutation (the "Genuine red" rule), such as
    `dist/plugin*` without the slash, or appending instead of overwriting.
  - Folded into slice 1, each would be red only because the subcommand or shim
    does not exist yet. That red says nothing about the prefix or overwrite
    behaviour.
- **1.3/2 + 1.3/3 (silent vs warn entry matching).** A merged slice would hold
  tests that already pass at RED (the warn cases pass against 1.3/1's exact
  match), so the mutation step would still be needed. Nothing saved.
- **1.1/4 into 1.1/1.** Not merged. A naive `--files-from` GREEN copies no
  `memory/fact.md`, so the merge would push 1.1/1's GREEN toward the ignore-list
  sync and take away 1.1/2's genuine red. The brief rules this out.
- **2.2/2, 2.2/3 into 2.2/1.** No gain: against unchanged install.sh both pass
  at RED even inside slice 1, so they need their mutations either way.
- **3.3 + 3.4 (`toolkit/README.md`, `README.md`).** These are different prose
  files, and 3.4 is not trivially small: four edits across four sections. 3.4
  also depends on 3.3's `## Dogfooding` heading. One opus agent can still take
  both in sequence; that is an orchestration choice, not an item merge.
- **3.1 + 3.2.** Code and wiring (`release.just`, `justfile`) versus a new prose
  file, with different requirements (D10 vs D12). Not merged.
- **CLAUDE.md in 1.1/1, 2.1/1 and 3.6.** Left unchanged, per the "Two gates"
  section.

## Requirements Mapping

No items were merged, so the item numbers and every `1.1/7` and `2.1/5`-style
slice reference are unchanged. Checking the table against each item's
`Requirements:` line turned up mismatches in both directions:

- **Items claimed by the table but missing the requirement:**
  - 3.1 was on the D4 and D8 rows but listed only D10.
  - 3.2 was on the D9 row but listed only D12.
- **Items listing a requirement but missing from the table:**
  - 3.3 (D4, D7, D10)
  - 3.4 (D9, D10)
  - 3.6 (D5, D9, D10)
  - 3.5 (D1–D12)

Fixes, all in runbook.md:

- 3.1's Requirements is now `D4, D8, D10`. D4 lists `just dogfood` as a
  promotion trigger, and D8 says `just dogfood` exits non-zero with rsync's
  stderr.
- 3.2's Requirements is now `D9, D12`, for its `PATH_add plugin-dev/bin` step.
- Table rows widened:
  - D4 gains 3.3.
  - D5 gains 3.6, and its phase column becomes 1, 3.
  - D7 gains 3.3, and its phase column becomes 1, 2, 3.
  - D9 gains 3.4 and 3.6.
  - D10 gains 3.3, 3.4 and 3.6.
- One sentence under the table says 3.5 carries D1–D12 as documentation and is
  therefore on no row.

A script compared the table with the items' `Requirements:` lines: D1–D12 all
match, with 3.5 excluded as the note states. Every requirement is still traced
to the items that carry it.

## Constraints check

- Field lines are still nested bullets.
- No model lines or code blocks were added.
- Only runbook.md was edited, apart from this report. Nothing was committed.

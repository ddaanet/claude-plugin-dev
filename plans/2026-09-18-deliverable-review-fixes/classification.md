# Classification — deliverable-review fix pass

Produced by `/edify:design` on 2026-09-18 over
`plans/2026-09-15-first-release-version/reports/deliverable-review.md` (Critical
0, Major 6, Minor 15).

## Requirements-clarity gate

- **Requirements source:** `reports/deliverable-review.md` — 6 Major, 15 Minor,
  each carrying file:line, a failure scenario, and (for the Majors) a stated fix
  shape.
- **Completeness:** concrete mechanism per item **Y**; measurable criterion
  **Y** — each item's criterion is a named mutation that must go red.
- **Routing:** proceed to triage. No `/requirements` pass; the findings are
  mechanism-specified and the task frame froze them against re-derivation.

## Multi-item decomposition

Trigger: **implicit bundling** — the input artifact enumerates 21 discrete
findings. Three clusters; every item named with its own behavioral-code check.

### Cluster A — production code, logic paths change

| Item | Finding | Behavioral? |
|---|---|---|
| A1 | M2 `release.sh:307` `release_tags()` pipe → capture | Yes |
| A2 | Minor 1 `release.sh:577` `printf \| grep -qxF` EPIPE | Yes |
| A3 | Minor 2 `self-release.sh:109` `git describe` → tag listing | Yes |

### Cluster B — test suites

B1 (M1 dist split discriminates tag from HEAD), B2 (M3 `.claude/` exemption
vacuous, `memory` half absent), B3 (M4 nine refusals assert message only), B4
(Minor 3), B5 (Minors 4 and 6), B6 (Minor 5), B7 (Minor 8 harness divergence).
Behavioral check: **Yes** for all seven — B2 and B3 add fixture helpers, the
rest restructure fixtures so an assertion has something to be wrong about.

### Cluster C — prose

C1 (M6 `version-guard.sh:3-7` header), C2 (M5 `version-guard.md:44-48` parity
claim), C3 (Minor 15), C4 (Minor 9 + 2 further stale citations the review did
not find), C5 (Minor 10), C6 (Minor 11), C7 (Minor 12), C8 (Minor 13), C9 (Minor
14 recorded as a bound), C10 (changelog record), C11 (baseline defect left
standing, stated so). Behavioral check: **No** for all eleven — comments, design
nodes, a README line.

## Classification

- **Classification:** Moderate (clusters A and B); Simple (cluster C, batched)
- **Implementation certainty:** High — every fix shape is stated in the review
  and was verified against current code at `8d3fbf5`
- **Requirement stability:** High — findings written, verified and frozen
- **Behavioral code check:** Yes for A and B → Moderate minimum; No for C
- **Work type:** Production
- **Artifact destination:** production (`toolkit/`, `scripts/`, `tests/`) and
  investigation (`docs/`)
- **Evidence:** `craft:test-discipline` — cluster B is its "green nobody watched
  go red"; `reference-audit-after-a-move` — C4's exit condition is a whole-tree
  sweep, which grew the stale count from 1 to 3; `examine-evidence-drift` —
  C1/C2 are drift between co-maintained surfaces

**Author change:** none. No edify author skill is touched, so no corrector or
validator coupling applies.

**Routing:** Moderate, non-prose path → `outline.md`, `/proof`, `/runbook`.
Cluster A pairs each code change with the mutation that must go red; B is
tdd-shaped; C is inline.

## Decisions taken at triage

My human partner took the stated defaults on all four forks:

1. The self-release half **is** in scope — all six Majors.
2. `toolkit/release.sh`'s comment volume: **leave the comments**, record the
   volume as a known bound (C9).
3. `version-guard.sh:170-171`'s frozen wording: **rewrite** — the freeze was
   scoped to a plan that has now shipped.
4. `outline.md:262`'s three-vs-four hint count: **leave the outline alone**
   (C11). It is a dated executed artifact; the review report carries the
   correction.

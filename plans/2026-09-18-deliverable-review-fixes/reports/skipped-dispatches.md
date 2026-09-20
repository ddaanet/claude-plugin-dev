# Skipped dispatches — Phase 1 code reviews

**Written 2026-09-20, after the fact.** This record was not kept during the run.
It was reconstructed by an agent that witnessed none of the decisions it
describes, from two sources: the delegates' running log at
`/tmp/claude/orchestrate-report.md`, and `reports/tdd-audit.md`. Every commit
statistic below was re-verified with `git show --stat` rather than taken from
either source. It exists because the audit's second Critical is that no skip
decision was ever committed — the reasons lived only in a `/tmp` log, which is
what let a fourth omission sit indistinguishable from three justified skips.

Phase 1 ran six TDD slices. `reports/` holds two slice code reviews,
`item-1-1-s1-code-review.md` and `item-1-2-s2-code-review.md`. The four absences
are below: three recorded decisions, one omission.

## The three recorded skips

Each is a slice whose commit changed no implementation file — the second
assertion group over the other slice's production change, or a control. Scope IN
for a slice code review is the implementation files, so the dispatch would have
had an empty scope.

- **Item 1.1, slice 2/2 — commit `45891f8`** (`tests/release-test.sh`, 1 file,
  59 insertions).
  - The log records it under its own heading, "Item 1.1 slice 2/2 — code review,
    SKIPPED with reason": "Slice 2 changed no implementation file;
    `toolkit/release.sh` was already reviewed under `item-1-1-s1-code-review`,
    and the test itself was reviewed under `item-1-1-s2-test-review`. A dispatch
    here would have an empty scope, which the review-requirement fragment
    forbids delegating on. The Phase 1 boundary corrector reads the whole phase
    diff regardless."
- **Item 1.2, slice 1/2 — commit `d0c13b9`** (`tests/release-test.sh`, 1 file,
  60 insertions).
  - The log: "Slice 1 code review skipped: no implementation file changed. Same
    reason as Item 1.1 slice 2."
- **Item 1.3, slice 2/2 — commit `6a77bea`** (`tests/self-release-test.sh`, 1
  file, 27 insertions).
  - The log, in the heading "Slice 2/2 — GREEN, executed by the orchestrator;
    code review skipped": "Code review skipped for the same reason as Item 1.1
    slice 2: no implementation file changed, and `scripts/self-release.sh` is
    covered by the Phase 1 boundary corrector below."

## The omission

- **Item 1.3, slice 1/2 — commit `07b7ae9`**,
  `🐛 Item 1.3/1 — self-release lists and filters tags instead of git describe`.
  - `git show --stat 07b7ae9`: `scripts/self-release.sh | 29 +++++-----`,
    `tests/self-release-test.sh | 19 ++++--`. The scope was not empty: this is
    the only Phase 1 slice that changed a production file without a slice-level
    code review.
  - **No skip note exists.** The log goes from "Slice 1/2 — GREEN
    (`item-1-3-s1-green`)" straight to "Slice 2/2 — RED", with no code-review
    dispatch and no reason given, where all three genuine skips above are logged
    explicitly. Nothing in the log, the runbook or `reports/` records a
    decision. This was an oversight, not a decision.

### Consequence

The per-slice gate that would have caught them was not run, so two Major defects
introduced by `07b7ae9` reached the Phase 1 boundary, where
`reports/phase-1-corrector.md` found both in exactly the region that commit
introduced:

- The landed comment claimed the `dist-v*` lineage "sorts as text after "v" and
  is dropped there, not by the glob" — the opposite of what
  `git tag --list 'v*'` does, which fnmatches from the start of the name so
  `dist-v*` is never listed at all. The corrector measured it in a scratch repo
  before fixing it.
- `latest_tag=$(grep -m1 -E … <<< "$tags") || latest_tag=""` folded grep's
  status 2 into "no release tag yet", skipping the drift guard on a real filter
  error — the same fail-open class Item 1.1 exists to close, one stage down the
  same function.

Both were fixed at the phase boundary in **`73d46da`**,
`🐛 Phase 1 — boundary checkpoint fixes` (`scripts/self-release.sh` 29,
`tests/release-test.sh` 3, `tests/self-release-test.sh` 7, `toolkit/release.sh`
5, plus the corrector report). The remedy for the omission itself is
documentary, and is this file.

The audit's own recommendation — that a skipped dispatch should leave a stub
report naming the slice, the commit and the `git show --stat` line proving the
scope was empty — belongs in the execution skill's dispatch rules, not in this
runbook. It is carried to my human partner as an open finding of the run.

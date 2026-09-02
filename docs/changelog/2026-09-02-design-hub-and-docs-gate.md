# 2026-09-02 — The design doc became a hub, and docs got a gate

`docs/design.md` had reached 837 lines / 45KB — about 11k tokens to read whole,
which is what a session pays before touching anything the doc governs. Nothing
gated it, and nothing signalled the growth: it had simply been appended to,
correctly, twenty decisions deep.

Measurement first, because the fix depends on the shape. No entry dominated —
the largest section was 86 lines, 10% of the file, and the rest spread evenly
from 8 to 79. That is the flat shape, so the cut is by need-time rather than by
extracting one overgrown subsystem: what is a session about to work on?

Four nodes under `docs/references/`, and the hub keeps motivation, requirements,
limitations and a one-line conclusion per decision:

- `distribution.md` — subtree vendoring, the `dist-` split ref, tags-only
  versioning, the separate repository, `install.sh`, `update.sh`, migration
  notes, the `VERSION` file.
- `release-flow.md` — the last-released invariant, first release, marketplace
  entry, non-interactive release, `precommit` naming, the `prerelease` gate,
  branch detection.
- `recovery.md` — `check-version.sh`, `resume-release`, the clean-tree
  exclusions.
- `version-guard.md` — dual-channel hook output.

The hub is 181 lines and the largest node 246, so both a first read and a
targeted one now cost a fraction of the whole. No prose was rewritten in the
move: sections were sliced verbatim and demoted one heading level, and the four
cross-references that pointed at a section now in another file were repointed at
that file. The others already read correctly, because the sections they name
travelled together.

## The gate, and why the wrap comes first

`tests/docs-test.sh` caps every markdown file under `docs/` and `plans/` at 400
lines and checks that relative pointers resolve. The cap is borrowed from
gitlore, along with its reasoning: an 80-column line is roughly 23 tokens, so
400 wrapped lines stay under 10k — a node a session can read in one go.

The cap only means something because `just format-docs` hard-wraps those paths
first. Without the wrap a file passes by cramming paragraphs onto 300-character
lines, which is worse to read than the overage and defeats the metric while
satisfying it. So the wrap is not cosmetic here; it is what makes the count a
proxy for anything. rumdl 0.2.60 does it, pinned in `pyproject.toml`,
materialized by `uv sync`, put on PATH by direnv — the same setup gitlore uses,
chosen there after a render-diff comparison that ruled out prettier, dprint,
mdformat and remark on rendering changes.

`reflow-mode` matters as much as `reflow` itself. The default mode only breaks
lines already over the column and never re-fills a paragraph wrapped narrower,
which leaves the cap measuring the wrap rather than the content: prose
hand-wrapped at 60 columns sits at 1.3x the line count of the same words at 80,
and stays under a cap it should not be under. `normalize` re-fills every
paragraph. On this tree it was the difference between 85 lines changed and 276
across 31 files, and it took the hub from 190 lines to 181. Word streams before
and after are identical except for the `>` markers a rewrapped blockquote
continuation line gains, which is wrapping rather than a change.

Two landed plans exceed the cap (1100 and 482 lines). They carry
`<!-- cap-ok -->`. Splitting a plan that already shipped churns a record nobody
will read again, and the cap exists to bound what a session must read *before*
working. A living doc does not get the marker — it gets split.

## What was deliberately not built

gitlore's `scripts/check-docs-links.py` runs nine checks over its docs graph,
seven of which assume a `D<n>` decision numbering: unstubbed decisions,
duplicate conclusions, delegation drift. Adopting them here would mean
renumbering twenty titled sections as `D1`–`D20`, and buying a checker whose
semantics this repo does not yet need. The two checks that hold without the
numbering — the cap and pointer resolution — were reimplemented in ~70 lines of
bash instead, which is also what the rest of this repo is written in.

That is a knowing duplication: gitlore's checker and this one will drift, and
neither propagates to the other. The alternative was a shared dependency between
two repos that have no other coupling, to spare 70 lines.

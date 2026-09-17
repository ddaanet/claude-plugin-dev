# 2026-09-17 — `recovery.md` splits off this repo's own release

`docs/references/recovery.md` was 389 lines against the 400-line cap, having
absorbed the self-release material when `scripts/self-release.sh` landed earlier
today. The cap was about to fail on the next paragraph written there, and the
file was the only node with two audiences in it.

The cut is by boundary rather than by size. Everything about a *consumer's*
recovery stays — `check-version.sh` detection, `resume-release`, the shared
release tail, the refusal ladder, the clean-tree exclusions — and everything
about *this repo's* release moves to `docs/references/self-release.md`: why the
two scripts are deliberately not shared, the shape the self-release borrows
anyway, the `toolkit/VERSION`-is-the-only-witness guard, and the two-tag resume.
`recovery.md` lands at 352 lines, the new node at 78.

The clean-tree exclusions were the one section that spans both, so they were
placed rather than assigned. The argument for *why* `.claude/` and the gitlore
gitlink are exempt is consumer-facing and stays in `recovery.md`; the fact that
the self-release spells them as literal pathspecs instead of a `.gitmodules`
lookup is a claim about this repo and goes with the rest of it. Two one-line
pointers cross the seam, one in each direction.

## A stale paragraph the split surfaced

`recovery.md` still carried the pre-split argument that the self-release has no
`resume-release` of its own: "resuming it by hand is a tag and a
`gh release create`, which the toolkit's sole maintainer can do;
`resume-release` exists as a convenience for consumers." Thirty lines further
down, the section added this morning described the `just resume-release` the
self-release now has. The two paragraphs had never been read against each other
because nothing brings them into the same view — which is the failure mode a
400-line node is supposed to make less likely, and here the node was at the cap.

Rewritten in place per the living-doc rule rather than struck through. What
survived the correction is the part that was never about recovery: the two
scripts stay separate because one is consumer-shaped and the other is not, and
folding them together would make the toolkit consume its own consumer-shaped
code. What was dropped is only the by-hand claim, which the earlier change had
already falsified.

The hub gains a fifth decision group with five conclusions, none of which it
carried before — the self-release material had been living under a heading whose
group bullets never covered it.

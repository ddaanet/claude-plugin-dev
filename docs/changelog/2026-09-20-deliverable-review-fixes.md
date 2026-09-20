# 2026-09-20 — The first-release pass reviewed, and what the diff does not say

`/deliverable-review` over the 2026-09-15 first-release-version pass returned 6
Major, 15 Minor and one baseline defect. This entry records the pass that
executed them — planned on 2026-09-18, finished on 2026-09-20 — and the three
things it decided that reading the diff afterwards would not recover.

Most of the findings were narrow and their fixes speak for themselves: a
production path that answered "never released" for a listing that had failed, a
test suite asserting one property of a refusal that carried four, a hub bullet
restating its own node's argument, a manual saying "the latest tag" where its
own conventions said `vX.Y.Z`. Three do not.

## Citing a script by line number is now refused, by a check

Four of the five `<script>.sh:<line>` citations in this repo's tracked files
pointed at different code than when they were written. The number keeps parsing
after either file moves, and a reader who follows it lands somewhere plausible
with nothing raised — the failure mode of a citation is silence. The convention
that replaces it: name the enclosing symbol and quote a short fragment, which
survives an edit above it and fails visibly when the fragment goes.

It is enforced by `tests/citation-test.sh` rather than written as a `CLAUDE.md`
Conventions bullet, and that is the decision worth recording. A bullet would
duplicate a rule proposed upstream, in a brief filed against edify; the day
upstream ships its own version, the local copy becomes a stale duplicate that
nothing reports. A check cannot go stale that way — it either fires or it does
not, and it is the failure message, not a bullet, that carries the convention to
whoever trips it.

The scope is `git ls-files -z` minus `plans/` and `docs/changelog/`. Those are
this repo's frozen dated artifacts, which the convention does not bind for the
same reason it exists: a line number into a document that will never be edited
again is correct forever.

The residual bound is stated in the check's own header and is worth repeating
here, because it is the kind of gap that later reads as coverage. A citation
*into* a `.md` file is never flagged. The three forbidden target forms are
`.sh`, `.just` and `justfile`, and an extension alone cannot separate a living
document from a frozen one — `tests/version-guard-test.sh` cites the executed
outline by line number, and that citation is correct forever and is meant to
stay exactly as it is. Closing the gap would mean a path-by-path rule about
which `.md` files are living, which is the judgement the check was built to
avoid needing.

## The comment volume is accepted, and here are the numbers

`docs/design.md` now names the comment volume of the shipped scripts as an
accepted cost rather than an unnoticed one, and states it as a proportion:
roughly half of `release.sh` is comment-only, much of it write-time record
rather than contract.

The hub says it without figures deliberately. It is a living present-tense
document, and the same pass that added that bullet also edited both `release.sh`
and `version-guard.sh`, so any count written there would have been false on the
commit that landed it — which is the shape of defect this pass exists to fix,
one layer up.

Measured here, where the date makes it stay true: `toolkit/release.sh` is 871
lines, of which 451 are comment-only past the shebang — 52%.
`toolkit/version-guard.sh` is 187 lines with 86 comment-only, 46%. Both were
measured after this pass's own edits to them had landed.

The argument for leaving it is in the hub bullet: the `dist-` tree ships no
`docs/`, so a consumer reading `release.sh` has no changelog to reach for, and
the record stays where its reader is. The cost is that a comment retelling an
incident ages with the code around it.

## The baseline defect was left standing, on purpose

`outline.md:262` of the first-release-version pass says the no-tag refusal has
three hints. The code emits four, that pass's own runbook says four, and
`docs/references/recovery.md` documents four. No deliverable is wrong; the
outline is.

It stays wrong. An executed outline is a dated artifact under `plans/`, and this
repo does not revise those — the review report carries the correction, and that
is where a reader who needs it will be. Recorded here so a later review does not
re-open it as an unfixed finding: it was seen, and left.

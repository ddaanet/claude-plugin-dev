# 2026-08-28 — A refused push resumes; the release commit is never amended

Reported by `brief-release-memory-push-race.md`, which is a finding with a
conclusion rather than a defect: it records why a recovery step that looked
necessary is not, so nobody re-derives it.

The window. `bump_commit_tag` commits — and a consumer's gitlore `pre-commit`
hook commits memory, advances its `live` and stages the gitlink into that very
commit — then tags, then `push_branch` pushes. The parent's `pre-push` hook
publishes each memory store before the parent, and refuses if any store's
`origin/live` moved in between. Under `set -euo pipefail` the script dies with
the commit and the tag landed locally and nothing pushed. The window is
human-paced, not narrow: the memory-approval round on the release commit itself
sits inside it, and it reopens every time a prepared merge is reviewed while
`origin/live` moves again.

The step that was considered was `refresh_release_commit`: after the merge
lands, `commit --amend` so the release commit's gitlink names the merged memory,
then `git tag -f`. It is unnecessary. The gitlink a parent commit records is
always an ancestor of memory's `live`, or `live` itself — each `head-vs-remote`
merge takes the pending commit as its second parent, so it stays an ancestor
however many rounds the merge takes — and a push of `live` publishes every
ancestor. Since `pre-push` publishes memory before the parent, a parent push
that exits 0 already implies the release commit's gitlink is public. Nothing
needs the tagged commit to name the merge, and the amend would have bought only
a tidier tag tree in exchange for force-moving a tag the script is about to
publish and sequencing a scripted rewrite behind a human review.

So no step was added. What was missing was the loop's name at the point of
failure: `git push` was unguarded, and the only text the user got was the hook's
own directive, which says what to resolve but not what to run afterwards.
`push_branch` now names what landed locally, points at `just resume-release`,
and says the pair repeats if the push is refused again. The invariant above sits
as a comment on that guard, because the brief exists precisely because someone
was about to build the wrong thing.

`tests/release-test.sh`'s existing refused-push scenario carries the hint
assertions — confirmed red, the old output ended at git's own
`failed to push some refs` — and one new guard: the tag object sha is unchanged
across the failed release and the resume that completes it. That one was green
on arrival, which is the point; it is there so an amend cannot be reintroduced
quietly.

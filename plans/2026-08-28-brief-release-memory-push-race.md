## Brief: a release push refused by a memory merge is finished by `resume-release` as it stands — do not script an amend

2026-08-28 — target: `claude-plugin-dev` · found from `gitlore`

A finding with a conclusion, not a patch. It records why a recovery step that
looked necessary is not, so nobody re-derives it. The gitlore side of the
argument is stated as D46 in gitlore's
`docs/references/git-hooks-and-entry-points.md`.

## The window

`release.sh` runs `bump_commit_tag` — the release commit's gitlore `pre-commit`
hook commits memory, advances memory's `live`, and stages the memory gitlink
into the release commit — then tags, then `push_branch`. The parent's
`pre-push` hook publishes each tier's `live` and then memory's *before* the
parent push (gitlore NFR5). If any store's `origin/live` moved between the
commit and the push, that hook prepares a merge, prints
`gitlore: memory merge prepared` with the resolve directive, and refuses; under
`set -euo pipefail` the script dies with the commit and the tag landed locally
and nothing pushed.

The window is human-paced, not narrow: the FR11 approval round on the release
commit itself sits inside it, and so does the review of any merge. It can also
reopen — a merge is reviewed by a human and `origin/live` can move again while
that happens, so the push can be refused any number of times before it lands.

## The step that was considered, and why it is wrong

The direction on the table was a `refresh_release_commit` step on the resume
path: after the merge lands, `git commit --amend` the release commit so its
gitlink names the merged memory, then `git tag -f`, guarded by
branch-unpushed and tag-unpublished. gitlore's `pre-commit` would have
cooperated — a plain `--amend` on the tip is not a replay to it, so it re-pins
the gitlink itself.

It is unnecessary, and the reason is an invariant that holds in every round:

**The gitlink a parent commit records is always an ancestor of memory's
`live`, or `live` itself.** `pre-commit` makes it `live` itself. Each
`head-vs-remote` merge takes the pending commit — the one the release recorded
— as its *second* parent (gitlore D6, authority first), so it stays an
ancestor however many times `origin/live` moves and the merge is re-prepared
or re-reviewed.

**The window closes exactly when a push of `live` succeeds.** That push
publishes every ancestor, so `origin/live` contains the gitlink from that
moment; and because `pre-push` publishes memory before the parent, a parent
push that exits 0 implies the release commit's gitlink is public. Nothing in
that needs the tagged commit to name the merge.

A gitlink behind memory's HEAD is gitlore's resting state, not drift: the
session-start fast-forward, `commit-memory.sh` and `/gitlore:merge` all leave
memory ahead of the parent's pointer, it shows as ` M memory` in the parent's
porcelain, and the next parent commit records the move. Nothing walks memory
back to the pointer.

What the amend would have bought is only that the tag's tree names the merged
memory instead of the pre-merge commit, and a clean tree right after the
release. Against that: `tag -f` on a tag the script is about to publish, a
scripted rewrite of a tagged commit, and an ordering dependency on gitlore's
stale-merge guard (the amend is refused while a merge is prepared, so the step
would have had to sequence itself after `/gitlore:resolve` and say so).

## What `resume-release` already does

The existing resume path is the recovery, unchanged:

- `common_preflight` excludes `memory` from its uncommitted-changes check, so
  the floating gitlink does not block it. (That exclusion is what makes this
  work; the hardcoded path is the subject of
  `brief-release-sh-two-nits-from-gitlore-audit.md` §2.)
- `resume_preflight` finds the local tag at the manifest's version.
- `push_branch` sees `origin/<branch>` ≠ `HEAD` and pushes again, which runs
  `pre-push` again — and may be refused again if `origin/live` moved meanwhile.
- `push_tag`, `create_github_release`, `bump_marketplace` proceed as before.

So the loop is: `/gitlore:resolve` in Claude Code (the merge needs the
sub-agent and the approval, which a shell script cannot drive), then
`just resume-release`, repeated until the push lands. No code change is needed
for correctness.

## A preflight that makes the window empty

The loop above is the recovery; the release can also be arranged so it never
runs. `pre-push` yields only on a genuine divergence: a store whose local
`live` is a strict ancestor of `origin/live` is classified `behind`, prints
"nothing to publish — run `/gitlore:merge`", and the push proceeds (gitlore ≥
0.6.0; 0.5.0 stranded the tier on that state). So a release whose memory is
clean and already published cannot yield: the release commit pins nothing new,
and `pre-push` has nothing to send.

The order matters, because `/gitlore:merge` is itself a source of uncommitted
memory. Taking a tier's upstream facts fast-forwards the tier and writes the
root `MEMORY.md` plus the moved gitlink into the memory store, staged but not
committed — an FR11 commit's job. Running `just release` on that state either
hits the commit gate (memory dirty, no approved summary: the stranded-bump
incident in `brief-release-commit-rejection-strands-bump.md`) or, with the
summary approved, puts the approval round back inside the release. The
resolve-free ordering is:

1. Optionally `/gitlore:merge`, then commit memory under its approval — a
   parent commit, or the standalone memory commit — so the tree is clean.
2. `/gitlore:push`, and read its report: every store at its remote, nothing
   uncommitted named as unpublished.
3. `just release`.

A behind tier can be left behind: the release push proceeds past it with the
notice, and taking the facts afterwards dirties memory *after* the release,
where it rides the next ordinary commit. Following the notice between step 2
and step 3 reopens the window step 2 closed.

## Optional, for the maintainer

1. **Name the loop at the failure.** When `git push` in `push_branch` fails,
   the only text is gitlore's own directive, which says resolve but not what
   to run afterwards. A one-line hint after the failure — resolve the memory
   merge (`/gitlore:resolve` in Claude Code), then `just resume-release`;
   repeat if the push is refused again — closes that. Since the hook's own
   message is what the agent reads, keep the hint short and after it.
2. **A test.** `tests/release-test.sh` could carry a case with a `pre-push`
   hook that refuses once and passes on the second call: `release` dies after
   the tag exists locally; `--resume` completes; the tag was never moved
   (`git rev-parse v$V` unchanged across the two runs).
3. **A comment, not a step.** A sentence near `push_branch` saying that a
   refused push is re-pushed after resolve and that the release commit is never
   amended — with the ancestor invariant as the reason — is cheaper than the
   next person re-deriving it.

## Where to look

In `toolkit/release.sh`: `push_branch` (the unguarded `git push`),
`resume_preflight` (accepts exactly the stranded state: local tag, unpushed
branch), `common_preflight` (the `':(exclude)memory'` that lets resume run over
a floating gitlink). Verified against this repo's current `release.sh`.

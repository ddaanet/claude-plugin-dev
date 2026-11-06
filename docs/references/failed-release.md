# The failed release

Why a release that origin's default branch has moved past is redone rather than
resumed, and what a resume refuses, split out of [recovery.md](recovery.md),
which holds the resume flow. The conclusions these arguments support are listed
in [../design.md](../design.md).

## A release origin moved past

When origin's default branch holds commits the release commit lacks,
`push_branch` refuses before pushing, in both modes, so no pre-push hook runs on
a push that cannot land. The branch push is the first publish, so nothing is
public. Merging the other writer's work and resuming would publish a tag on a
commit that lacks it, a combination the gate never saw; the release is redone on
top of it instead. The script prints the undo with every value substituted and
runs none of it, because it rewrites local history:

1. `git fetch --no-tags origin`.
2. `git tag -d <tag>`.
3. Drop the bump, when the release commit changed the manifest's version and an
   earlier release tag exists. If it is `HEAD`, `git reset --hard HEAD~1`.
   Otherwise a `jq '.version = "<previous>"'` write over the manifest and a
   commit of it. A `rebase --onto` that drops the commit conflicts on the
   `memory` gitlink whenever a later commit moved it too, and restoring the
   manifest with `git checkout <rel>^ --` discards a later manifest edit, so
   neither is used; the jq commit rewrites no history and leaves the gitlink. A
   first release has no bump, decided by the absence of an earlier release tag,
   since the commit it tags may have set the version by hand: a reset there
   would drop work. A failed tag listing reads as none, for the same reason.
4. From `dev` only, `git branch -f <main> origin/<main>`, since the run moved
   local main; from main it is absent.
5. `git merge --no-edit origin/<main>`.

Then `just release` with the same bump; a first release repeats it bare. A race
where origin moves after the probe reaches `push_branch`'s failure hint, and the
resume it names lands here.

## A resume refuses a tag off `HEAD`'s history

A resume publishes the tag's commit, so it refuses a tag whose commit `HEAD`
does not contain. It runs no check that `main` or `origin/main` is an ancestor
of `HEAD`: those guard a commit and tag about to be cut, and a release already
on origin's `main` has nothing left they protect. When local main has it, the
hint is `git merge main`. Otherwise, while the tag is not on origin, the hint
re-tags the last commit that changed the manifest's `version` line when an
earlier release tag exists, since only such a release cut a bump commit; a first
release tags `HEAD` as it was, so the hint names no sha and prints no command:
it says to move the tag to the commit the release was meant to publish. A tag
already on origin is never moved, and the hint says to reconcile the branch by
hand.

# The failed release

How a release that origin's default branch has moved past is finished, and what
a resume refuses, split out of [recovery.md](recovery.md), which holds the
resume flow. The conclusions these arguments support are listed in
[../design.md](../design.md).

## A release origin moved past is merged, then resumed

When origin's default branch holds commits the release commit lacks and `HEAD`
lacks too, `push_target` refuses before `move_main` and before any push, in both
modes, so no pre-push hook runs on a push that cannot land. The branch push is
the first publish, so nothing is public. The hint is two commands, the same from
`main` and from `dev`:

```text
git merge origin/<main>
just resume-release
```

The tag stays on the release commit as it was cut. The tag is what fixes the
release's content, and the release commit being an ancestor of the `main` that
is pushed, or that `main` itself, is all publishing needs; so the other writer's
work is merged on top of the release. The merge is made on the branch checked
out, which is the one place a plain `git merge` can make it with no checkout:
from `dev`, local `main` is then fast-forwarded to the merged `HEAD`, as
`move_main` always moves it. A conflict, such as the other writer editing the
`TODO.md` the release commit took, is resolved as any merge conflict is, before
the resume.

On the resume, `push_target` reads origin's head. While it is inside the release
commit, the release commit is what `main` is moved to and pushed, so later
commits stay local. Once origin's head has moved past it and `HEAD` holds both,
`HEAD` is what is moved to and pushed: the merge's first parent is the release
side, its second origin's. Whatever `HEAD` carries beyond the release commit, a
later `dev` commit or a conflict fix, lands on `main` with it; that is
immaterial to the release, whose content the tag already fixed. The tag, the
dist branch, the GitHub release and the marketplace entry stay on the release
commit. The refusal fetches origin's `main` into `origin/<main>` before
printing, because the probe that read origin fetches only when the object is
missing, and the merge the hint names reads that ref. Origin moving again
between the merge and the push lands on the same refusal, and the same two
commands clear it.

A release tag origin already holds at another sha, as when another clone
released the same version first, is refused before `move_main` and before any
push, in both flows and in both modes; the dist tag too, where this clone has
one. The merge above is clean when the other writer's commit is the same bump,
and `push_tag` refuses to move a published tag only after `main` is pushed, so
without this check `main` would carry a release that is not the one origin's tag
names. A tag origin holds at the local sha is a partial push's, and passes.

## A resume refuses a tag off `HEAD`'s history

A resume publishes the tag's commit, alone or inside the merge above, so it
refuses a tag whose commit `HEAD` does not contain. It runs no check that `main`
or `origin/main` is an ancestor of `HEAD`: those guard a commit and tag about to
be cut, and a release already on origin's `main` has nothing left they protect.
When local main has it, the hint is `git merge main`. Otherwise, while the tag
is not on origin, the hint re-tags the last commit that changed the manifest's
`version` line when an earlier release tag exists, since only such a release cut
a bump commit; a first release tags `HEAD` as it was, so the hint names no sha
and prints no command: it says to move the tag to the commit the release was
meant to publish. A tag already on origin is never moved, and the hint says to
reconcile the branch by hand.

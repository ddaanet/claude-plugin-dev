# The release branch

Which branch a consumer release runs from, how local `main` is moved to the
release commit, and the refusals made before any commit or tag. The rest of the
flow is in [release-flow.md](release-flow.md); the conclusions these arguments
support are listed in [../design.md](../design.md).

## Default branch detection via `origin/HEAD`

Neither release flow hardcodes `main`: each reads the default branch from
`git symbolic-ref --short refs/remotes/origin/HEAD` and falls back to `"main"`
if unset. Lets the recipe work on `master`, `trunk`, fork-default branches,
etc., with no behaviour change in the common case.

What the name is used for differs by flow. The consumer flow in `toolkit/` runs
from that branch or from the literal `dev`, refuses every other branch and a
detached `HEAD`, and never changes branch. This repo's own flow,
`scripts/self-release.sh`, accepts the same two; the reasoning is in
[self-release.md](self-release.md). Both publish the tag's commit to the default
branch from either, and never push `dev`: later `dev` commits are not part of
the release, so the push names the release commit, not the branch. A resume from
`main` pushes only the release commit too, so commits made on `main` after it
stay local. The consumer flow's push note therefore names the revision it
uploaded (short sha, subject, age) rather than only the branch, and prints
nothing of the kind when the branch was already there.

Local `main` is moved to the release commit by a fast-forward fetch into the
ref, never a checkout, and never a rewind; a refusal dies with nothing pushed
and a `just resume-release` hint. In release mode, after `release_preflight` and
before any commit or tag, `branch_preflight` fetches with `--no-tags` and
refuses unless local `main` and `origin/main` are both ancestors of `HEAD`, each
refusal naming the merge that clears it. `--no-tags` because the fetch reads one
thing, origin's `main`: a tag arriving after the version was chosen would
otherwise meet the bump only once the release commit exists, and a plain fetch
also restores a lost tag before the lost-tag guard can read it. An origin with
no such branch has nothing to compare, and the run says so and continues.

From `dev`, `branch_preflight` also runs the fetch `move_main` will run, as a
no-op, before any commit or tag: git 2.35 and later refuse to move a branch
another worktree holds, and found after the commit and tag exist that refusal
leaves the release half-landed. An older git does not refuse, so neither the
probe nor `move_main` stops the move. The probe is git's own fetch rather than a
read of `git worktree list` because git's rule is wider than a checkout: it also
refuses a `main` held by a worktree mid-rebase, and a parse would pass that. The
refusal leaves git's `fatal:` line visible, since it names the worktree, and
says to free `main` in that worktree, with `git worktree list` to see its state,
then run the same command again; no tag exists yet, so `just resume-release` is
not the way out. A resume is unchanged: by then the move is the step that
failed, and `move_main`'s hint already says to clear what git reported, which
names the worktree. From `main` itself the probe is skipped, since nothing
moves. Commits made on `main` after a failed push do not need a refusal:
`move_main` has already brought `main` to the release commit by then, and the
remaining ways to get there are rare.

A consumer's `main` may have other writers, which is why the checks differ from
the self-release's. A resume runs no ancestry check on `main` or `origin/main`:
those guards refuse before a commit and tag are cut, and a release already on
origin's `main` has nothing left they protect. A resume refuses only a tag whose
commit `HEAD` does not contain, because it publishes that commit. Origin's
`main` moving past a release before the push is a refusal that prints the undo,
not a merge to resume through: merging the other writer's work after the tag was
cut would publish a combination the gate never saw, so the release is redone on
top of it
([recovery.md](recovery.md)).

`symbolic-ref` rather than `rev-parse --abbrev-ref` because the latter exits
non-zero *and* prints `"origin/HEAD"` to stdout when the ref is unset. Combined
with `pipefail` and a `|| echo "main"` fallback, the substitution captured both,
producing a two-line `main_branch` and the nonsensical error "must be on HEAD
(currently main)". `symbolic-ref` is silent on stdout when the ref is unset, so
the fallback fires cleanly. Both flows read it this way.

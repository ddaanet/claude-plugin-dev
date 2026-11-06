# This repo's own release

The toolkit releases itself with `scripts/self-release.sh`, not with the
`release.sh` it ships to consumers. What the two deliberately do not share, what
the self-release borrows anyway, and the one guard a consumer has no need for.
The conclusions these arguments support are listed in
[../design.md](../design.md).

## A separate script, not a consumer of its own toolkit

`release.sh` releases a *plugin*. It bumps `.claude-plugin/plugin.json`, it
bumps a marketplace entry, and it is shaped throughout by a consumer layout this
repo does not have and is not going to grow: there is no `plugin.json` here, on
purpose. The toolkit's own release bumps `toolkit/VERSION`, publishes no
marketplace entry, and cuts two tags rather than one — the source `vX.Y.Z` and
the `dist-vX.Y.Z` split ref consumers actually vendor (see
[distribution.md](distribution.md)).

Folding the one into the other would make the toolkit consume its own
consumer-shaped code, which the "don't run `release.just`'s recipes from this
repo" rule exists to prevent. The cost is a second script covering the same
ground, paid for by the `tests/self-release-*-test.sh` suites driving it end to
end against real repos with local bare origins and a `gh` stub — the same
fixture shape the `tests/release-*-test.sh` suites use for the consumer flow.

## The clean-tree exclusion is a literal pathspec here

`scripts/self-release.sh` carries `common_preflight`'s one exclusion — `memory`
— as a literal pathspec, rather than repeating `release.sh`'s `.gitmodules`
lookup (see "The clean-tree check exempts only the memory gitlink" in
[clean-tree.md](clean-tree.md) for why it is exempt, and why `.claude/` is not).
It runs against exactly one repo, whose mount path is known, so discovery would
be answering a question that has no second answer. That is the same reasoning
that keeps it separate from `release.sh` at all: it is not consumer-shaped code
and does not have to generalise.

## The shape it shares, and the one guard it adds

What it does share is the shape. The self-release began as an unguarded tail
inlined in the root `justfile` — push, push tags, `gh release create` — and the
failure `resume-release` exists to absorb hit it twice: `v0.4.1` has a `VERSION`
bump commit and no tag, and cutting `0.8.0` left the commit and both tags local
with the push refused.

Running the remaining lines by hand was the smaller problem. The larger one is
what a re-run would have done instead. With the local half landed,
`toolkit/VERSION` holds the new version and the newest tag names it, so the
drift check passes — `VERSION` *is* the latest tag — and so does the
tag-collision check, which asks about the *next* version. A
`just release <bump>` would have published the version after the one that failed
and left the stranded one tagged in two places with no GitHub release, refused
by nothing. The guard set was complete against every state except the one the
flow actually produces when it breaks.

So the script mirrors the consumer flow: an idempotent tail that both
`just release` and `just resume-release` run, each step probing origin before
acting, and `resume-release` depending on no gate for the reason `release.just`
already gives consumers — a prerelease that passed must not have to run again to
finish the release it gated. Plus the guard that closes the hole above: a bump
is refused while the version currently in `toolkit/VERSION` is tagged locally
but missing either tag on origin or its GitHub release, and the refusal names
what is missing. A probe that cannot read origin is not an absence: each
`ls-remote` is captured into a variable and a failure ends the run as itself, so
the missing-list hint never names a tag that was only unreachable.

No guard ties the bump to the migration notes. A note's file name is its
release's version, so a note written ahead of its release,
`migrations/vX.Y.Z.md` while `toolkit/VERSION` is still below it, needs the bump
that reaches that version; a smaller one publishes the change while
`update.sh`'s crossed range stops short of the note. The bump is chosen by hand
at release time, and a refusal is added if a release ever lands below a waiting
note, not before: no release has produced that state, and every refusal is one
more check each release has to pass.

The consumer script has no equivalent guard because it does not need one:
`release_preflight` reads the version from `plugin.json`, and a half-landed
consumer release is caught by `check-version.sh` comparing the manifest against
the marketplace entry. The toolkit publishes no marketplace entry, so
`toolkit/VERSION` is the only witness, and it is one a failed push leaves
looking correct.

The two tags are the other difference. `resume-release` re-cuts `dist-vX.Y.Z`
from the `vX.Y.Z` tag rather than from `HEAD`, since by resume time `HEAD` has
often moved past the release commit and the dist ref must carry the tagged
`toolkit/` tree. And when origin already holds the dist tag but this clone does
not, it leaves it alone rather than re-splitting: the split is deterministic in
practice, but "in practice" is not a basis for pushing a recomputed ref over a
published one, and `push_tag`'s mismatch refusal is the only thing standing
between a differing split and a moved tag.

## It releases from `main` or `dev` and publishes the tag's commit

Work lands on `dev`; a release is a review of `dev` against `main`, after which
`main` moves to the release. The script runs from either branch, so the release
does not start with a checkout of `main` that the session would then have to
undo. Any other branch, and a detached `HEAD`, are refused with both allowed
names in the message: a half-finished plan branch would otherwise be released
and pushed to `main` under a version tag. `dev` is a literal, like the `memory`
pathspec, because this is the one repo the script runs against. The default
branch is still read from `origin/HEAD`.

**Refused before anything is written.** `common_preflight` fetches origin and
dies if the fetch fails, then refuses unless local `main` and `origin/main` are
both ancestors of `HEAD`. With either holding a commit `HEAD` lacks, the
fast-forward of `main` or the push would refuse only after the commit and tags
were cut, which is the stranded state `resume-release` exists to absorb;
refusing first costs nothing to undo. This applies on `main` too: a `main` that
trails `origin/main` is refused up front. The fetch is a plain one, which also
brings back a release tag on origin's history, so a resume from a clone missing
the tag finds it and finishes.

A resume publishes only a tag whose commit is on `HEAD`'s history, however the
tag arrived, and refuses any other before writing anything. A tag off that
history names a commit the branch does not carry: fast-forwarding `main` to it
would publish that commit and leave `main` off the branch the next release is
cut from, and a resume cannot take published tags back. The refusal's hint
re-tags the commit and drops the dist tag too, because `ensure_dist_tag` would
otherwise keep the tree split from the old commit.

**`main` moves without a checkout.** After the tags, `main` is fast-forwarded to
the tag's commit with `git fetch . <sha>:refs/heads/main`, before any push.
Another worktree holding `main` makes git refuse, and the run stops with nothing
published and the same `just resume-release` hint as a failed push. Switching to
`main`, fast-forwarding and switching back was weighed and rejected: it moves
the checkout the session stands in, and a failure between the two switches
leaves it on the wrong branch. Pushing alone and leaving local `main` behind was
rejected too, since a stale local `main` is still an ancestor of `HEAD` and no
check would flag it. A `main` that already contains the tag's commit is left
alone, never rewound.

**The push publishes the tag's commit, not `HEAD`.** On `dev`, `HEAD` carries
work that is not being released, and a bare `git push` would publish it or
nothing at all, depending on configuration. The script pushes
`<sha>:refs/heads/main`, the same from either branch, and `dev` is never pushed
by it. On a resume, `HEAD` is often past the release commit, so the tag names
the commit and the push-probe asks whether that commit is an ancestor of
origin's `main`. Comparing origin's `main` to `HEAD` instead would republish, or
refuse, over commits the release never covered; the ancestor test makes a resume
after later commits publish none of them. The cost is that those commits reach
origin by an ordinary push, outside the script. gitlore's pre-push hook ignores
the refspec and pushes each memory store's `live`, so memory publishes as it
does from `main`.

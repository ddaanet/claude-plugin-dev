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
ground, paid for by `tests/self-release-test.sh` driving it end to end against
real repos with local bare origins and a `gh` stub — the same fixture shape
`tests/release-test.sh` uses for the consumer flow.

## The clean-tree exclusions are literal pathspecs here

`scripts/self-release.sh` carries both of `common_preflight`'s exclusions —
`.claude` and `memory` — as literal pathspecs, rather than repeating
`release.sh`'s `.gitmodules` lookup (see "The clean-tree check excludes the
agent's own working state" in [recovery.md](recovery.md) for why either is
exempt at all). It runs against exactly one repo, whose mount path is known, so
discovery would be answering a question that has no second answer. That is the
same reasoning that keeps it separate from `release.sh` at all: it is not
consumer-shaped code and does not have to generalise.

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

So the script now mirrors the consumer flow: an idempotent tail that both
`just release` and `just resume-release` run, each step probing origin before
acting, and `resume-release` depending on no gate for the reason `release.just`
already gives consumers — a prerelease that passed must not have to run again to
finish the release it gated. Plus the guard that closes the hole above: a bump
is refused while the version currently in `toolkit/VERSION` is tagged locally
but missing either tag on origin or its GitHub release, and the refusal names
what is missing.

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

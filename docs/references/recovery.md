# Recovery and the pre-flight state checks

What happens when a release lands only partially, and which working-tree state a
pre-flight is right to refuse. The conclusions these arguments support are
listed in [../design.md](../design.md).

## `check-version.sh`: catching a partially-completed release

`release`'s marketplace step (see "Marketplace entry" in
[release-flow.md](release-flow.md)) runs *after* `plugin.json` is bumped,
committed, tagged, pushed, and the GitHub release created. If anything from
`gh release create` onward fails, the plugin is left tagged and pushed at the
new version while `marketplace.json` is still at the old one — invisible to end
users, and nothing in the toolkit previously detected it: the pre-flight in
`release` only compares `plugin.json` against the latest tag, and the
version-guard hook only fires on edits to `plugin.json`, not on marketplace
staleness.

`check-version.sh` closes this by comparing `plugin.json`'s `.version` against
the consumer's entry in `$MARKETPLACE_DIR/.claude-plugin/marketplace.json`. It's
exposed as a `just check-version` recipe and also runs automatically as a
`release` pre-flight step, so a new release refuses to start on top of a drifted
marketplace from a previous incomplete one.

It was originally a gitlore-local script (it motivated the `prerelease` gate in
[release-flow.md](release-flow.md)), hardcoded to gitlore's plugin name and a
`../claude-plugins` sibling path. Absorbed into the toolkit with two fixes: the
plugin name is read from `plugin.json` instead of hardcoded, and the marketplace
path comes from `$MARKETPLACE_DIR` (matching `release.just`'s own convention)
instead of an assumed sibling directory. A missing marketplace entry is treated
as pre-first-publication state (skip), not drift (fail) — consistent with how
`release.just`'s marketplace step treats a missing entry.

An entry that *disagrees* with the manifest is still drift, and on an initial
release that needed its own hint. The ordinary advice for drift is
`just resume-release`, which then finds no tag and points back at
`just release`, which refuses on drift again: a loop whose only exit is a hand
edit. `release_preflight` reaches that point knowing more than
`check-version.sh` does — the lost-tags probe has already established that no
semver tag exists here or on origin — so the plugin is verifiably unpublished
and there is no partial release to resume.

The refusal is kept rather than relaxed. The alternative was to skip
`check-version.sh` when no semver tag exists anywhere and let `bump_marketplace`
overwrite the entry. An entry naming a version that was never released is an
anomaly with several readings — a plugin published under another name, an entry
belonging to a different plugin, a manifest meant to hold that version — and
overwriting picks one silently and hides the rest. Surfacing it costs one hand
edit on a path that runs at most once in a plugin's life.

So the hint names both versions, says no release is recorded at either, and
points at the marketplace entry as the one to correct — a successful first
release would write the manifest version there anyway — while naming the
manifest edit instead for the case where the entry's version was the intended
one. Resume is not offered. It also says "no vX.Y.Z tag, here or on origin"
rather than "never published": what the probe established is the absence of a
tag of that shape, and a plugin released only under some other scheme is a
residual the message must not deny.

## Recovery: `resume-release` and the shared release tail

`check-version.sh` detects a half-landed release but cannot fix one, and the
guard it feeds is deliberately strict: `release` refuses to start on top of
drift. Before `resume-release` nothing satisfied that guard except hand-editing
another repository. `resume-release` is the forward exit.

The last steps of a release — push the branch, push the tag, push the dist
branch and its tag when the plugin has opted in, create the GitHub release, bump
the marketplace — are one idempotent block that both `release` and
`resume-release` run. Each step probes remote state before acting:
`git ls-remote` for the branch and tag, `gh release view` for the release, and
`ls-remote` again — against the marketplace repo's own origin — for the
marketplace push. Probing the remote directly means the answer is authoritative
without a `git fetch`, so recovery never depends on how stale the local
remote-tracking refs are. A step that finds its work already done says so and
returns; only steps that act set `acted`.

`push_dist` sits between the tag push and the GitHub release, so the marketplace
never names a `ref` that is not on origin. It probes `dist` and `dist-v$V` on
origin before it acts, and tells a landed branch by the tip's subject,
`dist v$V from <the tag's commit>`; the commit is rebuilt reproducibly, so a
resume compares instead of guessing ([dist-branch.md](dist-branch.md)). The tag
probe, local and origin, runs before the branch push, so a `dist-v$V` at another
sha leaves nothing pushed. A rejected branch push dies naming
`just resume-release` and is never forced. Resume reads the opt-in from the
tag's commit, not the worktree, and validates the tree again before the first
push of `dist`.

Resume takes its version from `plugin.json` and requires the matching local tag
to already exist. It completes a release; it never starts one. Tagging `HEAD` on
a guess would tag whatever landed since the interrupted release, so a missing
tag is a refusal. When every step finds nothing to do, the summary says the
release is already complete rather than claiming to have completed it — that
distinction is what makes running it on a healthy repo safe rather than merely
harmless.

Which advice that refusal carries is picked from one `origin_release_tags`
listing, because a missing local tag says nothing about what is published. Four
cases:

- **Origin has `v$V`.** The release landed and this clone never fetched it.
  `git fetch --tags`, then `just resume-release`: the tag arrives and resume
  finishes whatever is left.
- **Origin has some other semver tag.** Something is published, but not this
  version. `git fetch --tags`, then `just release <bump>` — once the fetch lands
  there is a real release to bump from, and a bare `just release` would be
  refused on sight as a first release that this is not.
- **Origin has nothing, and this clone verifiably has no semver tag either.**
  Nothing to bump forward from, so the next command names no bump:
  `just release`.
- **Anything else** — origin silent while this clone's own tags are either
  present but non-matching or unreadable. `just release <bump>`: the branch that
  asserts least, and whose advice is safe either way, since `release_preflight`
  refuses a bump on a plugin that turns out never to have been released and says
  why.

Here the probe only improves the advice and is never allowed to harden the
refusal, which was already decided before any listing ran. So a failed listing
falls into the branch claiming least rather than becoming a second, different
error — and only a listing that *succeeded* and came back empty sets the
no-local-tags flag, since folding a failure into the empty case would let
silence claim "never released" and route to a bare `just release`.

A failure *of* the version commit is the one case recovery does not own. A
consumer's `pre-commit` hook can refuse it — gitlore's memory-approval gate is
on every consumer — and at that point nothing is committed or tagged, so there
is no partial release to resume. The manifest rewrite is already staged though,
and left in place it is a dirty tree that `common_preflight` refuses, blocking
`release` and `resume-release` alike on `uncommitted changes` with no mention of
the gate or the leftover. So the commit is guarded and the manifest restored
from HEAD, returning the tree to what the run found: a refused commit means
satisfy the gate and run the same command again, and recovery is not involved.
Only the commit is guarded — a `pre-commit` hook cannot fail `git tag`.

The marketplace commit is guarded the same way, and there the argument is one
step stronger. It is the last step of a release and its only write outside the
plugin repo, so a refusal leaves the version commit, tag, branch push and GitHub
release already public: the release genuinely is partial and `resume-release` is
what finishes it. A bump left staged in `MARKETPLACE_DIR` is precisely what
`common_preflight` reads as an unrelated dirty tree, so the leftover blocks the
one command that would help. The refusal used to print the
`git -C … checkout HEAD -- .claude-plugin/marketplace.json` to run first, which
made the recovery two commands and the first of them mandatory — the same
argument that made the manifest rollback automatic. It is automatic here too:
the tree is restored to the state `common_preflight` had already established was
clean, and the whole printed recovery is `just resume-release`.

A push refused by a consumer's `pre-push` hook is resume's ordinary case, and
the release commit is never amended to chase it. gitlore's hook publishes every
memory store before the parent push and refuses when one diverged, so the
release dies with the commit and tag local and nothing pushed. The tempting
repair — `commit --amend` the release commit so its gitlink names the merged
memory, then `tag -f` — buys nothing. The gitlink a parent commit records is
always an ancestor of memory's `live` or `live` itself, because each merge takes
the pending commit as its second parent, and a push of `live` publishes every
ancestor. So the moment the push succeeds the gitlink is public, whether or not
the tagged commit names the merge. Against that, the amend would force a tag the
script is about to publish and sequence a scripted rewrite behind a human merge
review. `push_branch` re-pushes the release commit to origin's default branch on
resume instead, and says so when it fails: clear what the hook reported, run
`just resume-release`, repeat if refused again.

A tag that exists on the remote at a *different* sha is an error, never a
force-push. A reused tag means something published under that version already,
and no recovery path should paper over that.

`resume-release` has no `prerelease` dependency, unlike `release`. The code it
completes is already committed, tagged, and in most cases pushed — the gate
already passed once, before the interruption. Re-running it would make recovery
cost whatever the consumer's slowest gate costs, and a consumer with paid checks
would route around the recipe and finish by hand, which is the situation this
exists to end.

The flow moved out of `release.just`'s recipe body into `plugin-dev/release.sh`
to get three things a justfile recipe cannot have: `shellcheck` coverage,
offline end-to-end tests driving real git repos with a stubbed `gh`, and no
just/bash quoting seam — `{{...}}` interpolation inside a shell body is a
recurring source of quoting bugs that no linter sees. `release.just` keeps the
two recipes as one-line wrappers, which is also the whole interface consumers
depend on.

This repo's own release borrows the same tail without sharing the code — it is
not consumer-shaped, and folding the two together would make the toolkit consume
its own consumer-shaped code. That argument, and the one guard the self-release
carries that no consumer needs, are in [self-release.md](self-release.md). A
local dist tag split from a `toolkit/` tree the release tag no longer has is
refused before any push, with the exact command that clears it.

## The refusal is where the operational knowledge lives

What to do when a release dies is knowledge that has to arrive at the moment it
dies. Two places could have held it and neither reaches the reader in time. A
ddaanet memory file is readable only from a machine that mounts the tier, and
only when an index line matches the string the failure happened to print — while
the consumer hitting the failure is often a plugin repo with no memory store at
all. A `docs/` page is worse: nothing routes a reader to a document mid-failure,
and the `dist-` tree ships no `docs/`. The script is in every consumer by
construction, so the message is the one channel that cannot be missed, and the
one that cannot drift from the check it guards.

So every refusal on a path where the tree state is non-obvious, or where a
release may already be partly public, states three things: what was checked,
what was exempt from it, and the exact next command. The clean-tree checks print
the offending paths and the exemptions that did not save them; the marketplace
checks say what is already published before naming `just resume-release`; the
first-release and version-drift refusals state the invariant they protect and
give the command that satisfies it; the lost-tags refusal names the newest tag
origin holds and asks for `git fetch --tags`; the diverged-push-route refusal
names the config key, prints its values one per line, and gives the
`git config --unset-all` that clears it.

### Why the lost-tags probe runs before the drift check

An empty *local* tag list is not evidence that a plugin was never released: a
clone can lose a tag it once had, or never have fetched it, while origin still
carries the actual release record. So `release_preflight` probes
`origin_release_tags` whenever the local list is empty, and it does so before
`check-version.sh` and therefore before `bump_commit_tag` tags or `push_branch`
pushes.

The ordering is the point. Reached after the drift check, the probe would be
commenting on a repository that had already been given advice — and
`check-version.sh`'s drift advice is actively wrong on a lost-tags clone, since
following it commits the marketplace's older version over a release that is
genuinely public. Firing first is what lets that state get the fetch hint
instead. A listing that could not be performed refuses outright here, unlike in
`resume_preflight`: there is a side effect left to protect, and `push_branch`
and `push_tag` need origin anyway, so continuing would only move the failure
past the last point a check could still have caught it.

The probe keys on a local list that is *entirely* empty, and partial tag loss is
a stated bound rather than a case it covers. A clone that kept older release
tags but lost the newest never reaches it: `release_tag_list` comes back
non-empty, so `latest_tag` is read from a stale local newest and the drift check
compares the manifest against that. A manifest holding the genuinely current
version then refuses with advice to set it *back* to the stale tag and commit
that edit — the same shape of wrong advice the probe exists to spare a fully
tagless clone, and the one state in which that refusal's own reasoning, that a
fetch can never have anything left to fetch, does not hold. Where the manifest
matches the stale tag instead, only the marketplace check stands between the run
and a bump computed from it, and it reads the state as a partial release rather
than as a lost tag.

Closing it means listing origin on every release instead of only on an empty
local list: a network round trip on the common path where the local tags are
complete, and a listing whose failure could not refuse the way the empty-list
probe's does — that would put every release behind a working network — so its
status would have to be absorbed instead. The bound is accepted on those terms,
as the `pushInsteadOf` route below is.

### The push route has to agree with the probe

`git ls-remote origin` reads origin's *fetch* URL, while `remote.origin.pushurl`
redirects every `git push origin ...` the release runs (`push_branch`,
`push_tag`, `push_dist`) to a repository the origin probes never inspect, so the
published-tag check would read somewhere the release does not publish to.
`common_preflight` refuses when it is set, before any side effect, on `release`
and `--resume` alike.

`branch.<name>.pushRemote` and `remote.pushDefault` are not checked. Each
selects the remote for an unqualified `git push`, and the release runs none:
every push, the marketplace bump's included, names origin and a refspec, which
ignores both (measured).

Refusing when a key is *set*, rather than when it "diverges" from origin:
deciding whether two URLs name the same repository (`git@host:o/p.git`,
`https://host/o/p`, `ssh://host/o/p`, an `insteadOf` rewrite — all one
repository) is not decidable in shell without a network round trip on the common
path. The recovery, unset it or point it at origin, covers a same-repo `pushurl`
on a different protocol too.

`--get-all` and not `--get`, because `pushurl` is genuinely multi-valued
(pushing to several mirrors is a supported arrangement) and `--get` prints only
the *last* value and still exits 0 (measured, git 2.47.3). The refusal would
then name one of two URLs and advise a `--unset` that refuses a multi-valued key
with status 5: a correct refusal handing back a recovery that does not work.

A further route, `url.<base>.pushInsteadOf`, is a stated bound rather than an
oversight. Measured: with it set and no `pushurl`, `git push origin main` lands
in the rewritten repository while `git ls-remote origin` still reads the
original — precisely the split this check exists to prevent. What does not carry
over is "refuse when set". The rewrite fires only when its base is a prefix of
origin's URL, and a base that does not match is inert (measured), so refusing on
presence would reject the global `insteadOf`/`pushInsteadOf` rewrites that are
ordinary in corporate setups — where the repo-scoped `pushurl` is anomalous by
its very presence, which is what makes refusing on presence honest for them.
Deciding whether a given base matches is the same URL-identity problem this
section already declines to solve. Plain `url.<base>.insteadOf` needs no check
at all: it rewrites fetch and push alike, so the probe reads the repository the
release publishes to.

Two constraints shape the wording. No message offers a way to skip a check — the
same rule the version-guard hook's deny message follows, for the same reason: an
agent reads a named bypass as authorisation to take it. And the exemptions a
message lists are built in the same place as the pathspecs it reports on
(`clean_pathspecs` returns both), so a consumer whose vendored `plugin-dev/`
predates one of the exclusions is never told about an exclusion its own copy
does not make. Its `tree_is_clean` is the authority on what it exempts, and the
message is generated from it rather than written alongside it.

Paths printed from a diff are read NUL-delimited: a spaced path reported as two
words names two files that do not exist. A path containing a newline still
prints across two lines, which no git quoting mode survives `-z` to fix, and the
comment states that bound rather than implying full coverage.

A release that origin's default branch has moved past, and a resume whose tag is
off `HEAD`'s history, are in [failed-release.md](failed-release.md).

## The clean-tree check exempts only the memory gitlink

`common_preflight` exempts only the gitlore memory submodule from its dirty-tree
refusal; `.claude/` is not exempt. The argument is in
[clean-tree.md](clean-tree.md).

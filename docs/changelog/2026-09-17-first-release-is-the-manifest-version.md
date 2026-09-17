# 2026-09-17 — The first release is the manifest version, detected by tag alone

Found while cutting `plugin-craft` v0.1.0 against vendored toolkit 0.7.1. The
release itself ran cleanly in one go; the problem was getting the intended
version into the manifest at all.

## The gap

`release_preflight` already published the manifest version verbatim on a first
release and refused a bump argument there, and `bump_commit_tag` tagged `HEAD`
with no commit, on the stated assumption that the manifest already held the
intended version. So the version has to be in `plugin.json` before the recipe
runs. Three things then collided.

`version-guard.sh` denied every `Write|Edit` that changed `.version`, with a
message saying the manifest "is the last released version", that it "is changed
only by `just release {patch|minor|major}`", and closing "Do not bypass this
guard, modify the recipe, or alter version state by other means." Correct in the
steady state and unsatisfiable on a first release: no recipe invocation selects
a version there — `just release` publishes whatever is already in the manifest,
and `just release minor` is refused on sight. `tree_is_clean` does not exempt
`.claude-plugin/` either, so the edit has to be committed by hand first, which
is again the "other means" the message forbids.

An agent that follows that message literally either publishes whatever the
scaffold seeded or stalls with nothing it is permitted to do. In the case that
surfaced it the manifest was hand-seeded `0.0.0`, so the literal path would have
published `v0.0.0`.

## Detection is by tag alone — the overturned decision

A plugin is at its first release exactly when no tag matching
`^v[0-9]+\.[0-9]+\.[0-9]+$` exists, locally or on origin. Its marketplace entry
plays no part.

Detection used to require **both** no `v*` tags and no marketplace entry, on the
argument that a repo whose tags were lost or never fetched still has its entry,
so republishing over it would collide with a version already out there. The
danger is real; the conjunct was the wrong instrument. It only ever protected a
lost-tags repo that *had* an entry — which is to say it covered plugins already
in the marketplace and left a first-time publisher's lost-tags clone unguarded.
That state is reachable, because `check-version.sh` treats a missing entry as
ordinary pre-first-publication and skips: a plugin can carry real release tags
and no entry at all.

So `release_preflight` probes `origin_release_tags` whenever the local list is
empty, before `check-version.sh` and so before anything tags or pushes. Any
semver tag on origin refuses and names the newest, hinting `git fetch --tags`;
any tag and not only `v$V`, since a tagless clone whose manifest was
hand-advanced past a real release would otherwise find no tag of its own name
and publish the hand-written version. A listing that could not be performed
refuses too — only origin's silence may say "never released" and continue. That
is strictly stronger than the conjunct, so the conjunct is gone, and with it the
requirement that `marketplace.json` be hand-edited before a plugin's first
release could be recognised as one.

Both listings gained `--sort=-v:refname` and a shared `semver_tags` filter.
`ls-remote`'s default order is lexicographic on the refname, where `v1.10.0`
precedes `v1.2.3` precedes `v1.9.0`, so the newest-first contract every caller
reads them under is not free. The filter is what keeps `vnext` and `v1.2` out of
`latest_tag`: both are `v*` tags and neither is a release.

## The probe is only as good as the push route

`ls-remote origin` reads origin's *fetch* URL, while `remote.origin.pushurl`,
`branch.<name>.pushRemote` and `remote.pushDefault` each redirect a push
elsewhere — and not to the same place, since `push_branch`'s unqualified
`git push` follows all three in that precedence while `push_tag`'s
`git push origin "$tag"` is redirected only by `pushurl`. Under any of them the
probe reads a repository the release does not publish to.

`common_preflight` now refuses when any of the three is set, before any side
effect, on `release` and `--resume` alike, naming the key and printing its
values one per line. Refused when *set* rather than when it "diverges": deciding
whether two URLs name the same repository is not decidable in shell without a
network round trip on the common path.

## The rest

`resume_preflight`'s no-tag refusal picks its hint from one origin listing —
fetch-then-resume, fetch-then-release, bare release, or release-with-bump —
where a failed listing costs only advice, never a harder refusal. And an initial
release whose marketplace entry disagrees with the manifest is still refused,
with a hint naming both versions, saying no release is recorded at either, and
pointing at the entry as the one to correct; resume is not offered, because
there is nothing to resume.

## What was rejected

Three mechanisms, the first two of them the brief's (its third — branching the
denial message — is what shipped). **Teaching the guard to allow the edit** is
the only one that lets an agent write the version unaided, which is the reason
it goes. **A `--initial 0.1.0` selector** keeps the guard's invariant literally
true but adds an argument valid once in a plugin's life, and does not even
remove the manual edit — a plugin content with its scaffolded version still
releases without it. **Seeding a baseline `v0.0.0` tag** writes a release that
did not happen into the namespace both listings treat as the release record, and
`just release` then bumps from it to `v0.0.1`: the same version-nobody-asked-for
outcome, moved one step.

Also rejected: skipping `check-version.sh` when no semver tag exists anywhere
and letting `bump_marketplace` overwrite a disagreeing entry. And, for the
failed-listing case in the hook, the initial-release wording or a third wording
true in both states — the restrictive one is the right answer to "don't know",
and it is what the hook already did.

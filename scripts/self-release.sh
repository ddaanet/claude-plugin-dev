#!/usr/bin/env bash
# claude-plugin-dev's OWN release, not a consumer's. Run from the repo root,
# through `just release` / `just resume-release`.
#
#   self-release.sh [patch|minor|major]   cut a toolkit release
#   self-release.sh --resume              finish one that landed partially
#
# Shares no code with toolkit/release.sh, and should not: that one releases a
# plugin (a plugin.json version, a marketplace entry, one tag), this one
# releases the toolkit (toolkit/VERSION, no marketplace, two tags -- vX.Y.Z
# and the dist-vX.Y.Z split consumers vendor). Factoring the overlap together
# would put every consumer's release path behind a branch only this repo takes.
#
# What it does share is the shape: every step past the local commit is probed
# before it is taken, so a run that died mid-flight can be finished by
# re-running with --resume rather than by hand. Finishing 0.8.0 by hand is what
# motivated this script; before it, the recipe's tail was four unguarded lines
# and a re-run silently published the NEXT version.
set -euo pipefail

die() { printf 'error: %s\n' "$1" >&2; exit 1; }
note() { printf '%s\n' "$1"; }

usage="usage: self-release.sh [patch|minor|major|--resume]"
mode="release"
bump="patch"
case "${1-}" in
    "")                ;;
    --resume)          mode="resume" ;;
    patch|minor|major) bump="$1" ;;
    -*)                die "unknown option: $1 ($usage)" ;;
    *)                 die "unknown bump type: $1 ($usage)" ;;
esac
[ "$#" -le 1 ] || die "too many arguments ($usage)"

ls_remote_sha() {
    # $1 = a full ref name. Prints its sha on origin, empty if absent there.
    # Captured whole and trimmed with a parameter expansion rather than piped
    # through `cut`: a pipeline reports cut's status, so a failed ls-remote
    # would read as "the ref is not on origin" -- and every caller below treats
    # absence as licence to act. `set -o pipefail` would cover it, but only for
    # as long as nobody removes it; this does not depend on that.
    local line
    line=$(git ls-remote origin "$1") || die "git ls-remote origin $1 failed"
    printf '%s' "${line%%$'\t'*}"
}

# The preflights live beside this file, found from its own location so the
# script runs from any CWD. The directive is for shellcheck -x, which cannot
# resolve the computed path.
# shellcheck source=scripts/self-release-preflight.sh
. "$(dirname "${BASH_SOURCE[0]}")/self-release-preflight.sh"

bump_commit_tag() {
    printf '%s\n' "$V" > toolkit/VERSION
    git add toolkit/VERSION
    # This repo's own pre-commit hook runs `just precommit`, and gitlore's gates
    # the memory submodule -- either can refuse. Dying with the bump written and
    # staged strands it, where common_preflight's "uncommitted changes" then
    # blocks both a re-run and --resume while naming neither the gate nor the
    # leftover. Restoring from HEAD leaves the tree as this run found it, so
    # satisfying the gate and re-running is the whole recovery.
    git commit -qm "release: $V" || {
        git checkout HEAD -- toolkit/VERSION
        printf 'hint: toolkit/VERSION was rolled back and nothing was tagged.\n' >&2
        printf '      fix what the gate reported above, then run the same command again.\n' >&2
        die "commit gate refused the release commit"
    }
    git tag -a "$tag" -m "Release $V"
    acted=1
    note "VERSION + tag: $tag created locally"
}

ensure_dist_tag() {
    local dist_sha remote_dist
    # Consumers vendor $dist_tag, never $tag. `git subtree pull` copies a ref's
    # ROOT tree, and this repo's root is its own working environment -- the
    # memory gitlink, .claude/, CLAUDE.md, the justfile, docs, tests. Splitting
    # toolkit/ yields a ref whose root is exactly what ships.
    if git rev-parse -q --verify "refs/tags/$dist_tag" >/dev/null; then
        # A local dist tag is kept only if it carries the tag's own toolkit/
        # tree. After an amend of the release commit it carries the tree the
        # tag no longer has, and push_tag would publish it: a published dist
        # tag is never moved, so the stale tree would be what consumers vendor
        # for good. The tag's tree, never HEAD's: a resume's HEAD may be past
        # the release with toolkit/ changed since. A dist tag already on origin
        # in this state is unreachable (main is pushed first, and
        # common_preflight refuses once origin's main holds commits HEAD lacks),
        # so it gets no hint of its own.
        if [ "$(git rev-parse "$dist_tag^{tree}")" != "$(git rev-parse "$tag:toolkit")" ]; then
            printf 'hint: %s was split from a toolkit/ tree %s no longer has, as after an amend of the release commit.\n' "$dist_tag" "$tag" >&2
            printf '      nothing was pushed. Delete it, then the next run splits it again:\n' >&2
            printf '        git tag -d %s\n' "$dist_tag" >&2
            # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
            printf '      then run `just resume-release`.\n' >&2
            die "local $dist_tag does not match the toolkit/ tree of $tag"
        fi
        note "dist tag $dist_tag: already created locally"
        return
    fi
    # Captured into a variable rather than tested inline: a `[ -n "$(…)" ]` only
    # ends the substitution's subshell when ls_remote_sha dies, so an unreadable
    # origin would fall through to the split below and leave a local dist tag
    # that push_tag then refuses to move for the rest of time. Assigning lets
    # the failure reach `set -e` instead.
    remote_dist=$(ls_remote_sha "refs/tags/$dist_tag")
    if [ -n "$remote_dist" ]; then
        # Published, and missing only here. Re-splitting would probably
        # reproduce it, but tagging that result locally and pushing it is not
        # something to do on "probably": push_tag's mismatch refusal is the only
        # thing between a differing split and a moved published tag.
        note "dist tag $dist_tag: already on origin (not in this clone)"
        return
    fi
    # Split $tag, not HEAD: on a resume HEAD has usually moved past the release
    # commit, and the dist ref has to carry the tagged toolkit/ tree.
    dist_sha=$(git subtree split -q --prefix=toolkit "$tag") \
        || die "git subtree split of $tag failed"
    git tag -a "$dist_tag" -m "Dist $V" "$dist_sha"
    acted=1
    note "dist tag $dist_tag: created locally"
}

move_main() {
    # Runs before any push: a refusal here (another worktree holds main) leaves
    # nothing published. Never rewinds main -- a main already past the tag's
    # commit stays where it is, and the skip below covers it.
    if git merge-base --is-ancestor "$release_commit" "refs/heads/$main_branch"; then
        note "branch $main_branch: already contains $tag"
        return
    fi
    git fetch -q . "$release_commit:refs/heads/$main_branch" || {
        printf 'hint: %s was not moved to %s; nothing was pushed.\n' "$main_branch" "$tag" >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      clear what git reported above (another worktree may hold %s), then run `just resume-release`.\n' "$main_branch" >&2
        die "could not move $main_branch to $tag"
    }
    acted=1
    note "branch $main_branch: moved to $tag"
}

push_branch() {
    # The fetch in common_preflight has just refreshed origin's main, so this
    # reads its current position. A release commit already under it is
    # published, whatever later commits came after.
    if git merge-base --is-ancestor "$release_commit" "refs/remotes/origin/$main_branch"; then
        note "branch $main_branch: already pushed"
        return
    fi
    # gitlore's pre-push hook publishes every memory store before the parent
    # push and refuses when one diverged. The commit and the tags are already
    # local by now, so the recovery is resume -- never an amend, which would
    # re-pin the gitlink and rewrite a commit the tag names.
    # Pushes the tag's commit, not HEAD: from dev, HEAD carries work that is not
    # being released. The refspec does not name the branch checked out, so the
    # push is the same from main and from dev.
    git push origin "$release_commit:refs/heads/$main_branch" || {
        printf 'hint: the release commit and tag %s are local; nothing was pushed.\n' "$tag" >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      clear what the push reported above, then run `just resume-release`.\n' >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      gitlore refuses the push while a memory store is diverged: `/gitlore:resolve`\n' >&2
        printf '      in Claude Code clears it. Repeat the pair if the push is refused again.\n' >&2
        die "push of $main_branch failed"
    }
    acted=1
    note "branch $main_branch: pushed"
}

push_tag() {
    # $1 = tag name.
    local t="$1" remote_sha local_sha
    remote_sha=$(ls_remote_sha "refs/tags/$t")
    if ! local_sha=$(git rev-parse -q --verify "refs/tags/$t"); then
        # ensure_dist_tag's third case: origin has it, this clone does not.
        [ -n "$remote_sha" ] || die "tag $t exists neither here nor on origin"
        note "tag $t: already on origin (not in this clone)"
        return
    fi
    if [ -n "$remote_sha" ]; then
        # Never move a published tag: a mismatch means it was reused, which no
        # recovery should paper over.
        [ "$remote_sha" = "$local_sha" ] \
            || die "$t on origin points at $remote_sha, not $local_sha -- refusing to move a published tag"
        note "tag $t: already pushed"
        return
    fi
    git push origin "$t" || {
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf 'hint: clear what the push reported above, then run `just resume-release`.\n' >&2
        die "push of tag $t failed"
    }
    acted=1
    note "tag $t: pushed"
}

create_github_release() {
    if gh release view "$tag" >/dev/null 2>&1; then
        note "github release $tag: already created"
        return
    fi
    gh release create "$tag" --title "Release $V" --generate-notes || {
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf 'hint: %s is public through its pushed tags; only the release is missing.\n' "$tag" >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      clear what gh reported above, then run `just resume-release`.\n' >&2
        die "gh release create $tag failed"
    }
    acted=1
    note "github release $tag: created"
}

acted=0
common_preflight
if [ "$mode" = "release" ]; then
    release_preflight
    bump_commit_tag
else
    resume_preflight
fi
# The tag's commit: HEAD on a release, but on a resume HEAD may be past it. Resolved
# to a sha because `git fetch .` refuses the unresolved ^{commit} form.
release_commit=$(git rev-parse "$tag^{commit}")
ensure_dist_tag
move_main
push_branch
push_tag "$tag"
push_tag "$dist_tag"
create_github_release
if [ "$mode" = "resume" ] && [ "$acted" = 0 ]; then
    note "release $tag is already complete (nothing to do)"
else
    note "Release $tag complete (consumers pull $dist_tag)"
fi

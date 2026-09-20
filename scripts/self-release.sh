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

common_preflight() {
    # Same two exclusions toolkit/release.sh's tree_is_clean applies, for the
    # same reason: `.claude/` holds the agent working environment and the task
    # frames the handoff skills stage for the next commit, and the `memory`
    # gitlink rests ahead of HEAD until gitlore's pre-commit hook folds it in.
    # Written literally -- this repo is one known repo, not a consumer the
    # script has to discover. The pathspec matches at the path separator, so
    # `.claude-plugin` is not in scope (nor does one exist here).
    git diff --quiet HEAD -- . ':(exclude).claude' ':(exclude)memory' \
        || die "uncommitted changes"
    branch=$(git symbolic-ref -q --short HEAD) || die "not on a branch"
    if main_branch=$(git symbolic-ref -q --short refs/remotes/origin/HEAD); then
        main_branch=${main_branch#origin/}
    else
        main_branch="main"
    fi
    [ "$branch" = "$main_branch" ] \
        || die "must be on $main_branch (currently $branch)"
    [ -f toolkit/VERSION ] || die "toolkit/VERSION file missing"
    file_version=$(tr -d '[:space:]' < toolkit/VERSION)
    # Leading zeros are rejected, not merely tolerated: `$((08))` is a base
    # error, so a padded component would crash the bump arithmetic below
    # instead of refusing here.
    [[ "$file_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
        || die "toolkit/VERSION is not X.Y.Z: '$file_version'"
}

require_prior_release_published() {
    # The gap this closes. After the release commit and both tags land locally,
    # a failed push leaves toolkit/VERSION equal to the newest tag -- so the
    # drift guard passes, the "tag already exists" guard passes (it asks about
    # the NEXT version's tags), and a re-run publishes the next version while
    # this one stays stranded, tagged and unreleased, with nothing refusing it.
    local prior="v$file_version" dist="dist-v$file_version" missing=()
    # No local tag at this version means no release was ever cut here: a fresh
    # clone, or a repo predating the tagging scheme. Nothing to strand.
    git rev-parse -q --verify "refs/tags/$prior" >/dev/null || return 0
    # A failed ls-remote dies inside the substitution, which only ends the
    # subshell -- git's own message reaches stderr and the empty result reads
    # as "missing". That direction is the safe one: it refuses a release it
    # could not prove was needed, rather than bumping past an unfinished one.
    [ -n "$(ls_remote_sha "refs/tags/$prior")" ] || missing+=("$prior")
    [ -n "$(ls_remote_sha "refs/tags/$dist")" ] || missing+=("$dist")
    gh release view "$prior" >/dev/null 2>&1 \
        || missing+=("the GitHub release for $prior")
    if [ "${#missing[@]}" -eq 0 ]; then
        return 0
    fi
    printf 'hint: %s is tagged in this clone but not fully published. Missing:\n' \
        "$prior" >&2
    printf '        %s\n' "${missing[@]}" >&2
    printf '      bumping now would publish the next version and strand this one.\n' >&2
    # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
    printf '      run `just resume-release` to finish it, then release again.\n' >&2
    die "release $prior is unfinished"
}

release_preflight() {
    local maj min pat t tags
    # Lists every v* tag and filters it down, rather than asking `git describe`
    # for "the" latest one, because describe has two failure modes here: it
    # returns the nearest reachable tag matching its pattern whatever that
    # tag's name means, so a non-release tag like `vnext` sitting on HEAD would
    # be read as the latest release; and it only sees tags reachable from HEAD,
    # so a release tag off HEAD's ancestry would be invisible rather than
    # merely unranked. `--list 'v*' --sort=-v:refname` considers every v* tag
    # regardless of reachability, ordered by version, and the filter below
    # narrows that to the X.Y.Z shape -- which is what drops `vnext` and any
    # other non-release name the glob admits. The dist-v* lineage never reaches
    # that filter: the glob anchors at the start of the tag name, so
    # `git tag --list 'v*'` does not list `dist-v0.2.0` at all (measured).
    #
    # Captured into a local and filtered as a second step, via a here-string
    # rather than a pipe, for ls_remote_sha's reason above: a pipe would let a
    # failed listing's status vanish into grep's, and a grep matching nothing
    # in an empty repo would still report success.
    #
    # This duplicates the three-line tag-listing toolkit/release.sh also does
    # for a plugin consumer's own tags. That is intentional, not an oversight:
    # this file's header explains why the two scripts share no code, and three
    # lines of listing is not worth a shared flow branching on which release
    # this is.
    tags=$(git tag --list 'v*' --sort=-v:refname) || die "git tag --list failed"
    latest_tag=$(grep -m1 -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<< "$tags") || {
        # grep exits 1 for a clean no-match -- a repo holding no release tag
        # yet -- and non-1 for a real error. Only the first is a value: folding
        # an error into the empty case would leave $latest_tag empty, skip the
        # drift guard below, and release from whatever toolkit/VERSION holds
        # over a listing this function could not read. Same distinction
        # toolkit/release.sh's semver_tags draws with `[ "$?" -eq 1 ]`.
        [ "$?" -eq 1 ] || die "could not filter the tag listing -- nothing was done"
        latest_tag=""
    }
    latest_tag=${latest_tag#v}
    if [ -n "$latest_tag" ] && [ "$file_version" != "$latest_tag" ]; then
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf 'hint: toolkit/VERSION holds the LAST released version. `just release` bumps from there.\n' >&2
        printf '      revert any manual VERSION bump and re-run.\n' >&2
        die "toolkit/VERSION ($file_version) does not match latest tag (v$latest_tag)"
    fi
    require_prior_release_published
    IFS=. read -r maj min pat <<< "$file_version"
    case "$bump" in
        major) V="$((maj + 1)).0.0" ;;
        minor) V="$maj.$((min + 1)).0" ;;
        patch) V="$maj.$min.$((pat + 1))" ;;
    esac
    tag="v$V"
    dist_tag="dist-$tag"
    for t in "$tag" "$dist_tag"; do
        ! git rev-parse -q --verify "refs/tags/$t" >/dev/null \
            || die "tag $t already exists"
    done
}

resume_preflight() {
    V="$file_version"
    tag="v$V"
    dist_tag="dist-$tag"
    # Resume only ever finishes a release whose commit and tag already landed
    # locally. No tag means no release was started at this version, and tagging
    # HEAD on a guess would tag whatever work landed since.
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null || {
        # The refusal is already decided; the probe below only picks which hint
        # explains it, so an unreadable origin falling through to the second
        # branch costs a less precise message and nothing else.
        if [ -n "$(ls_remote_sha "refs/tags/$tag")" ]; then
            printf 'hint: origin already has %s -- this clone is just missing it.\n' "$tag" >&2
            # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
            printf '      run `git fetch --tags`, then run `just resume-release`.\n' >&2
        else
            printf 'hint: no release was started at %s.\n' "$V" >&2
            # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
            printf '      run `just release <bump>` instead.\n' >&2
        fi
        die "no tag $tag for toolkit/VERSION $V"
    }
}

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

push_branch() {
    local remote_head
    remote_head=$(ls_remote_sha "refs/heads/$branch")
    if [ -n "$remote_head" ] && [ "$remote_head" = "$(git rev-parse HEAD)" ]; then
        note "branch $branch: already pushed"
        return
    fi
    # gitlore's pre-push hook publishes every memory store before the parent
    # push and refuses when one diverged. The commit and the tags are already
    # local by now, so the recovery is resume -- never an amend, which would
    # re-pin the gitlink and rewrite a commit the tag names.
    git push || {
        printf 'hint: the release commit and tag %s are local; nothing was pushed.\n' "$tag" >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      clear what the push reported above, then run `just resume-release`.\n' >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      gitlore refuses the push while a memory store is diverged: `/gitlore:resolve`\n' >&2
        printf '      in Claude Code clears it. Repeat the pair if the push is refused again.\n' >&2
        die "push of $branch failed"
    }
    acted=1
    note "branch $branch: pushed"
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
ensure_dist_tag
push_branch
push_tag "$tag"
push_tag "$dist_tag"
create_github_release
if [ "$mode" = "resume" ] && [ "$acted" = 0 ]; then
    note "release $tag is already complete (nothing to do)"
else
    note "Release $tag complete (consumers pull $dist_tag)"
fi

# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154  # globals shared with self-release.sh's shell
#
# Sourced by self-release.sh, never run on its own. The preflights: everything
# that runs before the release writes or publishes anything, apart from the
# publish steps that follow in the main script.
#
# It runs in self-release.sh's shell, so that script's `set -euo pipefail` and
# its die/note/ls_remote_sha helpers apply here, and these functions read and
# set the run's globals (`main_branch`, `branch`, `file_version`, `V`, `tag`,
# `dist_tag`, `latest_tag`, `bump`) directly rather than through arguments.

common_preflight() {
    # The `memory` gitlink is excluded, as toolkit/release-preflight.sh's
    # tree_is_clean excludes the gitlore memory submodule: it rests ahead of
    # HEAD until gitlore's pre-commit hook folds it in on the next commit.
    # Written literally -- this repo is one known repo, not a consumer the
    # script has to discover.
    git diff --quiet HEAD -- . ':(exclude)memory' \
        || die "uncommitted changes"
    # Read before the branch: the refusal below names it, and set -u would
    # otherwise end the script on an unset variable.
    if main_branch=$(git symbolic-ref -q --short refs/remotes/origin/HEAD); then
        main_branch=${main_branch#origin/}
    else
        main_branch="main"
    fi
    branch=$(git symbolic-ref -q --short HEAD) \
        || die "not on a branch (must be on $main_branch or dev)"
    # Releases cut from the default branch or from dev, the branch where work
    # lands. dev is never pushed: the release publishes the tag's commit to
    # main alone.
    case "$branch" in
        "$main_branch"|dev) ;;
        *) die "must be on $main_branch or dev (currently $branch)" ;;
    esac
    [ -f toolkit/VERSION ] || die "toolkit/VERSION file missing"
    file_version=$(tr -d '[:space:]' < toolkit/VERSION)
    # Leading zeros are rejected, not merely tolerated: `$((08))` is a base
    # error, so a padded component would crash the bump arithmetic below
    # instead of refusing here.
    [[ "$file_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
        || die "toolkit/VERSION is not X.Y.Z: '$file_version'"
    # A plain fetch: origin's main is read below, and git's tag following can
    # bring back a tag this clone lacks. resume_preflight judges a tag by its
    # commit, not by how it arrived.
    git fetch origin || die "git fetch origin failed"
    # Refused before anything is written: with either main holding commits HEAD
    # lacks, the move or the push would refuse only after the tag was cut.
    git merge-base --is-ancestor "refs/heads/$main_branch" HEAD \
        || die "local $main_branch is not an ancestor of HEAD"
    git merge-base --is-ancestor "refs/remotes/origin/$main_branch" HEAD \
        || die "origin/$main_branch is not an ancestor of HEAD"
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
    # Each probe is captured into a variable, never tested inline: a failed
    # ls-remote dies inside the substitution, which only ends the subshell, so
    # a `[ -n "$(ls_remote_sha ...)" ]` reads the failure as "absent" and the
    # hint below would list tags that are published as missing. `|| exit 1`
    # ends the script instead; die has already named the failed probe.
    local prior_sha dist_sha
    prior_sha=$(ls_remote_sha "refs/tags/$prior") || exit 1
    dist_sha=$(ls_remote_sha "refs/tags/$dist") || exit 1
    [ -n "$prior_sha" ] || missing+=("$prior")
    [ -n "$dist_sha" ] || missing+=("$dist")
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
    # Resume only ever finishes a release whose commit and tag already landed.
    # With no tag after common_preflight's fetch there is nothing to finish, and
    # tagging HEAD on a guess would tag whatever work landed since.
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null || {
        printf 'hint: no release was started at %s.\n' "$V" >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      run `just release <bump>` instead.\n' >&2
        die "no tag $tag for toolkit/VERSION $V"
    }
    # A tag off HEAD's history would move main, and publish, off the branch the next release is cut from.
    git merge-base --is-ancestor "$tag^{commit}" HEAD || {
        local release_sha
        # Only a release changes toolkit/VERSION, so this is the release commit as the branch now has it.
        release_sha=$(git log -1 --format=%H -- toolkit/VERSION)
        printf 'hint: %s names a commit %s does not carry, as after an amend or rebase of the release commit.\n' "$tag" "$branch" >&2
        printf '      if %s is not on origin, these commands re-tag it:\n' "$tag" >&2
        printf '        git tag -d %s %s; git tag -a %s -m "Release %s" %s\n' "$tag" "$dist_tag" "$tag" "$V" "$release_sha" >&2
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '      then run `just resume-release`.\n' >&2
        die "$tag is not on the history of $branch"
    }
}

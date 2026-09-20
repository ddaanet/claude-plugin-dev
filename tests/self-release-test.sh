#!/usr/bin/env bash
# End-to-end test of scripts/self-release.sh against real git repos in a temp
# dir. No network: origins are local bare repos and `gh` is a stub on PATH.
#
# The fixture is shaped like this repo -- a toolkit/ subdirectory that gets
# split into a dist- tag, plus root-only files that must NOT reach it -- rather
# than like a consumer plugin, which is what tests/release-test.sh covers.
#
# Usage: bash tests/self-release-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit` leaks
# GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every git command
# below targets a fixture repo via `-C` or a `cd`, never this repo, so it's
# always safe to drop them here.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/scripts/self-release.sh"

failures=0
fail() {
    printf 'FAIL: %s\n' "$1" >&2
    failures=$((failures + 1))
}
assert_eq() {
    # $1=actual $2=expected $3=label
    if [[ "$1" != "$2" ]]; then
        fail "$3: expected '$2', got '$1'"
    fi
}
assert_contains() {
    # $1=haystack $2=needle $3=label
    if ! printf '%s' "$1" | grep -q -- "$2"; then
        fail "$3: output did not contain '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}
assert_not_contains() {
    # $1=haystack $2=needle $3=label
    if printf '%s' "$1" | grep -q -- "$2"; then
        fail "$3: output contained '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}
assert_tag() {
    # $1=tag $2=where (local|origin) $3=label — asserts the tag exists there.
    case "$2" in
        local)  git -C "$repo" rev-parse -q --verify "refs/tags/$1" >/dev/null \
                    || fail "$3: local tag $1 missing" ;;
        origin) [ -n "$(git -C "$repo" ls-remote origin "refs/tags/$1")" ] \
                    || fail "$3: tag $1 not on origin" ;;
    esac
}
refute_tag() {
    # $1=tag $2=label
    if git -C "$repo" rev-parse -q --verify "refs/tags/$1" >/dev/null; then
        fail "$2: tag $1 should not exist"
    fi
}
assert_gh_untouched() {
    # $1=label. Fails unless $GH_LOG is empty -- pinning that the refusal
    # happened before `gh` was ever reached, not merely that its visible
    # output was absent. $GH_LOG is truncated per new_sandbox, so a scenario
    # sharing one sandbox across several refusals must call this between runs
    # rather than once at the end, or an earlier touch could be attributed to
    # the wrong one.
    local logged
    logged="$(cat "$GH_LOG")"
    [ -z "$logged" ] || fail "$1: gh was touched ($logged)"
}

sandboxes=()
cleanup() {
    local s
    for s in "${sandboxes[@]:-}"; do
        [ -n "$s" ] && rm -rf "$s"
    done
}
trap cleanup EXIT

out=""
rc=0
run() {
    # Runs the script under test in $repo. Captures stdout+stderr in $out.
    set +e
    out="$(cd "$repo" && bash "$script" "$@" 2>&1)"
    rc=$?
    set -e
}

new_sandbox() {
    # A repo shaped like claude-plugin-dev, already released at 0.1.0: both
    # tags pushed and the GitHub release "created", so the prior-release guard
    # is satisfied and a test that wants it unsatisfied breaks it explicitly.
    sandbox="$(mktemp -d)"
    sandboxes+=("$sandbox")
    repo="$sandbox/repo"

    mkdir -p "$sandbox/bin" "$sandbox/releases"
    cat > "$sandbox/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
    "release view")   [ -f "$GH_RELEASES/$3" ] || exit 1 ;;
    "release create") : > "$GH_RELEASES/$3" ;;
    *) printf 'gh stub: unhandled: %s\n' "$*" >&2; exit 127 ;;
esac
STUB
    chmod +x "$sandbox/bin/gh"
    export GH_LOG="$sandbox/gh.log"
    export GH_RELEASES="$sandbox/releases"
    : > "$GH_LOG"
    export PATH="$sandbox/bin:$PATH"

    git init -q -b main "$repo"
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name "Toolkit Test"
    git -C "$repo" config commit.gpgsign false
    git init -q --bare -b main "$repo-origin.git"
    git -C "$repo" remote add origin "$repo-origin.git"

    mkdir -p "$repo/toolkit"
    printf '0.1.0\n' > "$repo/toolkit/VERSION"
    printf '# shipped manual\n' > "$repo/toolkit/README.md"
    printf 'this file is the dev environment, not the dist tree\n' > "$repo/ROOT-ONLY.md"
    git -C "$repo" add -A
    git -C "$repo" commit -qm "init"
    git -C "$repo" tag -a v0.1.0 -m "Release 0.1.0"
    local dist_sha
    dist_sha=$(git -C "$repo" subtree split -q --prefix=toolkit v0.1.0)
    git -C "$repo" tag -a dist-v0.1.0 -m "Dist 0.1.0" "$dist_sha"
    git -C "$repo" push -q -u origin main
    git -C "$repo" push -q origin v0.1.0 dist-v0.1.0
    : > "$GH_RELEASES/v0.1.0"
}

commit_in_repo() {
    # $1=path $2=content — an ordinary commit on top of the release.
    printf '%s\n' "$2" > "$repo/$1"
    git -C "$repo" add -A
    git -C "$repo" commit -qm "work: $1"
}

block_push() {
    printf '#!/bin/sh\necho "pre-push: refused by fixture" >&2\nexit 1\n' \
        > "$repo/.git/hooks/pre-push"
    chmod +x "$repo/.git/hooks/pre-push"
}
unblock_push() { rm -f "$repo/.git/hooks/pre-push"; }

stage_claude_frame() {
    # $1=repo path. Reproduces what the handoff skills leave behind: a task
    # frame under .claude/, committed once and then rewritten and staged for
    # whatever commit lands next. Staged, not merely written -- an untracked
    # frame never reaches common_preflight's tracked-only
    # `git diff --quiet HEAD` in the first place, so a fixture that only
    # writes it untracked would exercise nothing. Same shape as
    # stage_handoff_frame in tests/release-test.sh.
    local dir="$1"
    mkdir -p "$dir/.claude"
    printf 'frame v1\n' > "$dir/.claude/handoff-task.md"
    git -C "$dir" add .claude/handoff-task.md
    git -C "$dir" commit -qm "handoff frame"
    printf 'frame v2\n' > "$dir/.claude/handoff-task.md"
    git -C "$dir" add .claude/handoff-task.md
}

stage_memory_gitlink() {
    # $1=repo path $2=sandbox path -- builds a real submodule inside
    # $sandbox, not shared across scenarios: new_sandbox rebuilds $repo on
    # every call, so a shared upstream outside the sandbox would leave state
    # crossing scenario boundaries -- a fixture that works alone and breaks
    # once another scenario runs ahead of it. Two empty commits upstream, add
    # it as memory/ at the second, commit the gitlink, then check the
    # submodule itself out at the first -- the gitlink recorded in HEAD's
    # tree and the submodule's own checked-out commit now disagree, the
    # resting state gitlore leaves. `-c protocol.file.allow=always` is
    # required, not optional: `submodule add` clones via a child process that
    # reads its own environment rather than the parent repo's config, and a
    # plain local-path add fails with `fatal: transport 'file' not allowed`.
    local dir="$1" upstream="$2/sub" first_sha
    git init -q -b main "$upstream"
    git -C "$upstream" config user.email test@example.com
    git -C "$upstream" config user.name "Toolkit Test"
    git -C "$upstream" config commit.gpgsign false
    git -C "$upstream" commit -q --allow-empty -m c1
    first_sha=$(git -C "$upstream" rev-parse HEAD)
    git -C "$upstream" commit -q --allow-empty -m c2
    git -c protocol.file.allow=always -C "$dir" submodule add -q "$upstream" memory
    git -C "$dir" commit -qm "memory gitlink"
    git -C "$dir/memory" checkout -q "$first_sha"
}

echo "=== happy path: minor bump publishes everything ==="
new_sandbox
run minor
assert_eq "$rc" 0 "happy: exit status"
assert_contains "$out" "Release v0.2.0 complete" "happy: final line"
assert_eq "$(cat "$repo/toolkit/VERSION")" "0.2.0" "happy: VERSION file"
git -C "$repo" diff --quiet HEAD || fail "happy: tree left dirty"
# diff --quiet HEAD reads tracked paths only, so an untracked leftover the
# release steps write (a stray file, a build byproduct) would pass it
# silently -- ls-files --others --exclude-standard is the tracked check's
# blind spot, the way stage_handoff_frame in tests/release-test.sh documents
# for the opposite direction (an untracked frame never reaching a tracked-only
# check).
untracked=$(git -C "$repo" ls-files --others --exclude-standard)
[ -z "$untracked" ] || fail "happy: untracked leftovers left ($untracked)"
assert_tag v0.2.0 local "happy"
assert_tag dist-v0.2.0 local "happy"
assert_tag v0.2.0 origin "happy"
assert_tag dist-v0.2.0 origin "happy"
assert_contains "$(cat "$GH_LOG")" "release create v0.2.0" "happy: gh called"
# The dist tree is what a consumer vendors: toolkit/'s contents at the root,
# carrying the bumped VERSION, and none of the repo's own working environment.
dist_files=$(git -C "$repo" ls-tree --name-only dist-v0.2.0)
assert_contains "$dist_files" "VERSION" "happy: dist tree has VERSION"
assert_contains "$dist_files" "README.md" "happy: dist tree has README"
assert_not_contains "$dist_files" "ROOT-ONLY" "happy: dist tree is root-free"
assert_not_contains "$dist_files" "toolkit" "happy: dist tree is unprefixed"
assert_eq "$(git -C "$repo" show dist-v0.2.0:VERSION)" "0.2.0" "happy: dist VERSION"

echo "=== bump arithmetic ==="
new_sandbox
run major
assert_contains "$out" "Release v1.0.0 complete" "major: bump"
new_sandbox
run
assert_contains "$out" "Release v0.1.1 complete" "default: patch bump"

echo "=== vnext on ancestry is not the latest tag ==="
# v0.1.0 ends up on HEAD~ and the non-release tag vnext on HEAD. The latest
# RELEASE tag is still v0.1.0, so release_preflight's drift guard must stay
# quiet and the bump must go through -- which it only does if that function
# lists and filters tags. Asking git for the nearest reachable tag instead
# answers "vnext", and the refusal it produces names a tag no bump can match.
new_sandbox
commit_in_repo work.md "ordinary work after 0.1.0"
git -C "$repo" tag vnext
run minor
assert_eq "$rc" 0 "vnext: exit status"
assert_tag v0.2.0 local "vnext"
assert_not_contains "$out" "does not match latest tag" "vnext: no drift refusal"

echo "=== release tag off ancestry still triggers drift guard ==="
# v0.9.0 sits on a branch that never merged into main, so it is unreachable
# from HEAD -- yet it is still the latest RELEASE tag, and toolkit/VERSION
# (0.1.0, from v0.1.0's release) must be read as stale against it. Asking git
# for the nearest reachable tag instead makes v0.9.0 invisible, so the drift
# guard sees only the reachable v0.1.0, which matches, and the release
# proceeds -- the newer tag went unnoticed, not merely unranked.
new_sandbox
git -C "$repo" checkout -q -b abandoned
commit_in_repo abandoned.md "on a branch that never merged"
git -C "$repo" tag -a v0.9.0 -m "abandoned release attempt"
git -C "$repo" checkout -q main
git -C "$repo" branch -q -D abandoned
# The fixture's whole point is the reachability split, and nothing downstream
# would notice if it collapsed: were v0.9.0 reachable, `describe` would answer
# it too and the assertions below would pass against the very shape they exist
# to reject. Pin both directions.
assert_tag v0.9.0 local "ancestry fixture"
git -C "$repo" merge-base --is-ancestor v0.1.0 HEAD \
    || fail "ancestry fixture: v0.1.0 is not reachable from HEAD"
if git -C "$repo" merge-base --is-ancestor v0.9.0 HEAD; then
    fail "ancestry fixture: v0.9.0 is reachable from HEAD"
fi
run minor
assert_eq "$rc" 1 "ancestry: exit status"
assert_contains "$out" "does not match latest tag (v0.9.0)" "ancestry: names off-ancestry tag"

echo "=== an unfinished release refuses a new one ==="
new_sandbox
block_push
run minor
assert_eq "$rc" 1 "blocked: exit status"
assert_contains "$out" "push of main failed" "blocked: names the failure"
assert_contains "$out" "resume-release" "blocked: points at resume"
assert_tag v0.2.0 local "blocked"
assert_tag dist-v0.2.0 local "blocked"
assert_eq "$(cat "$repo/toolkit/VERSION")" "0.2.0" "blocked: VERSION bumped locally"
unblock_push
# This is the gap the script exists to close: VERSION now equals the newest
# tag, so the drift guard passes and the next-version tags are free.
run minor
assert_eq "$rc" 1 "stranded: exit status"
assert_contains "$out" "release v0.2.0 is unfinished" "stranded: names the version"
assert_contains "$out" "just resume-release" "stranded: points at resume"
refute_tag v0.3.0 "stranded"
assert_eq "$(cat "$repo/toolkit/VERSION")" "0.2.0" "stranded: VERSION untouched"

echo "=== resume finishes it ==="
run --resume
assert_eq "$rc" 0 "resume: exit status"
assert_contains "$out" "Release v0.2.0 complete" "resume: final line"
assert_tag v0.2.0 origin "resume"
assert_tag dist-v0.2.0 origin "resume"
assert_contains "$(cat "$GH_LOG")" "release create v0.2.0" "resume: gh called"
refute_tag v0.3.0 "resume"

echo "=== resume is idempotent ==="
run --resume
assert_eq "$rc" 0 "resume twice: exit status"
assert_contains "$out" "already complete (nothing to do)" "resume twice: says so"
# Every step reports "already ..."; none reports having done anything. The
# anchors matter: "already pushed" contains "pushed".
assert_not_contains "$out" ": pushed$" "resume twice: pushed nothing"
assert_not_contains "$out" ": created$" "resume twice: created nothing"

echo "=== resume after later work inside toolkit/ ==="
new_sandbox
block_push
run minor
unblock_push
commit_in_repo toolkit/later-work.md "written after the release commit, inside toolkit/"
# ensure_dist_tag runs before push_branch, so the blocked `run minor` above
# already created dist-v0.2.0 locally. Left in place, --resume would take
# ensure_dist_tag's own "already created locally" short-circuit and
# `git subtree split` would never run at all -- the assertions below would
# then pass whether the split targets the tag or HEAD, discriminating
# nothing. Deleting the local tag first forces the split to actually run (the
# dead-origin resume scenario further down clears the same tag for the same
# reason).
git -C "$repo" tag -d dist-v0.2.0 >/dev/null
run --resume
assert_eq "$rc" 0 "resume after work: exit status"
assert_tag dist-v0.2.0 origin "resume after work"
# Split from the tag, not HEAD: HEAD now carries toolkit/later-work.md, added
# after the release commit. A split of HEAD would carry it into the dist
# tree; a split of $tag would not. This is what discriminates the two --
# splitting always "against the tagged commit at all" is not enough, because
# the first invocation's split (above) ran when HEAD and the tag coincided.
if git -C "$repo" show dist-v0.2.0:later-work.md >/dev/null 2>&1; then
    fail "resume after work: dist tree carries later work"
fi
dist_files_after_work=$(git -C "$repo" ls-tree --name-only dist-v0.2.0)
assert_not_contains "$dist_files_after_work" "later-work" \
    "resume after work: dist tree omits later file"
assert_eq "$(git -C "$repo" show dist-v0.2.0:VERSION)" "0.2.0" "resume after work: dist VERSION"

echo "=== a partially published release still refuses a bump ==="
new_sandbox
rm -f "$GH_RELEASES/v0.1.0"
run minor
assert_eq "$rc" 1 "no gh release: exit status"
assert_contains "$out" "the GitHub release for v0.1.0" "no gh release: names it"
refute_tag v0.2.0 "no gh release"
new_sandbox
git -C "$repo" push -q origin ":refs/tags/dist-v0.1.0"
run minor
assert_eq "$rc" 1 "no dist tag: exit status"
assert_contains "$out" "dist-v0.1.0" "no dist tag: names it"
refute_tag v0.2.0 "no dist tag"

echo "=== resume refusals ==="
new_sandbox
git -C "$repo" tag -d v0.1.0 >/dev/null
run --resume
assert_eq "$rc" 1 "resume, tag on origin only: exit status"
assert_contains "$out" "origin already has v0.1.0" "resume, tag on origin only: hint"
assert_contains "$out" "git fetch --tags" "resume, tag on origin only: remedy"
new_sandbox
git -C "$repo" tag -d v0.1.0 >/dev/null
git -C "$repo" push -q origin ":refs/tags/v0.1.0"
run --resume
assert_eq "$rc" 1 "resume, no tag anywhere: exit status"
assert_contains "$out" "no release was started at 0.1.0" "resume, no tag anywhere: hint"
assert_contains "$out" "just release <bump>" "resume, no tag anywhere: remedy"
# v0.1.0, the version this resume is about: the scenario deleted it here and
# on origin, and the refusal must not leave one behind. v0.2.0 names a bump
# --resume never performs.
refute_tag v0.1.0 "resume, no tag anywhere"
assert_gh_untouched "resume, no tag anywhere"

echo "=== never moves a published tag ==="
new_sandbox
run minor
git -C "$repo" tag -d v0.2.0 >/dev/null
commit_in_repo other.md "a different commit"
git -C "$repo" tag -a v0.2.0 -m "Release 0.2.0"
run --resume
assert_eq "$rc" 1 "moved tag: exit status"
assert_contains "$out" "refusing to move a published tag" "moved tag: refusal"

echo "=== preflight refusals ==="
new_sandbox
printf 'dirty\n' > "$repo/ROOT-ONLY.md"
run minor
assert_eq "$rc" 1 "dirty tree: exit status"
assert_contains "$out" "uncommitted changes" "dirty tree"
refute_tag v0.2.0 "dirty tree"
assert_gh_untouched "dirty tree"
git -C "$repo" checkout -q -- ROOT-ONLY.md
# common_preflight's `git diff --quiet HEAD -- . ':(exclude).claude'
# ':(exclude)memory'` sees tracked content only, so an untracked .claude/ file
# or an absent memory/ directory would never reach the check either way --
# proving the exclusions requires constructing real diffs under both paths
# for them to suppress, not merely creating the paths.
stage_memory_gitlink "$repo" "$sandbox"
stage_claude_frame "$repo"
run minor
assert_eq "$rc" 0 ".claude/ and memory/ are exempted from the clean check"

new_sandbox
git -C "$repo" checkout -q -b side
run minor
assert_eq "$rc" 1 "wrong branch: exit status"
assert_contains "$out" "must be on main (currently side)" "wrong branch"
refute_tag v0.2.0 "wrong branch"
assert_gh_untouched "wrong branch"

new_sandbox
printf '0.2\n' > "$repo/toolkit/VERSION"
git -C "$repo" commit -qam "bad version"
run minor
assert_eq "$rc" 1 "malformed VERSION: exit status"
assert_contains "$out" "toolkit/VERSION is not X.Y.Z" "malformed VERSION"
# v0.3.0, not v0.2.0: '0.2' reads as maj=0 min=2 pat='', so a minor bump that
# got past the shape guard would tag v0.3.0. Naming the tag no path creates
# would leave this unfalsifiable.
refute_tag v0.3.0 "malformed VERSION"
assert_gh_untouched "malformed VERSION"
new_sandbox
printf '0.08.0\n' > "$repo/toolkit/VERSION"
git -C "$repo" commit -qam "padded version"
run minor
assert_eq "$rc" 1 "zero-padded VERSION: exit status"
assert_contains "$out" "toolkit/VERSION is not X.Y.Z" "zero-padded VERSION"
refute_tag v0.2.0 "zero-padded VERSION"
assert_gh_untouched "zero-padded VERSION"

new_sandbox
printf '0.2.0\n' > "$repo/toolkit/VERSION"
git -C "$repo" commit -qam "hand-written bump"
run minor
assert_eq "$rc" 1 "hand-written bump: exit status"
assert_contains "$out" "does not match latest tag (v0.1.0)" "hand-written bump"
assert_contains "$out" "holds the LAST released version" "hand-written bump: hint"
# 0.2.0 is what the hand-written VERSION holds; a minor bump from there would
# tag v0.3.0 if the drift guard did not catch it first.
refute_tag v0.3.0 "hand-written bump"
assert_gh_untouched "hand-written bump"

# The dist lineage, because `git tag --list 'v*'` never lists it -- the glob
# anchors at the start of the tag name, so dist-v0.2.0 is absent from
# release_preflight's listing before its X.Y.Z filter runs at all. A squatting
# v0.2.0 reachable from HEAD is caught one guard earlier, by the drift check.
new_sandbox
git -C "$repo" tag -a dist-v0.2.0 -m "squatter"
run minor
assert_eq "$rc" 1 "tag squatting: exit status"
assert_contains "$out" "tag dist-v0.2.0 already exists" "tag squatting"
refute_tag v0.2.0 "tag squatting"
# gh IS legitimately reached here, by require_prior_release_published's own
# `gh release view` a few lines before the squatting die -- unlike every
# other preflight refusal, which dies before release_preflight gets that far.
# Pinned as the WHOLE log rather than a needle in it, so this scenario still
# asserts what assert_gh_untouched asserts everywhere else: that nothing but
# that one read-only call reached gh. A containment check would pass with a
# `release create` logged after it.
assert_eq "$(cat "$GH_LOG")" "release view v0.1.0" \
    "tag squatting: gh reached only for the prior-release check"

new_sandbox
run sideways
assert_eq "$rc" 1 "bad argument: exit status"
assert_contains "$out" "unknown bump type: sideways" "bad argument"
refute_tag v0.2.0 "bad argument"
assert_gh_untouched "bad argument"
run --wat
assert_eq "$rc" 1 "bad option: exit status"
assert_contains "$out" "unknown option: --wat" "bad option"
refute_tag v0.2.0 "bad option"
assert_gh_untouched "bad option"
run minor patch
assert_eq "$rc" 1 "extra argument: exit status"
assert_contains "$out" "too many arguments" "extra argument"
refute_tag v0.2.0 "extra argument"
assert_gh_untouched "extra argument"

echo "=== an unreadable origin refuses rather than proceeds ==="
new_sandbox
git -C "$repo" remote set-url origin "$sandbox/does-not-exist.git"
run minor
assert_eq "$rc" 1 "dead origin: exit status"
assert_contains "$out" "release v0.1.0 is unfinished" "dead origin: refuses"
refute_tag v0.2.0 "dead origin"
# A resume that cannot read origin must not re-cut the dist tag on a guess:
# a local tag differing from the published one is a dead end, since push_tag
# then refuses to move it and says nothing about how to clear it.
new_sandbox
block_push
run minor
unblock_push
git -C "$repo" tag -d dist-v0.2.0 >/dev/null
git -C "$repo" remote set-url origin "$sandbox/does-not-exist.git"
run --resume
assert_eq "$rc" 1 "dead origin on resume: exit status"
refute_tag dist-v0.2.0 "dead origin on resume"

if [ "$failures" -eq 0 ]; then
    echo "self-release.sh: ok"
else
    printf '%d self-release check(s) failed\n' "$failures" >&2
    exit 1
fi

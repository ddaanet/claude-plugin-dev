#!/usr/bin/env bash
# End-to-end test of scripts/self-release.sh against real git repos in a temp
# dir, for the branch it releases from. No network: origins are local bare
# repos and `gh` is a stub on PATH.
#
# Scope: releasing from `dev` as well as `main`. The release moves main to the
# release commit and leaves dev checked out and unpublished; branch and ancestry
# refusals; a resume after later dev commits publishes the tag's commit, not
# HEAD. Its siblings self-release-publish-test.sh and
# self-release-refusal-test.sh cover the publishing and refusal paths from main.
#
# The fixture's origin `main` can move on its own (a second clone pushes to the
# bare repo) while the fixture repo never fetches, so a refusal that names
# origin/main can only come from the script's own fetch.
#
# Usage: bash tests/self-release-branch-test.sh   (run from repo root)
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
    # Residual bound: the needle is a grep BRE matched line by line --
    # a metacharacter in it is live, and a needle that spans a newline
    # can never match.
    # A here-string, never a pipe: under pipefail grep -q exits on its first
    # match, the writer can take SIGPIPE, and the pipeline reports failure.
    if ! grep -q -- "$2" <<<"$1"; then
        fail "$3: output did not contain '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}
rev() {
    # $1=a revision. Prints its sha in the fixture repo, empty if it does not
    # resolve. Never fails: a missing ref is a value for an assertion to judge,
    # not a reason for `set -e` to end the suite.
    git -C "$repo" rev-parse -q --verify "$1" || true
}
origin_sha() {
    # $1=a full ref name. Prints its sha on origin, empty if absent there.
    local line
    line=$(git -C "$repo" ls-remote origin "$1") \
        || { fail "git ls-remote origin $1 failed"; return 0; }
    printf '%s' "${line%%$'\t'*}"
}
assert_tag() {
    # $1=tag $2=where (local|origin) $3=label — asserts the tag exists there.
    case "$2" in
        local)  [ -n "$(rev "refs/tags/$1")" ] \
                    || fail "$3: local tag $1 missing" ;;
        origin) [ -n "$(origin_sha "refs/tags/$1")" ] \
                    || fail "$3: tag $1 not on origin" ;;
    esac
}
refute_tag() {
    # $1=tag $2=label — asserts the tag exists neither here nor on origin.
    [ -z "$(rev "refs/tags/$1")" ] || fail "$2: local tag $1 should not exist"
    [ -z "$(origin_sha "refs/tags/$1")" ] || fail "$2: tag $1 should not be on origin"
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
    # A repo shaped like claude-plugin-dev, already released at 0.1.0 from main
    # (both tags pushed, the GitHub release "created"), then checked out on
    # `dev` one unpublished commit ahead of main: the state a release starts
    # from. Only main is on origin.
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/self-release-branch.XXXXXX")"
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

    git -C "$repo" checkout -q -b dev
    commit_in_repo dev-work.md "work on dev"
}

commit_in_repo() {
    # $1=path $2=content — an ordinary commit on the checked-out branch.
    printf '%s\n' "$2" > "$repo/$1"
    git -C "$repo" add -A
    git -C "$repo" commit -qm "work: $1"
}

hand_release() {
    # What bump_commit_tag leaves, built by hand on the checked-out branch: the
    # script under test is not the one that cuts a release from dev here.
    printf '0.2.0\n' > "$repo/toolkit/VERSION"
    git -C "$repo" add toolkit/VERSION
    git -C "$repo" commit -qm "release: 0.2.0"
    git -C "$repo" tag -a v0.2.0 -m "Release 0.2.0"
    release_sha=$(rev HEAD)
}

complete_release() {
    # A finished release, built by hand on dev: release commit, both tags, main
    # at the release commit, all pushed, and the GitHub release present.
    hand_release
    local dist_sha
    dist_sha=$(git -C "$repo" subtree split -q --prefix=toolkit v0.2.0)
    git -C "$repo" tag -a dist-v0.2.0 -m "Dist 0.2.0" "$dist_sha"
    git -C "$repo" branch -f main HEAD
    git -C "$repo" push -q origin main v0.2.0 dist-v0.2.0
    : > "$GH_RELEASES/v0.2.0"
}

move_origin_main() {
    # Origin's main gains a commit from a second clone, so the fixture repo has
    # not fetched it: only the script's own fetch can see it.
    local other="$sandbox/other"
    git clone -q "$repo-origin.git" "$other"
    git -C "$other" config user.email test@example.com
    git -C "$other" config user.name "Toolkit Test"
    git -C "$other" config commit.gpgsign false
    printf 'only on origin\n' > "$other/origin-only.md"
    git -C "$other" add -A
    git -C "$other" commit -qm "work: origin-only.md"
    git -C "$other" push -q origin main
    [ "$(rev refs/remotes/origin/main)" != "$(origin_sha refs/heads/main)" ] \
        || fail "fixture: the repo already knows origin's new main, so the fetch proves nothing"
}

assert_on_dev() {
    # $1=label — the release never changes the checked-out branch, and never
    # publishes dev.
    assert_eq "$(git -C "$repo" symbolic-ref -q --short HEAD || true)" dev "$1: HEAD branch"
    assert_eq "$(origin_sha refs/heads/dev)" "" "$1: dev on origin"
}

echo "=== a release from dev ==="
new_sandbox
run minor
assert_eq "$rc" 0 "release from dev: exit status"
assert_tag v0.2.0 local "release from dev"
assert_tag v0.2.0 origin "release from dev"
assert_tag dist-v0.2.0 origin "release from dev"
release_sha=$(rev "refs/tags/v0.2.0^{commit}")
[ -n "$release_sha" ] || fail "release from dev: tag v0.2.0 does not resolve to a commit"
assert_eq "$(rev refs/heads/main)" "$release_sha" "release from dev: local main"
assert_eq "$(origin_sha refs/heads/main)" "$release_sha" "release from dev: origin main"
assert_eq "$(rev HEAD)" "$release_sha" "release from dev: HEAD is the release commit"
assert_on_dev "release from dev"

echo "=== another branch refuses ==="
new_sandbox
git -C "$repo" checkout -q -b side
run minor
assert_eq "$rc" 1 "branch side: exit status"
assert_contains "$out" "must be on main or dev (currently side)" "branch side"
refute_tag v0.2.0 "branch side"

echo "=== a local main HEAD lacks refuses ==="
new_sandbox
git -C "$repo" checkout -q main
commit_in_repo main-only.md "only on main"
git -C "$repo" checkout -q dev
run minor
assert_eq "$rc" 1 "local main ahead: exit status"
assert_contains "$out" "local main is not an ancestor of HEAD" "local main ahead"
refute_tag v0.2.0 "local main ahead"
refute_tag dist-v0.2.0 "local main ahead"
assert_eq "$(tr -d '[:space:]' < "$repo/toolkit/VERSION")" 0.1.0 "local main ahead: VERSION"

echo "=== an origin main HEAD lacks refuses ==="
new_sandbox
move_origin_main
run minor
assert_eq "$rc" 1 "origin main ahead: exit status"
assert_contains "$out" "origin/main is not an ancestor of HEAD" "origin main ahead"
refute_tag v0.2.0 "origin main ahead"
refute_tag dist-v0.2.0 "origin main ahead"
assert_eq "$(tr -d '[:space:]' < "$repo/toolkit/VERSION")" 0.1.0 "origin main ahead: VERSION"

echo "=== a resume after a later dev commit publishes the tag, not HEAD ==="
new_sandbox
hand_release
commit_in_repo later.md "after the release"
later_sha=$(rev HEAD)
run --resume
assert_eq "$rc" 0 "resume past later commit: exit status"
assert_eq "$(rev refs/heads/main)" "$release_sha" "resume past later commit: local main"
assert_eq "$(origin_sha refs/heads/main)" "$release_sha" "resume past later commit: origin main"
assert_tag v0.2.0 origin "resume past later commit"
assert_tag dist-v0.2.0 origin "resume past later commit"
assert_eq "$(rev HEAD)" "$later_sha" "resume past later commit: HEAD"
assert_on_dev "resume past later commit"

echo "=== a resume of a complete release pushes nothing ==="
new_sandbox
complete_release
commit_in_repo later.md "after the release"
before=$(git -C "$repo" ls-remote origin)
run --resume
after=$(git -C "$repo" ls-remote origin)
assert_eq "$rc" 0 "resume of complete release: exit status"
assert_contains "$out" "is already complete" "resume of complete release"
assert_eq "$after" "$before" "resume of complete release: origin refs"
assert_eq "$(origin_sha refs/heads/main)" "$release_sha" "resume of complete release: origin main"
assert_eq "$(rev refs/heads/main)" "$release_sha" "resume of complete release: local main"
assert_eq "$(grep -c 'release create' "$GH_LOG" || true)" 0 "resume of complete release: gh release create"
assert_on_dev "resume of complete release"

echo "=== origin main HEAD lacks refuses from main too ==="
new_sandbox
git -C "$repo" checkout -q main
move_origin_main
run minor
assert_eq "$rc" 1 "origin main ahead, on main: exit status"
assert_contains "$out" "origin/main is not an ancestor of HEAD" "origin main ahead, on main"
refute_tag v0.2.0 "origin main ahead, on main"
assert_eq "$(tr -d '[:space:]' < "$repo/toolkit/VERSION")" 0.1.0 "origin main ahead, on main: VERSION"

echo "=== a resume refuses when origin main has commits HEAD lacks ==="
new_sandbox
hand_release
main_before=$(rev refs/heads/main)
move_origin_main
run --resume
assert_eq "$rc" 1 "resume, origin main ahead: exit status"
assert_contains "$out" "origin/main is not an ancestor of HEAD" "resume, origin main ahead"
assert_eq "$(rev refs/heads/main)" "$main_before" "resume, origin main ahead: local main"

echo "=== a resume refuses a tag whose commit is off HEAD's history ==="
new_sandbox
hand_release
git -C "$repo" reset -q --hard HEAD~1
commit_in_repo toolkit/VERSION 0.2.0
git -C "$repo" merge-base --is-ancestor refs/heads/main v0.2.0 \
    || fail "fixture: main cannot fast-forward to the tag, so git would refuse the move anyway"
if git -C "$repo" merge-base --is-ancestor v0.2.0 HEAD; then
    fail "fixture: the tag is on HEAD's history"
fi
main_before=$(rev refs/heads/main)
origin_before=$(git -C "$repo" ls-remote origin)
run --resume
assert_eq "$rc" 1 "resume, tag off HEAD: exit status"
assert_contains "$out" "v0.2.0 is not on the history of dev" "resume, tag off HEAD"
assert_contains "$out" "git tag -d v0.2.0 dist-v0.2.0" "resume, tag off HEAD: hint re-tags"
assert_eq "$(rev refs/heads/main)" "$main_before" "resume, tag off HEAD: local main"
assert_eq "$(git -C "$repo" ls-remote origin)" "$origin_before" "resume, tag off HEAD: origin refs"
assert_eq "$(rev refs/tags/dist-v0.2.0)" "" "resume, tag off HEAD: no dist tag cut"

echo "=== following the off-history hint finishes the release from the amended tree ==="
new_sandbox
git -C "$repo" worktree add -q "$sandbox/wt" main
run minor
assert_eq "$rc" 1 "hint followed: the release dies at the move"
git -C "$repo" worktree remove --force "$sandbox/wt"
old_dist_tree=$(rev "dist-v0.2.0^{tree}")
printf '# amended manual\n' > "$repo/toolkit/README.md"
git -C "$repo" add toolkit/README.md
git -C "$repo" commit -q --amend --no-edit
[ "$(rev HEAD:toolkit)" != "$old_dist_tree" ] \
    || fail "fixture: the amend left toolkit/ as it was, so a stale dist tag would go unseen"
run --resume
assert_eq "$rc" 1 "hint followed: the amended tree refuses"
hint_commands=$(grep -E '^ +git tag -d ' <<<"$out" || true)
(cd "$repo" && bash -c "$hint_commands") >/dev/null || fail "hint followed: the printed commands failed: $hint_commands"
run --resume
assert_eq "$rc" 0 "hint followed: exit status"
git -C "$repo" merge-base --is-ancestor v0.2.0 HEAD \
    || fail "hint followed: v0.2.0 is not on HEAD's history"
assert_eq "$(rev "dist-v0.2.0^{tree}")" "$(rev v0.2.0:toolkit)" "hint followed: dist tree is the tag's toolkit"

echo "=== a resume leaves main past the tag where it is ==="
new_sandbox
complete_release
commit_in_repo later.md "after the release"
later_sha=$(rev HEAD)
git -C "$repo" branch -f main HEAD
git -C "$repo" push -q origin main
before=$(git -C "$repo" ls-remote origin)
run --resume
after=$(git -C "$repo" ls-remote origin)
assert_eq "$rc" 0 "main past tag: exit status"
assert_contains "$out" "is already complete" "main past tag"
assert_eq "$(rev refs/heads/main)" "$later_sha" "main past tag: local main"
assert_eq "$after" "$before" "main past tag: origin refs"
assert_on_dev "main past tag"

echo "=== a resume from main publishes the tag, not HEAD ==="
new_sandbox
git -C "$repo" checkout -q main
hand_release
commit_in_repo later.md "after the release"
later_sha=$(rev HEAD)
run --resume
assert_eq "$rc" 0 "resume on main past tag: exit status"
assert_eq "$(origin_sha refs/heads/main)" "$release_sha" "resume on main past tag: origin main"
assert_eq "$(rev refs/heads/main)" "$later_sha" "resume on main past tag: local main"

echo "=== a resume after a failed push, main already at the tag ==="
new_sandbox
hand_release
git -C "$repo" branch -f main HEAD
run --resume
assert_eq "$rc" 0 "resume, main at tag: exit status"
assert_eq "$(origin_sha refs/heads/main)" "$release_sha" "resume, main at tag: origin main"
assert_tag v0.2.0 origin "resume, main at tag"
assert_tag dist-v0.2.0 origin "resume, main at tag"
assert_on_dev "resume, main at tag"
new_sandbox
hand_release
git -C "$repo" branch -f main HEAD
commit_in_repo later.md "after the release"
run --resume
assert_eq "$rc" 0 "resume, main at tag, later commit: exit status"
assert_eq "$(origin_sha refs/heads/main)" "$release_sha" "resume, main at tag, later commit: origin main"
assert_eq "$(rev refs/heads/main)" "$release_sha" "resume, main at tag, later commit: local main"
assert_on_dev "resume, main at tag, later commit"

echo "=== another worktree holding main stops the release before origin ==="
new_sandbox
git -C "$repo" worktree add -q "$sandbox/wt" main
main_before=$(origin_sha refs/heads/main)
run minor
assert_eq "$rc" 1 "worktree holds main: exit status"
assert_contains "$out" "just resume-release" "worktree holds main"
assert_eq "$(origin_sha refs/heads/main)" "$main_before" "worktree holds main: origin main"
assert_eq "$(origin_sha refs/tags/v0.2.0)" "" "worktree holds main: tag on origin"
assert_eq "$(origin_sha refs/tags/dist-v0.2.0)" "" "worktree holds main: dist tag on origin"

echo "=== a detached HEAD refuses ==="
new_sandbox
git -C "$repo" checkout -q --detach
run minor
assert_eq "$rc" 1 "detached HEAD: exit status"
assert_contains "$out" "not on a branch" "detached HEAD"
assert_contains "$out" "main or dev" "detached HEAD: names both branches"
refute_tag v0.2.0 "detached HEAD"

if [ "$failures" -eq 0 ]; then
    echo "self-release.sh branch handling: ok"
else
    printf '%d self-release branch check(s) failed\n' "$failures" >&2
    exit 1
fi

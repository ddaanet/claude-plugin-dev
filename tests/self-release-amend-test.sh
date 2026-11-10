#!/usr/bin/env bash
# End-to-end test of scripts/self-release.sh against real git repos in a temp
# dir, for a release commit amended after its tags were cut. No network:
# origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: a release commit amended after its push failed, against
# docs/references/recovery.md's advice not to. A local dist tag cut from the OLD
# toolkit/ tree must not be published for the amended tag: the resume refuses
# and the hint deletes it.
#
# The failed push is real: origin's pre-receive hook rejects while a flag file
# exists, so the fixture is what the script itself leaves behind.
#
# Usage: bash tests/self-release-amend-test.sh   (run from repo root)
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
    # A repo shaped like claude-plugin-dev, released at 0.1.0 from main (both
    # tags pushed), on main. Only main is on origin, and origin refuses pushes
    # while $reject exists.
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/self-release-amend.XXXXXX")"
    sandboxes+=("$sandbox")
    repo="$sandbox/repo"
    reject="$sandbox/reject-push"

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
    printf '#!/bin/sh\n[ ! -f "%s" ] || { echo "push rejected by the fixture" >&2; exit 1; }\n' \
        "$reject" > "$repo-origin.git/hooks/pre-receive"
    chmod +x "$repo-origin.git/hooks/pre-receive"

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
    # $1=path $2=content — an ordinary commit on the checked-out branch.
    printf '%s\n' "$2" > "$repo/$1"
    git -C "$repo" add -A
    git -C "$repo" commit -qm "work: $1"
}

failed_release() {
    # $1=label — `release minor` run for real, its push to main refused. Leaves
    # what the script leaves: the release commit, both tags, local main at it.
    # Also asserts what the dist-tree check rests on: a clean release's dist
    # tag has the tree of the tag's toolkit/.
    : > "$reject"
    run minor
    rm -f "$reject"
    assert_eq "$rc" 1 "$1: the release dies at the push"
    assert_contains "$out" "push of main failed" "$1: the push is what failed"
    old_sha=$(rev "refs/tags/v0.2.0^{commit}")
    [ -n "$old_sha" ] || fail "$1: fixture: no v0.2.0 after the failed release"
    assert_eq "$(rev refs/heads/main)" "$old_sha" "$1: fixture: main fast-forwarded to the release"
    assert_eq "$(rev "dist-v0.2.0^{tree}")" "$(rev v0.2.0:toolkit)" "$1: a clean release's dist tree is the tag's toolkit"
}

amend_release() {
    # Amends the release commit on the checked-out branch so toolkit/ differs,
    # and re-tags v0.2.0 on it by hand, as recovery.md advises against. The
    # suite runs on main, so the amend moves main with HEAD; dist-v0.2.0 is
    # left on the tree split before the amend.
    local old_toolkit
    old_toolkit=$(rev v0.2.0:toolkit)
    printf '# amended manual\n' > "$repo/toolkit/README.md"
    git -C "$repo" add toolkit/README.md
    git -C "$repo" commit -q --amend --no-edit
    git -C "$repo" tag -d v0.2.0 >/dev/null
    git -C "$repo" tag -a v0.2.0 -m "Release 0.2.0"
    [ "$(rev HEAD:toolkit)" != "$old_toolkit" ] \
        || fail "fixture: the amend left toolkit/ as it was, so a stale dist tag would go unseen"
    assert_eq "$(rev "refs/tags/v0.2.0^{commit}")" "$(rev HEAD)" "fixture: v0.2.0 re-tagged on the amended commit"
}

echo "=== a stale local dist tag is refused, with a hint that deletes it ==="
new_sandbox
failed_release "stale local dist"
amend_release
origin_before=$(git -C "$repo" ls-remote origin)
run --resume
assert_eq "$rc" 1 "stale local dist: exit status"
assert_contains "$out" "dist-v0.2.0" "stale local dist: the refusal names the dist tag"
assert_contains "$out" "git tag -d dist-v0.2.0" "stale local dist: hint deletes the local dist tag"
assert_contains "$out" "just resume-release" "stale local dist: hint says to re-run"
assert_eq "$(git -C "$repo" ls-remote origin)" "$origin_before" "stale local dist: nothing was pushed"

echo "=== following the hint finishes with a dist tag of the amended toolkit ==="
new_sandbox
failed_release "stale local dist, hint followed"
amend_release
run --resume
assert_eq "$rc" 1 "hint followed: the stale dist tag refuses"
hint_commands=$(grep -E '^ +git tag -d ' <<<"$out" || true)
[ -n "$hint_commands" ] || fail "hint followed: the refusal printed no 'git tag -d' command"
(cd "$repo" && bash -c "$hint_commands") >/dev/null \
    || fail "hint followed: the printed command failed: $hint_commands"
run --resume
assert_eq "$rc" 0 "hint followed: exit status"
assert_eq "$(rev "dist-v0.2.0^{tree}")" "$(rev HEAD:toolkit)" "hint followed: dist tree is the amended toolkit"
assert_eq "$(origin_sha refs/tags/dist-v0.2.0)" "$(rev refs/tags/dist-v0.2.0)" "hint followed: dist tag published"
assert_eq "$(origin_sha refs/heads/main)" "$(rev HEAD)" "hint followed: origin main is the amended commit"

echo "=== a dist tag matching its tag is kept when HEAD's toolkit/ moved on ==="
new_sandbox
failed_release "matching dist"
dist_before=$(rev refs/tags/dist-v0.2.0)
commit_in_repo toolkit/later.md "after the release, inside toolkit/"
run --resume
assert_eq "$rc" 0 "matching dist, later toolkit work: exit status"
assert_eq "$(rev refs/tags/dist-v0.2.0)" "$dist_before" "matching dist, later toolkit work: the dist tag is kept"
assert_eq "$(origin_sha refs/tags/dist-v0.2.0)" "$dist_before" "matching dist, later toolkit work: published"

if [ "$failures" -eq 0 ]; then
    echo "self-release.sh amended-release handling: ok"
else
    printf '%d self-release amended-release check(s) failed\n' "$failures" >&2
    exit 1
fi

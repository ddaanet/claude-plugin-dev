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

echo "=== happy path: minor bump publishes everything ==="
new_sandbox
run minor
assert_eq "$rc" 0 "happy: exit status"
assert_contains "$out" "Release v0.2.0 complete" "happy: final line"
assert_eq "$(cat "$repo/toolkit/VERSION")" "0.2.0" "happy: VERSION file"
git -C "$repo" diff --quiet HEAD || fail "happy: tree left dirty"
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

echo "=== resume after later work on main ==="
new_sandbox
block_push
run minor
unblock_push
commit_in_repo docs.md "written after the release commit"
run --resume
assert_eq "$rc" 0 "resume after work: exit status"
assert_tag dist-v0.2.0 origin "resume after work"
# Split from the tag, not HEAD: the dist tree must not carry later work, and
# would not even see it here -- docs.md is outside toolkit/. What it proves is
# that the split ran against the tagged commit at all.
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
assert_contains "$out" "no release was started at 0.1.0" "resume, no tag anywhere: hint"
assert_contains "$out" "just release <bump>" "resume, no tag anywhere: remedy"

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
assert_contains "$out" "uncommitted changes" "dirty tree"
git -C "$repo" checkout -q -- ROOT-ONLY.md
# .claude/ and memory/ are excluded from that check, the way this repo needs.
mkdir -p "$repo/.claude"
printf 'task frame\n' > "$repo/.claude/handoff-task.md"
run minor
assert_eq "$rc" 0 ".claude/ is excluded from the clean check"

new_sandbox
git -C "$repo" checkout -q -b side
run minor
assert_contains "$out" "must be on main (currently side)" "wrong branch"

new_sandbox
printf '0.2\n' > "$repo/toolkit/VERSION"
git -C "$repo" commit -qam "bad version"
run minor
assert_contains "$out" "toolkit/VERSION is not X.Y.Z" "malformed VERSION"
new_sandbox
printf '0.08.0\n' > "$repo/toolkit/VERSION"
git -C "$repo" commit -qam "padded version"
run minor
assert_contains "$out" "toolkit/VERSION is not X.Y.Z" "zero-padded VERSION"

new_sandbox
printf '0.2.0\n' > "$repo/toolkit/VERSION"
git -C "$repo" commit -qam "hand-written bump"
run minor
assert_contains "$out" "does not match latest tag (v0.1.0)" "hand-written bump"
assert_contains "$out" "holds the LAST released version" "hand-written bump: hint"

# The dist lineage, because `git describe --match 'v*'` ignores it: a squatting
# v0.2.0 reachable from HEAD is caught one guard earlier, by the drift check.
new_sandbox
git -C "$repo" tag -a dist-v0.2.0 -m "squatter"
run minor
assert_contains "$out" "tag dist-v0.2.0 already exists" "tag squatting"

new_sandbox
run sideways
assert_contains "$out" "unknown bump type: sideways" "bad argument"
run --wat
assert_contains "$out" "unknown option: --wat" "bad option"
run minor patch
assert_contains "$out" "too many arguments" "extra argument"

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

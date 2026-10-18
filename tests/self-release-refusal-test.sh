#!/usr/bin/env bash
# End-to-end test of scripts/self-release.sh against real git repos in a temp
# dir. No network: origins are local bare repos and `gh` is a stub on PATH.
#
# The fixture is shaped like this repo -- a toolkit/ subdirectory that gets
# split into a dist- tag, plus root-only files that must NOT reach it -- rather
# than like a consumer plugin, which is what the tests/release-*-test.sh suites
# cover.
#
# Scope: what the script refuses -- resume refusals, a moved published tag,
# preflight refusals, an unreadable origin. Its sibling
# self-release-publish-test.sh covers the publishing and resume path.
#
# Usage: bash tests/self-release-refusal-test.sh   (run from repo root)
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
assert_not_contains() {
    # $1=haystack $2=needle $3=label
    # Residual bound: the needle is a grep BRE matched line by line --
    # a metacharacter in it is live, and a needle that spans a newline
    # can never match.
    # A here-string, never a pipe: under pipefail grep -q exits on its first
    # match, the writer can take SIGPIPE, and the pipeline reports failure.
    if grep -q -- "$2" <<<"$1"; then
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
    # stage_handoff_frame in tests/release-tree-test.sh.
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
# common_preflight's `git diff --quiet HEAD -- . ':(exclude)memory'` sees
# tracked content only, so an absent memory/ directory would never reach the
# check either way -- proving the exclusion requires constructing a real diff
# under it for the exclusion to suppress, not merely creating the path.
stage_memory_gitlink "$repo" "$sandbox"
run minor
assert_eq "$rc" 0 "memory/ is exempted from the clean check"

# .claude/ is not exempt: a staged frame is a tracked difference from HEAD like
# any other, and the refusal names it.
new_sandbox
stage_claude_frame "$repo"
run minor
assert_eq "$rc" 1 "staged .claude/ frame: exit status"
assert_contains "$out" "uncommitted changes" "staged .claude/ frame"
refute_tag v0.2.0 "staged .claude/ frame"
assert_gh_untouched "staged .claude/ frame"

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
# The refusal is the probe failure itself. A failed ls-remote is not evidence
# that the tags are absent, so neither the missing-list hint nor the "unfinished"
# verdict may appear -- they would name v0.1.0, dist-v0.1.0 and the GitHub
# release as unpublished when all three are.
assert_contains "$out" "git ls-remote origin refs/tags/v0.1.0 failed" "dead origin: names the probe failure"
assert_not_contains "$out" "not fully published. Missing:" "dead origin: no missing-list hint"
assert_not_contains "$out" "is unfinished" "dead origin: no unfinished verdict"
refute_tag v0.2.0 "dead origin"
assert_gh_untouched "dead origin"
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
# The no-tag hint probes origin to pick its wording; an unreadable origin must
# refuse as the probe failure, not claim "no release was started".
new_sandbox
git -C "$repo" tag -d v0.1.0 >/dev/null
git -C "$repo" remote set-url origin "$sandbox/does-not-exist.git"
run --resume
assert_eq "$rc" 1 "dead origin, no local tag: exit status"
assert_contains "$out" "git ls-remote origin refs/tags/v0.1.0 failed" "dead origin, no local tag: names the probe failure"
assert_not_contains "$out" "no release was started" "dead origin, no local tag: no guessed hint"

if [ "$failures" -eq 0 ]; then
    echo "self-release.sh: ok"
else
    printf '%d self-release check(s) failed\n' "$failures" >&2
    exit 1
fi

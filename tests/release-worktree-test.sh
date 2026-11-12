#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir, for a
# `main` checked out in another worktree. No network: origins are local bare
# repos and `gh` is a stub on PATH.
#
# Scope: releasing from `dev` moves local `main` with `git fetch . <sha>:main`,
# which git refuses while another worktree holds `main`. A release from dev in
# that state refuses before any commit or tag, whether `main` is checked out
# there or held by an interrupted rebase that porcelain shows as `detached`:
# git's own refusal, naming the worktree, stays visible, the hint says to run
# the same command again, and once `main` is freed that command completes with
# the other worktree's work intact. A worktree whose directory was deleted is
# refused the same way, and once the fixture prunes it the release completes.
# The worktree's path holds a space. A
# release from `main` in the current worktree is unaffected, and so is the
# resume side: a resume with `main` held elsewhere and already at the release
# commit completes. Its state is built by hand with git and jq, so no script
# under test sets up another's scenario.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group,
# and release-branch-test.sh for the other release-from-dev refusals.
#
# Usage: bash tests/release-worktree-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo via `-C`, never this
# repo, so it's always safe to drop them here.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

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
    # $1=haystack $2=needle $3=label (same residual bound as assert_contains)
    if grep -q -- "$2" <<<"$1"; then
        fail "$3: output contained '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
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

# out/rc from the last run_in call.
out=""
rc=0
run_in() {
    # $1=dir, rest=command. Captures stdout+stderr in $out, status in $rc.
    local dir="$1"
    shift
    set +e
    out="$(cd "$dir" && "$@" 2>&1)"
    rc=$?
    set -e
}

git_init() {
    # $1=path. A repo with a deterministic identity and a bare origin.
    git init -q -b main "$1"
    git -C "$1" config user.email test@example.com
    git -C "$1" config user.name "Toolkit Test"
    git -C "$1" config commit.gpgsign false
    git init -q --bare -b main "$1-origin.git"
    git -C "$1" remote add origin "$1-origin.git"
}

new_sandbox() {
    # Sets $sandbox, $plugin, $marketplace; exports MARKETPLACE_DIR, PATH, GH_*.
    # The plugin is released at 1.2.3 and its marketplace entry is at 1.2.3.
    # Physical spelling: macOS $TMPDIR sits under a symlink, and git records a
    # worktree's path with symlinks resolved, so $wt must be spelled the same.
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/release-worktree.XXXXXX")" || exit 1
    sandbox="$(cd "$sandbox" && pwd -P)"
    sandboxes+=("$sandbox")
    plugin="$sandbox/plugin"
    marketplace="$sandbox/marketplace"

    # gh stub: records every call, and "remembers" created releases as marker
    # files so `release view` can answer truthfully on a second run.
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

    # Fixture plugin, vendoring the toolkit the way a consumer does.
    git_init "$plugin"
    mkdir -p "$plugin/.claude-plugin" "$plugin/plugin-dev"
    cat > "$plugin/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.2.3",
  "description": "test fixture",
  "license": "MIT"
}
JSON
    cp "$repo_root"/toolkit/*.sh "$plugin/plugin-dev/"
    git -C "$plugin" add -A
    git -C "$plugin" commit -qm "init"
    git -C "$plugin" tag -a v1.2.3 -m "Release 1.2.3"
    git -C "$plugin" push -q -u origin main
    git -C "$plugin" push -q origin v1.2.3
    git -C "$plugin" remote set-head origin main

    # Fixture marketplace.
    git_init "$marketplace"
    mkdir -p "$marketplace/.claude-plugin"
    jq -n '{plugins: [{name: "fixture", source: {source: "github", repo: "o/fixture"}, version: "1.2.3"}]}' \
        > "$marketplace/.claude-plugin/marketplace.json"
    git -C "$marketplace" add -A
    git -C "$marketplace" commit -qm "init"
    git -C "$marketplace" push -q -u origin main
    export MARKETPLACE_DIR="$marketplace"
    origin_before="$(origin_rev refs/heads/main)"
}

market_version() {
    jq -r '.plugins[] | select(.name=="fixture") | .version' \
        "$marketplace/.claude-plugin/marketplace.json"
}

rev() {
    # $1=a revision in the plugin repo. Prints its sha, empty when it does not
    # resolve. Never fails: a missing ref is a value for an assertion to judge,
    # not a reason for `set -e` to end the suite.
    git -C "$plugin" rev-parse -q --verify "$1" || true
}
origin_rev() {
    # $1=a revision in the bare origin, read from the bare repo itself and never
    # through the clone's remote-tracking refs. Prints its sha, empty if absent.
    git -C "$plugin-origin.git" rev-parse -q --verify "$1" || true
}
branch_now() {
    git -C "$plugin" symbolic-ref -q --short HEAD || true
}

to_dev() {
    # Branches `dev` off main with one commit, never pushed: the state a release
    # from dev starts in.
    git -C "$plugin" checkout -q -b dev
    printf 'work on dev\n' > "$plugin/dev-work.md"
    git -C "$plugin" add -A
    git -C "$plugin" commit -qm "work: dev-work.md"
}

main_elsewhere() {
    # Checks `main` out in a second worktree, whose path holds a space, with an
    # untracked file standing for work in progress there. Sets $wt.
    wt="$sandbox/main wt"
    git -C "$plugin" worktree add -q "$wt" main
    printf 'in progress\n' > "$wt/notes.md"
}

wt_intact() {
    # $1=label. The other worktree is still there, with its work in progress.
    [ -f "$wt/notes.md" ] || fail "$1: the other worktree's untracked file is gone"
    assert_eq "$(git -C "$plugin" worktree list --porcelain | grep -c "^worktree $wt\$" || true)" "1" \
        "$1: the other worktree is still registered"
}

released() {
    # $1=label. The release of v1.2.4 from dev finished: main local and on origin
    # at the tag's commit, the tag and the GitHub release published, the
    # marketplace bumped, dev checked out and never pushed.
    local tag_commit
    assert_eq "$rc" "0" "$1: exit status"
    tag_commit="$(rev 'refs/tags/v1.2.4^{commit}')"
    [ -n "$tag_commit" ] || fail "$1: tag v1.2.4 does not resolve to a commit"
    assert_eq "$(rev refs/heads/main)" "$tag_commit" "$1: local main at the tag's commit"
    assert_eq "$(origin_rev refs/heads/main)" "$tag_commit" "$1: origin main at the tag's commit"
    assert_eq "$(origin_rev 'refs/tags/v1.2.4^{commit}')" "$tag_commit" "$1: tag on origin"
    assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "$1: GitHub release created"
    assert_eq "$(market_version)" "1.2.4" "$1: marketplace bumped"
    assert_contains "$out" "Release v1.2.4 complete" "$1: summary"
    assert_eq "$(branch_now)" "dev" "$1: HEAD branch unchanged"
    assert_eq "$(origin_rev refs/heads/dev)" "" "$1: dev not on origin"
}

untouched() {
    # $1=label. Nothing moved: local main where it was, origin's main and tags,
    # the GitHub releases and the marketplace as the fixture left them.
    assert_eq "$rc" "1" "$1: exit status"
    assert_eq "$(rev refs/heads/main)" "$main_before" "$1: local main not moved"
    assert_eq "$(origin_rev refs/heads/main)" "$origin_before" "$1: origin main untouched"
    assert_eq "$(origin_rev refs/tags/v1.2.4)" "" "$1: no tag on origin"
    assert_not_contains "$(cat "$GH_LOG")" "release create" "$1: no GitHub release"
    assert_eq "$(market_version)" "1.2.3" "$1: marketplace untouched"
    assert_eq "$(branch_now)" "dev" "$1: HEAD branch unchanged"
}

refused_clean() {
    # $1=label. The refusal of a release from dev with main held in $wt, made
    # before any commit or tag: nothing moved, git's own line is left visible,
    # the worktree is named, and the way out is the same command once main is
    # free. No tag exists, so a resume has nothing to finish.
    untouched "$1"
    assert_eq "$(rev HEAD)" "$head_before" "$1: no commit made"
    assert_eq "$(rev refs/tags/v1.2.4)" "" "$1: no local tag"
    assert_contains "$out" "$wt" "$1: names the other worktree"
    assert_contains "$out" "fatal:" "$1: git's own refusal is left visible"
    assert_contains "$out" "run the same command again" "$1: says to run the same command again"
    assert_not_contains "$out" "resume-release" "$1: does not send to a resume"
}

echo "=== a release from dev with main checked out in another worktree refuses before any commit ==="
new_sandbox
to_dev
main_elsewhere
main_before="$(rev refs/heads/main)"
head_before="$(rev HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
refused_clean "release, main elsewhere"
# The fixture frees main as the hint says, then the same command completes.
git -C "$wt" switch -q --detach
run_in "$plugin" bash plugin-dev/release.sh patch
released "release, main elsewhere: after main is freed"
wt_intact "release, main elsewhere: after the release"

echo "=== a release from dev with main held by a deleted worktree refuses until it is pruned ==="
# The worktree's directory is gone but it is still registered, so git still
# refuses. The fixture frees main by pruning the registration.
new_sandbox
to_dev
main_elsewhere
rm -rf "$wt"
main_before="$(rev refs/heads/main)"
head_before="$(rev HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
refused_clean "release, main in a deleted worktree"
git -C "$plugin" worktree prune
run_in "$plugin" bash plugin-dev/release.sh patch
released "release, main in a deleted worktree: after the prune"

echo "=== a release from main in this worktree, dev checked out in another, completes ==="
new_sandbox
to_dev
git -C "$plugin" checkout -q main
git -C "$plugin" worktree add -q "$sandbox/dev wt" dev
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "release from main, dev elsewhere: exit status"
rel="$(rev 'refs/tags/v1.2.4^{commit}')"
[ -n "$rel" ] || fail "release from main, dev elsewhere: tag v1.2.4 does not resolve to a commit"
assert_eq "$(rev refs/heads/main)" "$rel" "release from main, dev elsewhere: local main at the release"
assert_eq "$(origin_rev refs/heads/main)" "$rel" "release from main, dev elsewhere: origin main at the release"
assert_eq "$(origin_rev 'refs/tags/v1.2.4^{commit}')" "$rel" "release from main, dev elsewhere: tag on origin"
assert_eq "$(market_version)" "1.2.4" "release from main, dev elsewhere: marketplace bumped"
assert_eq "$(branch_now)" "main" "release from main, dev elsewhere: HEAD branch unchanged"

echo "=== a release from dev with main held by an interrupted rebase elsewhere refuses before any commit ==="
# The rebase leaves the other worktree on a detached HEAD, so `git worktree list
# --porcelain` no longer says `branch refs/heads/main`, yet git still refuses to
# fetch into main. Main's tip is an ancestor of dev, so the ancestor refusals do
# not fire: only asking git itself catches this.
new_sandbox
to_dev
main_elsewhere
git -C "$wt" switch -q -c other
printf 'other\n' > "$wt/conflict.md"
git -C "$wt" add conflict.md
git -C "$wt" commit -qm "other: conflict.md"
git -C "$wt" switch -q main
printf 'main\n' > "$wt/conflict.md"
git -C "$wt" add conflict.md
git -C "$wt" commit -qm "main: conflict.md"
git -C "$plugin" merge -q --no-edit main
run_in "$wt" git rebase other
assert_eq "$rc" "1" "rebase fixture: the rebase stops on the conflict"
wt_block="$(git -C "$plugin" worktree list --porcelain \
    | awk -v w="worktree $wt" 'BEGIN { RS = "" } index($0, w "\n") == 1')"
assert_contains "$wt_block" "^detached\$" "rebase fixture: the other worktree shows detached"
assert_not_contains "$wt_block" "branch refs/heads/main" "rebase fixture: porcelain does not name main"
run_in "$plugin" git fetch . refs/heads/main:refs/heads/main
assert_eq "$rc" "128" "rebase fixture: git itself refuses to fetch into main"
main_before="$(rev refs/heads/main)"
head_before="$(rev HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
refused_clean "release, main mid-rebase elsewhere"

echo "=== a resume from dev, main held elsewhere and already at the release commit, completes ==="
# move_main ran before a failed push, then main was checked out elsewhere: the
# resume has nothing to move, so it must not probe main. Built by hand.
new_sandbox
to_dev
jq '.version = "1.2.4"' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" add -A
git -C "$plugin" commit -qm "release: 1.2.4"
git -C "$plugin" tag -a v1.2.4 -m "Release 1.2.4"
git -C "$plugin" branch -f main "$(rev HEAD)"
main_elsewhere
run_in "$plugin" bash plugin-dev/release.sh --resume
released "resume, main elsewhere at the release"
wt_intact "resume, main elsewhere at the release"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release worktree scenarios passed\n'

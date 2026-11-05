#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir, for the
# branch it releases from. No network: origins are local bare repos and `gh` is
# a stub on PATH.
#
# Scope: releasing a consumer plugin from `dev` as well as `main`. The release
# moves main to the release commit and leaves dev checked out and unpublished;
# a first release from dev; the branch refusals; local `main` or `origin/main`
# holding a commit HEAD lacks; an origin with no `main`; a clone with no local
# `main`.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size), and
# release-branch-resume-test.sh and release-branch-moved-test.sh for the
# resume and moved-origin halves of the same contract.
#
# Usage: bash tests/release-branch-test.sh   (run from repo root)
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
    # $1=marketplace entry version, or "" for no entry (first publication).
    # Sets $sandbox, $plugin, $marketplace; exports MARKETPLACE_DIR, PATH, GH_*.
    local entry_version="$1"
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/release-branch.XXXXXX")"
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
    if [ -n "$entry_version" ]; then
        jq -n --arg v "$entry_version" \
            '{plugins: [{name: "fixture", source: {source: "github", repo: "o/fixture"}, version: $v}]}' \
            > "$marketplace/.claude-plugin/marketplace.json"
    else
        jq -n '{plugins: []}' > "$marketplace/.claude-plugin/marketplace.json"
    fi
    git -C "$marketplace" add -A
    git -C "$marketplace" commit -qm "init"
    git -C "$marketplace" push -q -u origin main
    export MARKETPLACE_DIR="$marketplace"
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
    # from dev starts in. Sets $dev_head.
    git -C "$plugin" checkout -q -b dev
    printf 'work on dev\n' > "$plugin/dev-work.md"
    git -C "$plugin" add -A
    git -C "$plugin" commit -qm "work: dev-work.md"
    dev_head="$(rev HEAD)"
}

after_release() {
    # $1=label. What every successful release from dev leaves: the branch it
    # started on checked out, dev never published.
    assert_eq "$(branch_now)" "dev" "$1: HEAD branch unchanged"
    assert_eq "$(origin_rev refs/heads/dev)" "" "$1: dev not on origin"
}

make_virgin() {
    # $1=manifest version. Strips the fixture's release history so the plugin
    # has never been released: no v* tags locally or on origin, and the manifest
    # seeded at $1. Paired with new_sandbox "" (no marketplace entry).
    git -C "$plugin" tag -d v1.2.3 >/dev/null
    git -C "$plugin" push -q origin :refs/tags/v1.2.3
    jq --arg v "$1" '.version = $v' "$plugin/.claude-plugin/plugin.json" \
        > "$plugin/.claude-plugin/plugin.json.tmp"
    mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
    git -C "$plugin" add -A
    if ! git -C "$plugin" diff --cached --quiet; then
        git -C "$plugin" commit -qm "scaffold at $1"
    fi
    git -C "$plugin" push -q origin main
}

writer_clone() {
    # A second clone of origin acting as another writer. Sets $other.
    other="$sandbox/other"
    git clone -q "$plugin-origin.git" "$other"
    git -C "$other" config user.email test@example.com
    git -C "$other" config user.name "Toolkit Test"
    git -C "$other" config commit.gpgsign false
}
writer_push() {
    # Commits a file in the other writer's clone and pushes it to origin's main.
    # Sets $other_sha. The plugin clone never fetches it by itself.
    printf 'only on origin\n' > "$other/origin-only.md"
    git -C "$other" add -A
    git -C "$other" commit -qm "work: origin-only.md"
    git -C "$other" push -q origin main
    other_sha="$(git -C "$other" rev-parse HEAD)"
}

refused_clean() {
    # $1=label $2=head before. A refused release leaves no commit, no tag and
    # nothing on origin.
    assert_eq "$rc" "1" "$1: exit status"
    assert_eq "$(rev HEAD)" "$2" "$1: no commit made"
    assert_eq "$(rev 'refs/tags/v1.2.4')" "" "$1: no local tag"
    assert_eq "$(origin_rev refs/tags/v1.2.4)" "" "$1: no tag on origin"
    assert_not_contains "$(cat "$GH_LOG")" "release create" "$1: no GitHub release"
}

echo "=== a release from dev: main moves to the release commit, dev stays home ==="
new_sandbox "1.2.3"
to_dev
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "release from dev: exit status"
rel="$(rev 'refs/tags/v1.2.4^{commit}')"
[ -n "$rel" ] || fail "release from dev: tag v1.2.4 does not resolve to a commit"
assert_eq "$(rev refs/heads/main)" "$rel" "release from dev: local main at the release"
assert_eq "$(origin_rev refs/heads/main)" "$rel" "release from dev: origin main at the release"
assert_eq "$(rev HEAD)" "$rel" "release from dev: HEAD is the release commit"
assert_eq "$(origin_rev 'refs/tags/v1.2.4^{commit}')" "$rel" "release from dev: tag on origin at the release"
assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "release from dev: GitHub release created"
assert_eq "$(market_version)" "1.2.4" "release from dev: marketplace bumped"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.4" "release from dev: manifest bumped"
after_release "release from dev"

echo "=== a first release from dev ==="
new_sandbox ""
make_virgin "0.1.0"
to_dev
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "0" "first release from dev: exit status"
assert_eq "$(rev 'refs/tags/v0.1.0^{commit}')" "$dev_head" "first release from dev: tags HEAD"
assert_eq "$(rev refs/heads/main)" "$dev_head" "first release from dev: local main at HEAD"
assert_eq "$(origin_rev refs/heads/main)" "$dev_head" "first release from dev: origin main at HEAD"
assert_eq "$(origin_rev 'refs/tags/v0.1.0^{commit}')" "$dev_head" "first release from dev: tag on origin"
assert_eq "$(market_version)" "0.1.0" "first release from dev: marketplace entry created"
after_release "first release from dev"

echo "=== another branch refuses, naming main and dev ==="
new_sandbox "1.2.3"
to_dev
git -C "$plugin" checkout -q -b side
head_before="$(rev HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
refused_clean "branch side" "$head_before"
assert_contains "$out" "main" "branch side: names the main branch"
assert_contains "$out" "dev" "branch side: names dev"
assert_contains "$out" "side" "branch side: names where it is"
assert_eq "$(branch_now)" "side" "branch side: checkout unchanged"

echo "=== a detached HEAD refuses, naming main and dev ==="
git -C "$plugin" checkout -q --detach
head_before="$(rev HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
refused_clean "detached HEAD" "$head_before"
assert_contains "$out" "main" "detached HEAD: names the main branch"
assert_contains "$out" "dev" "detached HEAD: names dev"

echo "=== local main holding a commit HEAD lacks refuses ==="
new_sandbox "1.2.3"
to_dev
git -C "$plugin" checkout -q main
printf 'only on main\n' > "$plugin/main-only.md"
git -C "$plugin" add -A
git -C "$plugin" commit -qm "work: main-only.md"
main_head="$(rev HEAD)"
git -C "$plugin" checkout -q dev
head_before="$(rev HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
refused_clean "local main ahead" "$head_before"
assert_contains "$out" "git merge main" "local main ahead: hint names the merge"
assert_eq "$(rev refs/heads/main)" "$main_head" "local main ahead: main not moved"
assert_eq "$(origin_rev refs/heads/main)" "$(rev refs/remotes/origin/main)" "local main ahead: origin main untouched"

echo "=== origin/main holding a commit HEAD lacks refuses ==="
new_sandbox "1.2.3"
to_dev
writer_clone
writer_push
head_before="$(rev HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
refused_clean "origin main ahead" "$head_before"
assert_contains "$out" "git merge origin/main" "origin main ahead: hint names the merge"
assert_eq "$(origin_rev refs/heads/main)" "$other_sha" "origin main ahead: origin main untouched"
assert_not_contains "$(git -C "$plugin" log --format=%H refs/heads/main)" "$other_sha" "origin main ahead: local main did not take it"

echo "=== an origin with no main releases, and says so ==="
new_sandbox "1.2.3"
to_dev
git -C "$plugin-origin.git" update-ref -d refs/heads/main
git -C "$plugin" update-ref -d refs/remotes/origin/main
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "origin without main: exit status"
rel="$(rev 'refs/tags/v1.2.4^{commit}')"
[ -n "$rel" ] || fail "origin without main: tag v1.2.4 does not resolve to a commit"
assert_eq "$(origin_rev refs/heads/main)" "$rel" "origin without main: main created at the release"
assert_eq "$(rev refs/heads/main)" "$rel" "origin without main: local main at the release"
# The wording is the green phase's; the note must say origin has no main.
if ! grep -qiE 'origin.*(no|without|lacks|missing|has not|does not have).*main|(no|without|missing).*main.*origin' <<<"$out"; then
    fail "origin without main: no note saying origin has no main branch"
    printf '  --- output ---\n%s\n  --------------\n' "$out" >&2
fi
after_release "origin without main"

echo "=== a clone with no local main releases from dev, and main is created ==="
new_sandbox "1.2.3"
to_dev
git -C "$plugin" branch -q -D main
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "no local main: exit status"
rel="$(rev 'refs/tags/v1.2.4^{commit}')"
[ -n "$rel" ] || fail "no local main: tag v1.2.4 does not resolve to a commit"
assert_eq "$(rev refs/heads/main)" "$rel" "no local main: local main created at the release"
assert_eq "$(origin_rev refs/heads/main)" "$rel" "no local main: origin main at the release"
assert_not_contains "$out" "fatal:" "no local main: no git fatal in the output"
after_release "no local main"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release branch scenarios passed\n'

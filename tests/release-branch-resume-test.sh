#!/usr/bin/env bash
# End-to-end test of release.sh --resume against real git repos in a temp dir,
# for a release cut from `dev`. No network: origins are local bare repos and
# `gh` is a stub on PATH.
#
# Scope: a resume after later dev commits publishes the tag's commit, never
# HEAD; a resume of a complete release pushes nothing; origin moving after the
# push does not block the resume and needs no merge; a tag off HEAD's history
# refuses, with the hint matching the state. Each state is built by hand with
# git and jq, so no script under test sets up another's scenario.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size), and
# release-branch-test.sh and release-branch-moved-test.sh for the release-mode
# and moved-origin halves of the same contract.
#
# Usage: bash tests/release-branch-resume-test.sh   (run from repo root)
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
    # from dev starts in.
    git -C "$plugin" checkout -q -b dev
    printf 'work on dev\n' > "$plugin/dev-work.md"
    git -C "$plugin" add -A
    git -C "$plugin" commit -qm "work: dev-work.md"
}

after_release() {
    # $1=label. What every successful release from dev leaves: the branch it
    # started on checked out, dev never published.
    assert_eq "$(branch_now)" "dev" "$1: HEAD branch unchanged"
    assert_eq "$(origin_rev refs/heads/dev)" "" "$1: dev not on origin"
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

hand_release() {
    # $1=version. The release commit and tag release.sh would cut, built by hand
    # on the current branch, so the resume scenarios depend on no script under
    # test to set up. Sets $rel to the release commit.
    jq --arg v "$1" '.version = $v' "$plugin/.claude-plugin/plugin.json" \
        > "$plugin/.claude-plugin/plugin.json.tmp"
    mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
    git -C "$plugin" add .claude-plugin/plugin.json
    git -C "$plugin" commit -qm "release: $1"
    git -C "$plugin" tag -a "v$1" -m "Release $1"
    rel="$(rev HEAD)"
}
later_commit() {
    # A dev commit after the release commit. Sets $later.
    printf 'later work\n' > "$plugin/later.md"
    git -C "$plugin" add -A
    git -C "$plugin" commit -qm "work: later.md"
    later="$(rev HEAD)"
}

publish_by_hand() {
    # Pushes the release commit and tag to origin the way a finished push does.
    git -C "$plugin" push -q origin "$rel:refs/heads/main"
    git -C "$plugin" push -q origin "v1.2.4"
}

echo "=== a resume after a later dev commit leaves origin's main at the tag's commit ==="
new_sandbox "1.2.3"
to_dev
hand_release "1.2.4"
later_commit
main_before="$(origin_rev refs/heads/main)"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "resume past later commit: exit status"
assert_eq "$(origin_rev refs/heads/main)" "$rel" "resume past later commit: origin main at the tag's commit"
assert_eq "$(rev refs/heads/main)" "$rel" "resume past later commit: local main at the tag's commit"
assert_eq "$(rev HEAD)" "$later" "resume past later commit: HEAD untouched"
if git -C "$plugin-origin.git" cat-file -e "$later^{commit}" 2>/dev/null; then
    fail "resume past later commit: the later dev commit reached origin"
fi
assert_eq "$(origin_rev 'refs/tags/v1.2.4^{commit}')" "$rel" "resume past later commit: tag on origin"
assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "resume past later commit: GitHub release created"
assert_eq "$(market_version)" "1.2.4" "resume past later commit: marketplace bumped"
assert_contains "$out" "Release v1.2.4 complete" "resume past later commit: summary"
# The push names the revision it uploaded, so a later commit left local is
# visible: the release commit, not HEAD.
assert_contains "$out" "branch main: pushed ${rel:0:7} release: 1.2.4" "resume past later commit: names the pushed revision"
assert_not_contains "$out" "${later:0:7}" "resume past later commit: the later commit is not named as pushed"
after_release "resume past later commit"

echo "=== a resume of a complete release with a later dev commit pushes nothing ==="
new_sandbox "1.2.3"
to_dev
hand_release "1.2.4"
publish_by_hand
git -C "$plugin" branch -f main "$rel"
: > "$GH_RELEASES/v1.2.4"
jq '(.plugins[] | select(.name=="fixture") | .version) = "1.2.4"' \
    "$marketplace/.claude-plugin/marketplace.json" > "$marketplace/m.tmp"
mv "$marketplace/m.tmp" "$marketplace/.claude-plugin/marketplace.json"
git -C "$marketplace" add -A
git -C "$marketplace" commit -qm "bump fixture to 1.2.4"
git -C "$marketplace" push -q origin main
later_commit
market_before="$(git -C "$marketplace-origin.git" rev-parse refs/heads/main)"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "complete release, later commit: exit status"
assert_contains "$out" "already complete (nothing to do)" "complete release, later commit: says nothing to do"
assert_eq "$(origin_rev refs/heads/main)" "$rel" "complete release, later commit: origin main unchanged"
assert_eq "$(origin_rev 'refs/tags/v1.2.4^{commit}')" "$rel" "complete release, later commit: tag unchanged"
assert_eq "$(rev HEAD)" "$later" "complete release, later commit: HEAD untouched"
assert_not_contains "$out" "main: pushed" "complete release, later commit: no push reported"
assert_not_contains "$(cat "$GH_LOG")" "release create" "complete release, later commit: no GitHub release made"
assert_eq "$(git -C "$marketplace-origin.git" rev-parse refs/heads/main)" "$market_before" "complete release, later commit: marketplace untouched"
if git -C "$plugin-origin.git" cat-file -e "$later^{commit}" 2>/dev/null; then
    fail "complete release, later commit: the later dev commit reached origin"
fi
after_release "complete release, later commit"

echo "=== origin moved after the push: the resume finishes with no merge ==="
new_sandbox "1.2.3"
to_dev
hand_release "1.2.4"
publish_by_hand
writer_clone
writer_push
head_before="$(rev HEAD)"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "origin moved after push: exit status"
assert_eq "$(rev HEAD)" "$head_before" "origin moved after push: no merge, HEAD untouched"
assert_eq "$(origin_rev refs/heads/main)" "$other_sha" "origin moved after push: origin main not rewound"
assert_eq "$(rev refs/heads/main)" "$rel" "origin moved after push: local main at the tag's commit"
assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "origin moved after push: GitHub release created"
assert_eq "$(market_version)" "1.2.4" "origin moved after push: marketplace bumped"
assert_contains "$out" "Release v1.2.4 complete" "origin moved after push: summary"
assert_not_contains "$out" "main: pushed" "origin moved after push: nothing uploaded, no push reported"
after_release "origin moved after push"

refused_resume() {
    # $1=label $2=head before. A refused resume changes nothing anywhere.
    assert_eq "$rc" "1" "$1: exit status"
    assert_eq "$(rev HEAD)" "$2" "$1: HEAD untouched"
    assert_eq "$(origin_rev refs/tags/v1.2.4)" "" "$1: no tag on origin"
    assert_eq "$(origin_rev refs/heads/main)" "$main_before" "$1: origin main untouched"
    assert_not_contains "$(cat "$GH_LOG")" "release create" "$1: no GitHub release"
}
bump_on_head() {
    # The same version edit as hand_release, committed without a tag: a bump on
    # this branch that the tag does not point at.
    jq '.version = "1.2.4"' "$plugin/.claude-plugin/plugin.json" > "$plugin/m.tmp"
    mv "$plugin/m.tmp" "$plugin/.claude-plugin/plugin.json"
    git -C "$plugin" add .claude-plugin/plugin.json
    git -C "$plugin" commit -qm "bump to 1.2.4 on dev"
    bump_sha="$(rev HEAD)"
}

echo "=== a tag off HEAD's history, local main carrying it: the hint merges main ==="
new_sandbox "1.2.3"
to_dev
git -C "$plugin" checkout -q main
hand_release "1.2.4"
git -C "$plugin" checkout -q dev
bump_on_head
main_before="$(origin_rev refs/heads/main)"
head_before="$(rev HEAD)"
run_in "$plugin" bash plugin-dev/release.sh --resume
refused_resume "tag off history, main carries it" "$head_before"
assert_contains "$out" "git merge main" "tag off history, main carries it: hint merges main"
assert_eq "$(rev 'refs/tags/v1.2.4^{commit}')" "$rel" "tag off history, main carries it: tag not moved"

echo "=== a tag off HEAD's history, main not carrying it: the hint re-tags ==="
new_sandbox "1.2.3"
to_dev
git -C "$plugin" checkout -q -b old main
hand_release "1.2.4"
git -C "$plugin" checkout -q dev
git -C "$plugin" branch -D old >/dev/null
bump_on_head
later_commit
main_before="$(origin_rev refs/heads/main)"
head_before="$(rev HEAD)"
run_in "$plugin" bash plugin-dev/release.sh --resume
refused_resume "tag off history, main lacks it" "$head_before"
assert_contains "$out" "git tag" "tag off history, main lacks it: hint re-tags"
# The last commit that changed the manifest's version line, not HEAD.
assert_contains "$out" "${bump_sha:0:7}" "tag off history, main lacks it: hint names the bump commit"
assert_not_contains "$out" "git merge main" "tag off history, main lacks it: no merge hint"
assert_eq "$(rev 'refs/tags/v1.2.4^{commit}')" "$rel" "tag off history, main lacks it: tag not moved"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release branch resume scenarios passed\n'

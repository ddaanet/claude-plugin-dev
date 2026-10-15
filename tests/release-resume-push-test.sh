#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: --resume completing a release whose push was rejected, whose
# marketplace push was rejected, or whose first publication was, and refusing to
# move a tag origin already has elsewhere.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-resume-push-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d)"
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

echo "=== resume: completes a release whose push was rejected ==="
new_sandbox "1.2.3"
# A pre-push hook that refuses, reproducing the gitlore 0.4.3 failure: the
# recipe dies after the irreversible commit and tag, before the tag push.
cat > "$plugin/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
echo "pre-push: refusing" >&2
exit 1
HOOK
chmod +x "$plugin/.git/hooks/pre-push"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "interrupted release exit code"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.4" "manifest bumped before the failure"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.2.4 | wc -l | tr -d ' ')" \
    "0" "tag not on origin after the failure"
assert_eq "$(market_version)" "1.2.3" "marketplace still stale after the failure"
assert_contains "$out" "pre-push: refusing" "refused push shows the hook's own words"
assert_contains "$out" "are local; nothing was pushed" "refused push names what landed locally"
assert_contains "$out" "just resume-release" "refused push names the recovery command"
# The tag is published as-is by resume; nothing may recreate or move it.
tag_before_resume=$(git -C "$plugin" rev-parse v1.2.4)

rm -f "$plugin/.git/hooks/pre-push"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "resume exit code"
assert_eq "$(git -C "$plugin" rev-parse v1.2.4)" "$tag_before_resume" "resume left the tag object untouched"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" \
    "$(git -C "$plugin" rev-parse HEAD)" "resume pushed the branch"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.2.4 | wc -l | tr -d ' ')" \
    "1" "resume pushed the tag"
assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "resume created the GitHub release"
assert_eq "$(market_version)" "1.2.4" "resume bumped the marketplace"
assert_contains "$out" "Release v1.2.4 complete" "resume summary"

echo "=== resume: completes a release whose marketplace push was rejected ==="
new_sandbox "1.2.3"
# Same idea as the plugin-push scenario above, but the rejecting hook sits on
# the marketplace repo: the marketplace commit lands locally, its push fails,
# and a naive "is the working tree at $V" probe would call that done.
cat > "$marketplace/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
echo "pre-push: refusing" >&2
exit 1
HOOK
chmod +x "$marketplace/.git/hooks/pre-push"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "marketplace-push-interrupted release exit code"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.2.4 | wc -l | tr -d ' ')" \
    "1" "plugin tag reached origin despite the marketplace push failure"
assert_eq "$(market_version)" "1.2.4" "marketplace committed locally despite the failure"
assert_eq "$(git -C "$marketplace" ls-remote origin refs/heads/main | cut -f1)" \
    "$(git -C "$marketplace" log -1 --format=%H HEAD^)" "marketplace origin not yet at the bumped commit"
# The last outward step of the release, so a bare git error as the last word
# would leave the operator to work out what is already public.
assert_contains "$out" "push of the marketplace bump failed" "refused marketplace push names what failed"
assert_contains "$out" "public through its GitHub release" "refused marketplace push says what already landed"
assert_contains "$out" "just resume-release" "refused marketplace push names the recovery command"
assert_contains "$out" "/add-dir $marketplace" "refused marketplace push names the classifier remedy"

rm -f "$marketplace/.git/hooks/pre-push"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "marketplace-push resume exit code"
assert_eq "$(git -C "$marketplace" ls-remote origin refs/heads/main | cut -f1)" \
    "$(git -C "$marketplace" rev-parse HEAD)" "resume pushed the marketplace"
if grep -q "already complete (nothing to do)" <<<"$out"; then
    fail "marketplace-push resume falsely claimed nothing-to-do"
fi
assert_contains "$out" "Release v1.2.4 complete" "marketplace-push resume summary"

echo "=== resume: completes a first-publication release whose marketplace push was rejected ==="
new_sandbox ""   # empty .plugins — pre-first-publication, same as the plain
                 # first-publication scenario above, but interrupted+resumed.
cat > "$marketplace/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
echo "pre-push: refusing" >&2
exit 1
HOOK
chmod +x "$marketplace/.git/hooks/pre-push"
run_in "$plugin" bash plugin-dev/release.sh minor
assert_eq "$rc" "1" "first-publication marketplace-push-interrupted release exit code"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.3.0" "manifest bumped despite the marketplace push failure"
assert_eq "$(jq '[.plugins[] | select(.name=="fixture")] | length' "$marketplace/.claude-plugin/marketplace.json")" \
    "1" "marketplace entry created locally despite the failure"

rm -f "$marketplace/.git/hooks/pre-push"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "first-publication resume exit code"
assert_contains "$out" "Release v1.3.0 complete" "first-publication resume summary"
assert_eq "$(git -C "$marketplace" ls-remote origin refs/heads/main | cut -f1)" \
    "$(git -C "$marketplace" rev-parse HEAD)" "first-publication resume pushed the marketplace"
assert_eq "$(jq '[.plugins[] | select(.name=="fixture")] | length' "$marketplace/.claude-plugin/marketplace.json")" \
    "1" "first-publication resume created the entry exactly once, not a duplicate"
assert_eq "$(market_version)" "1.3.0" "first-publication resume entry version"

echo "=== resume: refuses to move a tag origin already has elsewhere ==="
new_sandbox "1.2.3"
init_sha="$(git -C "$plugin" rev-parse HEAD)"   # the "init" commit, already on origin
cat > "$plugin/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
echo "pre-push: refusing" >&2
exit 1
HOOK
chmod +x "$plugin/.git/hooks/pre-push"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "setup interrupted release exit code"
rm -f "$plugin/.git/hooks/pre-push"
# Simulate someone else publishing a different v1.2.4 on origin while this
# release was stalled: point the plugin origin's tag at the pre-bump commit,
# not this run's local tag.
git -C "$plugin-origin.git" tag v1.2.4 "$init_sha"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "moved-tag resume exit code"
assert_contains "$out" "refusing to move a published tag" "moved-tag resume message"
assert_eq "$(cat "$GH_LOG")" "" "moved-tag resume must not call gh"
assert_eq "$(market_version)" "1.2.3" "moved-tag resume must not touch the marketplace"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release resume-push scenarios passed\n'

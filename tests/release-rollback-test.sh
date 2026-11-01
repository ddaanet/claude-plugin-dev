#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: a refused commit rolling the bump back, a detached-HEAD marketplace,
# and a malformed marketplace.json refusing before anything is public.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-rollback-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/release-rollback.XXXXXX")"
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

echo "=== release: a refused commit rolls the manifest back ==="
new_sandbox "1.2.3"
# The manifest rewrite is already written and staged when `git commit` runs, so
# a bare set -e death here strands the bump: no commit, no tag, and a dirty tree
# that then blocks both a re-run and --resume on `uncommitted changes`.
cat > "$plugin/.git/hooks/pre-commit" <<'HOOK'
#!/bin/sh
echo "pre-commit: refusing" >&2
exit 1
HOOK
chmod +x "$plugin/.git/hooks/pre-commit"
run_in "$plugin" bash plugin-dev/release.sh patch
refused_out="$out"
assert_eq "$rc" "1" "refused-commit exit code"
assert_contains "$refused_out" "commit gate refused" "refused-commit names what failed"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" \
    "1.2.3" "refused-commit rolled the manifest back"
run_in "$plugin" git status --porcelain
assert_eq "$out" "" "refused-commit left a clean tree"
assert_eq "$(git -C "$plugin" tag --list 'v1.2.4')" "" "refused-commit created no tag"
assert_eq "$(cat "$GH_LOG")" "" "refused-commit must not call gh"

# The rollback exists to make this re-run possible: with the gate satisfied,
# an ordinary `release patch` proceeds with no manual repair in between.
rm -f "$plugin/.git/hooks/pre-commit"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "re-run after a refused commit exit code"
assert_contains "$out" "Release v1.2.4 complete" "re-run completes the release"
assert_eq "$(market_version)" "1.2.4" "re-run bumped the marketplace"

echo "=== release: a refused marketplace commit rolls the bump back and says what is public ==="
new_sandbox "1.2.3"
# The mirror of the scenario above, one repo over and much later in the flow:
# by the time the marketplace commit runs, the version commit, tag, branch
# push and GitHub release are all public. A staged leftover here would be read
# by the next run as an unrelated dirty tree and refuse `resume-release` — the
# one command that finishes the release — so the bump is rolled back instead.
cat > "$marketplace/.git/hooks/pre-commit" <<'HOOK'
#!/bin/sh
echo "pre-commit: refusing" >&2
exit 1
HOOK
chmod +x "$marketplace/.git/hooks/pre-commit"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "refused-marketplace-commit exit code"
assert_contains "$out" "commit gate refused the marketplace bump" "refused-marketplace-commit names what failed"
assert_contains "$out" "public through its GitHub release" "refused-marketplace-commit says what already landed"
assert_contains "$out" "was rolled back" "refused-marketplace-commit says the bump was rolled back"
assert_contains "$out" "just resume-release" "refused-marketplace-commit names the recovery command"
assert_eq "$(market_version)" "1.2.3" "refused-marketplace-commit rolled the marketplace back"
run_in "$marketplace" git status --porcelain
assert_eq "$out" "" "refused-marketplace-commit left a clean marketplace tree"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.2.4 | wc -l | tr -d ' ')" \
    "1" "refused-marketplace-commit left the plugin tag public"

# The rollback is what makes this the whole recovery: satisfy the gate and
# resume finishes, with no manual checkout in between.
rm -f "$marketplace/.git/hooks/pre-commit"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "resume after a refused marketplace commit exit code"
assert_eq "$(market_version)" "1.2.4" "resume rewrote and committed the marketplace bump"
assert_eq "$(git -C "$marketplace" ls-remote origin refs/heads/main | cut -f1)" \
    "$(git -C "$marketplace" rev-parse HEAD)" "resume pushed the marketplace"

echo "=== release: a non-v tag nearer than the release tag does not read as the latest release ==="
new_sandbox "1.2.3"
# `git describe --tags` returns the nearest tag of ANY name, distance-ordered
# rather than version-ordered, so a nightly or docs tag on a later commit used
# to be read as the last release and refused a repo that was perfectly
# consistent — with a hint telling the user to revert a bump they never made.
git -C "$plugin" commit --allow-empty -qm "later work"
git -C "$plugin" tag nightly-2026
git -C "$plugin" push -q origin main
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "non-v tag does not block the release"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" \
    "1.2.4" "manifest bumped past the non-v tag"
assert_eq "$(market_version)" "1.2.4" "marketplace bumped past the non-v tag"

echo "=== release: refuses a detached-HEAD marketplace before anything is published ==="
new_sandbox "1.2.3"
# A detached marketplace HEAD makes `symbolic-ref` empty, and the ls-remote for
# "refs/heads/" then matches nothing, so the push at the end is what discovers
# it — by which point the plugin's commit, tag, pushed tag and GitHub release
# have all landed. Preflight already validates MARKETPLACE_DIR three other
# ways; this belongs with them.
git -C "$marketplace" checkout -q --detach
run_in "$plugin" bash plugin-dev/release.sh patch
if [ "$rc" -eq 0 ]; then fail "detached-HEAD marketplace was accepted"; fi
assert_contains "$out" "detached HEAD" "detached-HEAD refusal names the state"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" \
    "1.2.3" "detached-HEAD refusal left the manifest alone"
assert_eq "$(git -C "$plugin" tag --list 'v1.2.4')" "" "detached-HEAD refusal created no tag"
assert_eq "$(cat "$GH_LOG")" "" "detached-HEAD refusal must not call gh"

echo "=== resume: a malformed marketplace.json refuses before anything is public ==="
# Item A1. common_preflight's marketplace-entry check (`jq -e ... any(...)`)
# reads ANY non-zero jq exit as "no entry" — it cannot distinguish a clean
# "not found" (exit 1) from a parse error on malformed JSON (exit 5,
# measured against jq 1.7). In `release` mode that misread is caught
# downstream by check-version.sh before anything is public. In `--resume`
# mode release_preflight never runs, so the misread survives common_preflight
# and the run proceeds through push_branch, push_tag and
# create_github_release — the GitHub release goes public — before
# bump_marketplace's own jq call, reading the same malformed file, finally
# aborts the script with a raw parse error.
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "setup release exit code"
: > "$GH_LOG"
# Corrupt marketplace.json in place and commit the corruption, so the
# marketplace repo's tree is clean (tree_is_clean must not be what refuses
# this run — a dirty-tree refusal would fire in common_preflight for an
# unrelated reason) while its content fails to parse.
printf '{"plugins":[' > "$marketplace/.claude-plugin/marketplace.json"
git -C "$marketplace" add -A
git -C "$marketplace" commit -qm "corrupt marketplace.json"
market_before="$(cat "$marketplace/.claude-plugin/marketplace.json")"
plugin_origin_tags_before="$(git -C "$plugin-origin.git" tag --list)"
market_origin_head_before="$(git -C "$marketplace-origin.git" rev-parse main)"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "malformed-marketplace resume exit code"
assert_contains "$out" "could not read" "malformed-marketplace resume names the failure mode"
assert_contains "$out" "marketplace.json" "malformed-marketplace resume names the file"
assert_eq "$(cat "$GH_LOG")" "" "malformed-marketplace resume must not call gh"
assert_eq "$(cat "$marketplace/.claude-plugin/marketplace.json")" "$market_before" \
    "malformed-marketplace resume left marketplace.json exactly as it found it"
assert_eq "$(git -C "$plugin-origin.git" tag --list)" "$plugin_origin_tags_before" \
    "malformed-marketplace resume pushed no new plugin tag"
assert_eq "$(git -C "$marketplace-origin.git" rev-parse main)" "$market_origin_head_before" \
    "malformed-marketplace resume pushed nothing to the marketplace origin"

echo "=== release: a malformed marketplace.json refuses before anything is public ==="
# Item A1, release-mode side. Today the same misread in common_preflight's
# entry check survives it (as above), but in `release` mode the run then
# hits release_preflight's own check-version.sh call, which fails on the
# same malformed file for an unrelated reason (version-drift wording, not
# "could not read"). After the fix, common_preflight refuses first, here
# too, before release_preflight ever runs.
new_sandbox "1.2.3"
printf '{"plugins":[' > "$marketplace/.claude-plugin/marketplace.json"
git -C "$marketplace" add -A
git -C "$marketplace" commit -qm "corrupt marketplace.json"
market_before="$(cat "$marketplace/.claude-plugin/marketplace.json")"
plugin_origin_tags_before="$(git -C "$plugin-origin.git" tag --list)"
market_origin_head_before="$(git -C "$marketplace-origin.git" rev-parse main)"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "malformed-marketplace release exit code"
assert_contains "$out" "could not read" "malformed-marketplace release names the failure mode"
assert_contains "$out" "marketplace.json" "malformed-marketplace release names the file"
assert_eq "$(cat "$GH_LOG")" "" "malformed-marketplace release must not call gh"
assert_eq "$(cat "$marketplace/.claude-plugin/marketplace.json")" "$market_before" \
    "malformed-marketplace release left marketplace.json exactly as it found it"
assert_eq "$(git -C "$plugin" tag --list 'v1.2.4')" "" \
    "malformed-marketplace release created no local tag"
assert_eq "$(git -C "$plugin-origin.git" tag --list)" "$plugin_origin_tags_before" \
    "malformed-marketplace release pushed no new plugin tag"
assert_eq "$(git -C "$marketplace-origin.git" rev-parse main)" "$market_origin_head_before" \
    "malformed-marketplace release pushed nothing to the marketplace origin"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release rollback scenarios passed\n'

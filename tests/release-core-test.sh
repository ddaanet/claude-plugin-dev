#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: the plain release paths -- the happy path, a first publication, a bad
# option or bump word, an unwritable marketplace directory, a major bump, the
# zero-argument shape.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-core-test.sh   (run from repo root)
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

skip_as_root() {
    # $1=scenario title. Succeeds, printing a SKIP line that names the scenario,
    # when the suite runs as root; fails silently otherwise. Root ignores a
    # directory's permission bits, so `chmod 555` blocks nothing and the
    # unwritable-marketplace scenarios would exercise the writable path and
    # report a toolkit regression that is only the environment. Always called as
    # `if ! skip_as_root …; then`, never as a bare `&&` list, so a false return
    # is not an errexit-visible failure.
    if [ "$(id -u)" -ne 0 ]; then
        return 1
    fi
    printf 'SKIP: %s -- running as root, which ignores chmod 555 on a directory\n' "$1"
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

echo "=== release: happy path ==="
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "happy-path exit code"
assert_contains "$out" "Release v1.2.4 complete" "happy-path summary"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.4" "manifest version"
assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
    "yes" "local tag created"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.2.4 | wc -l | tr -d ' ')" \
    "1" "tag pushed to origin"
assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "gh release created"
assert_eq "$(market_version)" "1.2.4" "marketplace bumped"
assert_eq "$(jq -c '.plugins[] | select(.name=="fixture") | .source' \
    "$marketplace/.claude-plugin/marketplace.json")" \
    '{"source":"github","repo":"o/fixture"}' "existing entry source untouched by bump"
assert_eq "$(git -C "$marketplace" log -1 --format=%s)" "release: fixture 1.2.4" "marketplace commit"

echo "=== release: first publication creates the marketplace entry ==="
new_sandbox ""   # empty .plugins — pre-first-publication
run_in "$plugin" bash plugin-dev/release.sh minor
assert_eq "$rc" "0" "first-publication exit code"
assert_contains "$out" "marketplace: entry created at 1.3.0" "first-publication summary"
entry="$(jq -c '.plugins[] | select(.name=="fixture")' \
    "$marketplace/.claude-plugin/marketplace.json")"
assert_eq "$(printf '%s' "$entry" | jq -r .version)" "1.3.0" "created entry version"
assert_eq "$(printf '%s' "$entry" | jq -r .license)" "MIT" "created entry license from manifest"
assert_eq "$(printf '%s' "$entry" | jq -r .description)" "test fixture" "created entry description"
# The source is a url source whose url is built from the owner/repo slug
# derived from origin. Origin is a local path in the fixture, so the slug is
# its last two components: the sandbox dir and "plugin-origin". The expected
# value is spelled from that fixture fact, not derived with the script's sed.
expected_source="$(jq -cn --arg u "https://github.com/$(basename "$sandbox")/plugin-origin.git" \
    '{source: "url", url: $u}')"
assert_eq "$(printf '%s' "$entry" | jq -c .source)" "$expected_source" \
    "created entry source is a url source"

echo "=== release: unknown option is refused cleanly ==="
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh --bogus
assert_eq "$rc" "1" "unknown option exit code"
assert_contains "$out" "unknown option: --bogus" "unknown option message"
assert_eq "$(cat "$GH_LOG")" "" "unknown option must not call gh"

echo "=== release: unknown bump word is refused cleanly ==="
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh bogusword
assert_eq "$rc" "1" "unknown bump word exit code"
assert_contains "$out" "unknown bump type: bogusword" "unknown bump word message"
assert_contains "$out" "usage: release.sh" "unknown bump word usage hint"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.3" "unknown bump word left manifest untouched"
assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
    "no" "unknown bump word created no tag"
assert_eq "$(cat "$GH_LOG")" "" "unknown bump word must not call gh"

echo "=== release: a manifest with no name is refused before anything is published ==="
new_sandbox "1.2.3"
jq 'del(.name)' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" commit -qam "drop the manifest name"
git -C "$plugin" push -q origin main
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "nameless manifest exit code"
assert_contains "$out" "has no .name" "nameless manifest message"
assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
    "no" "nameless manifest created no tag"
assert_eq "$(cat "$GH_LOG")" "" "nameless manifest must not call gh"
assert_eq "$(jq -r '.plugins | map(.name) | join(",")' "$marketplace/.claude-plugin/marketplace.json")" \
    "fixture" "nameless manifest left the marketplace entries as they were"

# --resume runs no check-version, so the refusal above is not enough there: the
# manifest name is read in the preflight both modes share.
echo "=== resume: a manifest with no name is refused before anything is published ==="
new_sandbox "1.2.3"
jq 'del(.name)' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" commit -qam "drop the manifest name"
git -C "$plugin" push -q origin main
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "nameless manifest resume exit code"
assert_contains "$out" "has no .name" "nameless manifest resume message"
assert_eq "$(cat "$GH_LOG")" "" "nameless manifest resume must not call gh"
assert_eq "$(jq -r '.plugins | map(.name) | join(",")' "$marketplace/.claude-plugin/marketplace.json")" \
    "fixture" "nameless manifest resume left the marketplace entries as they were"

echo "=== release: a marketplace file with no plugins list is refused, and not as drift ==="
new_sandbox "1.2.3"
printf '{}\n' > "$marketplace/.claude-plugin/marketplace.json"
git -C "$marketplace" commit -qam "empty the marketplace"
git -C "$marketplace" push -q origin main
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "plugins-less marketplace exit code"
assert_contains "$out" "could not read" "plugins-less marketplace message"
assert_not_contains "$out" "version drift" "plugins-less marketplace is not reported as drift"
assert_eq "$(cat "$GH_LOG")" "" "plugins-less marketplace must not call gh"

echo "=== release: refuses when the marketplace directory isn't writable ==="
if ! skip_as_root "release: refuses when the marketplace directory isn't writable"; then
    new_sandbox "1.2.3"
    chmod 555 "$marketplace/.claude-plugin"
    run_in "$plugin" bash plugin-dev/release.sh patch
    chmod 755 "$marketplace/.claude-plugin"
    assert_eq "$rc" "1" "read-only marketplace dir exit code"
    assert_contains "$out" "$marketplace/.claude-plugin is not writable" "read-only marketplace dir message names the path"
    assert_contains "$out" "Permission denied" "read-only marketplace dir message keeps mktemp's own diagnosis"
    assert_contains "$out" "excludedCommands" "read-only marketplace dir message names the exclusion route"
    assert_contains "$out" "just resume-release" "read-only marketplace dir message names the resume-release entry"
    assert_not_contains "$out" "dangerouslyDisableSandbox" "read-only marketplace dir message does not name the denied bypass flag"
    assert_contains "$out" "/add-dir $marketplace" "read-only marketplace dir message names the add-dir escape"
    assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.3" "read-only marketplace dir left manifest untouched"
    assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
        "no" "read-only marketplace dir created no tag"
    assert_eq "$(cat "$GH_LOG")" "" "read-only marketplace dir must not call gh"
fi

echo "=== resume: succeeds on a no-op marketplace bump even when its directory isn't writable ==="
if ! skip_as_root "resume: succeeds on a no-op marketplace bump even when its directory isn't writable"; then
    new_sandbox "1.2.3"
    run_in "$plugin" bash plugin-dev/release.sh patch
    assert_eq "$rc" "0" "setup release exit code"
    chmod 555 "$marketplace/.claude-plugin"
    run_in "$plugin" bash plugin-dev/release.sh --resume
    chmod 755 "$marketplace/.claude-plugin"
    assert_eq "$rc" "0" "no-op resume exit code despite read-only marketplace dir"
    assert_contains "$out" "already complete (nothing to do)" "no-op resume summary despite read-only marketplace dir"
fi

echo "=== resume: still refuses when a real marketplace write is needed and the directory isn't writable ==="
if ! skip_as_root "resume: still refuses when a real marketplace write is needed and the directory isn't writable"; then
    new_sandbox "1.2.3"
    # Plugin push rejected: manifest+tag land locally, but the marketplace is
    # never touched (still 1.2.3) — a real write is needed to catch it up.
    cat > "$plugin/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
echo "pre-push: refusing" >&2
exit 1
HOOK
    chmod +x "$plugin/.git/hooks/pre-push"
    run_in "$plugin" bash plugin-dev/release.sh patch
    assert_eq "$rc" "1" "setup interrupted-release exit code"
    assert_eq "$(market_version)" "1.2.3" "setup marketplace still stale"
    rm -f "$plugin/.git/hooks/pre-push"
    chmod 555 "$marketplace/.claude-plugin"
    run_in "$plugin" bash plugin-dev/release.sh --resume
    chmod 755 "$marketplace/.claude-plugin"
    assert_eq "$rc" "1" "real-write resume exit code"
    assert_contains "$out" "$marketplace/.claude-plugin is not writable" "real-write resume message names the path"
    assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.2.4 | wc -l | tr -d ' ')" \
        "1" "real-write resume still pushed the plugin tag before failing at the marketplace"
    assert_eq "$(market_version)" "1.2.3" "real-write resume left the marketplace untouched"
fi

# jq always writes 2-space JSON, so a byte comparison of its output against a
# marketplace.json kept in any other style reads "changed" for a file that is
# already at the version, and the rewrite commits a whole-file diff.
echo "=== resume: a marketplace already at the version in another JSON style is left alone ==="
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "setup release exit code"
jq -c . "$marketplace/.claude-plugin/marketplace.json" > "$sandbox/compact.json"
cp "$sandbox/compact.json" "$marketplace/.claude-plugin/marketplace.json"
git -C "$marketplace" commit -qam "compact style"
git -C "$marketplace" push -q origin main
mp_head="$(git -C "$marketplace" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "other-style no-op resume exit code"
assert_contains "$out" "already complete (nothing to do)" "other-style no-op resume summary"
assert_eq "$(git -C "$marketplace" rev-parse HEAD)" "$mp_head" "other-style no-op resume committed nothing"
assert_eq "$(cmp "$marketplace/.claude-plugin/marketplace.json" "$sandbox/compact.json" && echo same)" \
    "same" "other-style no-op resume left the file byte for byte"

echo "=== release: major bump end-to-end ==="
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh major
assert_eq "$rc" "0" "major bump exit code"
assert_contains "$out" "Release v2.0.0 complete" "major bump summary"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "2.0.0" "major bump manifest version"
assert_eq "$(market_version)" "2.0.0" "major bump marketplace bumped"

echo "=== release: zero-argument shape defaults to patch ==="
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "0" "zero-argument exit code"
assert_contains "$out" "Release v1.2.4 complete" "zero-argument summary"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.4" "zero-argument manifest version"
assert_eq "$(market_version)" "1.2.4" "zero-argument marketplace bumped"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release core scenarios passed\n'

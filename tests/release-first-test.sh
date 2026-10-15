#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: a first release -- the manifest version published verbatim, an explicit
# bump refused, and a marketplace entry that neither disqualifies nor exempts
# it.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-first-test.sh   (run from repo root)
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

make_virgin() {
    # $1=manifest version. Strips the fixture's release history so the plugin
    # has never been released: no v* tags locally or on origin, and the manifest
    # seeded at $1. Paired with new_sandbox "" (no marketplace entry) this is
    # the state a plugin scaffolded by the external plugin-dev marketplace
    # plugin arrives in; paired with new_sandbox "1.2.3" the entry already
    # agrees with $1, on a plugin that has still never been tagged.
    git -C "$plugin" tag -d v1.2.3 >/dev/null
    git -C "$plugin" push -q origin :refs/tags/v1.2.3
    jq --arg v "$1" '.version = $v' "$plugin/.claude-plugin/plugin.json" \
        > "$plugin/.claude-plugin/plugin.json.tmp"
    mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
    git -C "$plugin" add -A
    # Seeding the version the fixture already carries stages nothing, and a
    # no-op `git commit` is a hard error under set -e.
    if ! git -C "$plugin" diff --cached --quiet; then
        git -C "$plugin" commit -qm "scaffold at $1"
    fi
    git -C "$plugin" push -q origin main
}

echo "=== release: a first release publishes the manifest version verbatim ==="
new_sandbox ""            # no marketplace entry
make_virgin "0.1.0"       # no v* tags, manifest seeded by an external scaffold
head_before="$(git -C "$plugin" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "0" "first-release exit code"
assert_contains "$out" "Release v0.1.0 complete" "first-release summary"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "0.1.0" "first-release manifest untouched"
# Nothing to bump means nothing to commit: the tag lands on the commit that was
# already HEAD, not on a synthetic "release: 0.1.0" commit above it.
assert_eq "$(git -C "$plugin" rev-parse HEAD)" "$head_before" "first-release makes no commit"
assert_eq "$(git -C "$plugin" rev-parse -q --verify 'refs/tags/v0.1.0^{commit}')" \
    "$head_before" "first-release tags HEAD"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v0.1.0 | wc -l | tr -d ' ')" \
    "1" "first-release tag pushed to origin"
assert_contains "$(cat "$GH_LOG")" "release create v0.1.0" "first-release gh release created"
assert_eq "$(market_version)" "0.1.0" "first-release marketplace entry created at the manifest version"

echo "=== release: a first release refuses an explicit bump ==="
for word in patch minor major; do
    new_sandbox ""
    make_virgin "0.1.0"
    run_in "$plugin" bash plugin-dev/release.sh "$word"
    assert_eq "$rc" "1" "first-release '$word' exit code"
    assert_contains "$out" "never been released" "first-release '$word' explains why"
    assert_contains "$out" "0.1.0" "first-release '$word' names the version it would publish"
    assert_contains "$out" "set .version in .claude-plugin/plugin.json" \
        "first-release '$word' names the remedy for wanting another version"
    assert_contains "$out" "commit that edit" \
        "first-release '$word' names committing the version edit"
    assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "first-release '$word' creates no tag"
    assert_eq "$(cat "$GH_LOG")" "" "first-release '$word' must not call gh"
    assert_eq "$(market_version)" "" "first-release '$word' must not touch the marketplace"
done

echo "=== release: a marketplace entry does not disqualify a first release ==="
new_sandbox "1.2.3"       # entry exists at 1.2.3...
make_virgin "1.2.3"       # ...but the plugin has never been tagged, locally or on origin
head_before="$(git -C "$plugin" rev-parse HEAD)"
marketplace_head_before="$(git -C "$marketplace" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "0" "entry-agrees-no-tags exit code"
assert_contains "$out" "Release v1.2.3 complete" "entry-agrees-no-tags publishes the manifest version verbatim"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.3" "entry-agrees-no-tags manifest untouched"
assert_eq "$(git -C "$plugin" rev-parse HEAD)" "$head_before" "entry-agrees-no-tags makes no commit"
assert_eq "$(git -C "$plugin" rev-parse -q --verify 'refs/tags/v1.2.3^{commit}')" \
    "$head_before" "entry-agrees-no-tags tags HEAD"
assert_eq "$(market_version)" "1.2.3" "entry-agrees-no-tags marketplace untouched"
assert_eq "$(git -C "$marketplace" rev-parse HEAD)" "$marketplace_head_before" \
    "entry-agrees-no-tags marketplace HEAD unmoved"

echo "=== release: a marketplace entry does not exempt a first release from refusing a bump ==="
new_sandbox "1.2.3"
make_virgin "1.2.3"
head_before="$(git -C "$plugin" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "entry-agrees-no-tags-bump exit code"
assert_contains "$out" "never been released" "entry-agrees-no-tags-bump explains why"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "entry-agrees-no-tags-bump creates no tag"
assert_eq "$(cat "$GH_LOG")" "" "entry-agrees-no-tags-bump must not call gh"
# The tag and gh assertions alone would still pass a refusal raised after the
# version commit and branch push — the two irreversible steps that precede
# them. The refusal belongs in preflight, so nothing at all may have landed.
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.3" \
    "entry-agrees-no-tags-bump left the manifest untouched"
assert_eq "$(git -C "$plugin" rev-parse HEAD)" "$head_before" "entry-agrees-no-tags-bump makes no commit"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$head_before" \
    "entry-agrees-no-tags-bump did not advance origin main"
assert_eq "$(market_version)" "1.2.3" "entry-agrees-no-tags-bump must not touch the marketplace"

echo "=== release: an initial release whose entry disagrees with the manifest is still refused ==="
new_sandbox "1.2.3"       # entry recorded at 1.2.3...
make_virgin "0.1.0"       # ...but the plugin has never been tagged, locally or on origin: the
                          # lost-tags probe finds nothing either way, so this state is verifiably
                          # unpublished — decision 1's hint, not resume, is the one that must
                          # fire here.
head_before="$(git -C "$plugin" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "initial-entry-disagrees exit code"
# Asserting the two versions against "$out" whole would pass on check-version.sh's
# own drift line alone (`plugin.json=0.1.0 marketplace.json=1.2.3`), which says
# nothing about the hint. Decision 1 and the runbook both require the HINT to
# name both versions, so drop that line first. `|| [ "$?" -eq 1 ]` absorbs a
# no-match grep's status 1 and nothing else, so an empty result is a value while
# a real grep error still aborts the suite.
hint_only="$(printf '%s\n' "$out" | { grep -v '^check-version:' || [ "$?" -eq 1 ]; })"
assert_contains "$hint_only" "0.1.0" "initial-entry-disagrees hint names the manifest version"
assert_contains "$hint_only" "1.2.3" "initial-entry-disagrees hint names the marketplace entry version"
assert_contains "$out" "no release is recorded at" \
    "initial-entry-disagrees says neither version has a recorded release"
assert_contains "$out" "correct the marketplace entry" \
    "initial-entry-disagrees points at the marketplace entry as the one to correct"
assert_contains "$out" "set .version in .claude-plugin/plugin.json" \
    "initial-entry-disagrees offers editing the manifest instead, if 1.2.3 is the intended version"
assert_not_contains "$out" "just resume-release" \
    "initial-entry-disagrees must not offer resume — nothing was ever released to resume"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "initial-entry-disagrees created no tag"
assert_eq "$(cat "$GH_LOG")" "" "initial-entry-disagrees must not call gh"
# Decision 1's rejected alternative was to skip check-version.sh here and let
# bump_marketplace overwrite the entry. These four pin the refusal as a refusal:
# nothing published, and the disagreeing entry left standing for the maintainer
# to resolve by hand.
assert_eq "$(market_version)" "1.2.3" "initial-entry-disagrees must not overwrite the marketplace entry"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "0.1.0" \
    "initial-entry-disagrees left the manifest untouched"
assert_eq "$(git -C "$plugin" rev-parse HEAD)" "$head_before" "initial-entry-disagrees makes no commit"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$head_before" \
    "initial-entry-disagrees did not advance origin main"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release first scenarios passed\n'

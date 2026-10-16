#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: which tags count as releases -- non-semver v tags, a manifest ahead of the
# newest tag, tags with no marketplace entry.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-tags-test.sh   (run from repo root)
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

echo "=== release: non-semver v tags are not releases ==="
new_sandbox ""            # no marketplace entry
make_virgin "0.1.0"       # manifest seeded by an external scaffold, no v* tags
# The only v* tags this plugin then carries are not versions, so it is still at
# its first release. Both are load-bearing and neither is redundant: `vnext`
# is what `git tag --list 'v*'` matches and no version filter should, while
# `v1.2` is what tells the full three-part anchor from a `^v[0-9]` one — under
# that weaker anchor v1.2 survives, the plugin reads as released, and the run
# refuses on manifest-versus-latest-tag instead.
git -C "$plugin" tag vnext
git -C "$plugin" tag v1.2
head_before="$(git -C "$plugin" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "0" "non-semver-tags exit code"
assert_contains "$out" "Release v0.1.0 complete" "non-semver-tags summary"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "0.1.0" \
    "non-semver-tags manifest untouched"
assert_eq "$(git -C "$plugin" rev-parse HEAD)" "$head_before" \
    "non-semver-tags makes no commit"
assert_eq "$(git -C "$plugin" rev-parse -q --verify 'refs/tags/v0.1.0^{commit}')" \
    "$head_before" "non-semver-tags tags HEAD"

echo "=== release: a non-semver v tag above the release tag does not read as the latest ==="
new_sandbox "1.2.3"        # fixture keeps v1.2.3, entry at 1.2.3
# `vnext` sorts above v1.2.3 under --sort=-v:refname (verified, git 2.47.3), so
# latest_tag must be routed through the same semver filter release_tags uses —
# not merely consulted to decide first-release vs not. `v1.2` sorts below
# v1.2.3 and is inert here: under a weaker `^v[0-9]` anchor this scenario still
# passes. It is the scenario above that tells the full three-part anchor from
# that one; v1.2 is carried here only to keep one fixture tag set across the
# suites. The summary line is the last thing release.sh prints, after the tag
# push, the GitHub release and the marketplace bump, so asserting it covers the
# whole publication and names the tag that was created.
git -C "$plugin" tag vnext
git -C "$plugin" tag v1.2
# A second, older semver tag is what pins *which end* of the listing latest_tag
# takes. With v1.2.3 alone the first and last lines are the same line, so a
# `sed -n '$s/…'` taking the oldest release passes every scenario in the suite.
git -C "$plugin" tag v1.0.0
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "non-semver-latest-tag exit code"
assert_contains "$out" "Release v1.2.4 complete" "non-semver-latest-tag summary"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.4" \
    "non-semver-latest-tag manifest bumped"

echo "=== release: a non-semver v tag above the release tag does not suppress the drift check ==="
new_sandbox "1.3.0"       # entry at the hand-bumped version, so check-version.sh passes
# The other half of routing latest_tag through the filter: the junk tag must
# not be picked, AND the newest real release tag must still be. Not proving
# both leaves "skip the manifest-vs-tag check whenever the newest v* tag is
# not semver" passing the whole suite (verified by mutation) — and under that
# reading a hand-bumped manifest publishes a version past the intended one
# exactly when some `vnext`-shaped tag happens to exist.
jq '.version = "1.3.0"' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" commit -qam "hand-bump the manifest"
git -C "$plugin" push -q origin main
git -C "$plugin" tag vnext
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "non-semver-latest-drift exit code"
assert_contains "$out" "does not match latest tag (v1.2.3)" \
    "non-semver-latest-drift names the newest release tag, not the junk one"
assert_eq "$(git -C "$plugin" tag --list 'v1.3.1')" "" "non-semver-latest-drift creates no tag"
assert_eq "$(cat "$GH_LOG")" "" "non-semver-latest-drift must not call gh"

echo "=== release: tags with no marketplace entry is not a first release ==="
new_sandbox ""            # no entry...
run_in "$plugin" bash plugin-dev/release.sh patch   # ...but the fixture's v1.2.3 tag stands
assert_eq "$rc" "0" "tagged-unpublished exit code"
assert_contains "$out" "Release v1.2.4 complete" "tagged-unpublished bumps forward"
assert_eq "$(market_version)" "1.2.4" "tagged-unpublished marketplace entry created at the bumped version"

# The marketplace entry is seeded at the hand-bumped version so check-version.sh
# passes and the manifest-vs-tag check is the one that fires.
echo "=== release: a manifest ahead of the newest tag names the invariant it broke ==="
new_sandbox "1.3.0"
jq '.version = "1.3.0"' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" commit -qam "hand-bump the manifest"
git -C "$plugin" push -q origin main
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "version-drift exit code"
assert_contains "$out" "does not match latest tag" "version-drift names the mismatch"
assert_contains "$out" "LAST released version, never the next one" "version-drift states the invariant"
assert_contains "$out" "set .version in .claude-plugin/plugin.json back to 1.2.3" \
    "version-drift gives the remedy that works: revert the committed bump"
assert_contains "$out" "bump that produces the version you want" \
    "version-drift says which bump to re-run with"
# The two remedies this hint used to offer are dead on every path that reaches
# it, and a reader who does not know that will put them back. Both negatives
# are load-bearing:
#
# `git checkout HEAD -- <manifest>` is always a no-op here. common_preflight
# refuses a dirty tree — its own `tree_is_clean "."` guard — before
# release_preflight runs, and
# clean_pathspecs exempts only the gitlore submodule — never
# `.claude-plugin/` — so the hand-written bump has always been committed
# already by the time this fires. This scenario's own fixture commits it.
#
# `git fetch --tags` can never have anything to fetch. latest_tag comes from
# release_tag_list, the LOCAL semver tags, and the lost-tag probe upstream has
# already established that local and origin agree on the newest one (an origin
# tag ahead fires the probe's own fetch hint first; an unreachable origin dies
# there). The probe-before-drift scenario above pins that ordering. Worse than
# useless: the probe's hint is what sends an operator to fetch, so they reach
# this refusal having just run the command it used to advise.
assert_not_contains "$out" "git checkout HEAD --" \
    "version-drift must not offer the checkout — the tree is provably clean here"
assert_not_contains "$out" "git fetch --tags" \
    "version-drift must not offer a fetch — the lost-tag probe already cleared origin"
assert_eq "$(git -C "$plugin" tag --list 'v1.3.1')" "" "version-drift creates no tag"
assert_eq "$(cat "$GH_LOG")" "" "version-drift must not call gh"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release tags scenarios passed\n'

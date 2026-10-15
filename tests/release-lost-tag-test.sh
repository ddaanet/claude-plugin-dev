#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: a lost local tag and the origin probe -- unverifiable refusals, the
# version-sorted listing, the probe running before the drift check, and a listing
# that fails.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-lost-tag-test.sh   (run from repo root)
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

lose_tag() {
    # $1=repo path, $2=tag (default v1.2.3). Deletes the tag from the local
    # clone only, leaving origin's copy in place: the "lost tags" state Item
    # 1.2's origin probe exists to catch — a clone whose local tag went missing
    # while origin's release history did not. Contrast make_virgin, which drops
    # origin's copy too: a plugin that was truly never released. Used by slices
    # 1-4. $1 is required, not defaulted to $plugin: a default no call site may
    # take (shellcheck SC2119 fires on the bare call) is a contract that reads
    # as usable and is not. `git tag -d` on an absent tag exits non-zero and
    # says so on stderr, which under this suite's `set -e` aborts the run —
    # deleting a tag that is not there is a broken fixture, never a no-op.
    local repo="$1" tag="${2:-v1.2.3}"
    git -C "$repo" tag -d "$tag" >/dev/null
}

# The other side of the branch the scenario above opens. Decision 1 replaces the
# drift hint only where the plugin is verifiably unpublished; a plugin that HAS
# been released and drifts — tag and manifest at 1.2.4, entry still at 1.2.3,
# exactly the half-landed release resume exists for — must still be told to
# resume, because there the advice is correct. Nothing else in the suite pins
# that: an implementation replacing the resume hint unconditionally passes every
# other scenario, verified by mutation. Green today, so this is a
# characterization guard, not part of slice 6's red.
echo "=== release: version drift on a plugin that HAS been released still offers resume ==="
new_sandbox "1.2.3"       # entry still at the previously released 1.2.3...
jq '.version = "1.2.4"' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" commit -qam "release: 1.2.4"
git -C "$plugin" tag -a v1.2.4 -m "Release 1.2.4"
git -C "$plugin" push -q origin main
git -C "$plugin" push -q origin v1.2.4    # ...but 1.2.4's commit and tag already landed
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "released-drift exit code"
assert_contains "$out" "version drift" "released-drift refuses as drift"
assert_contains "$out" "just resume-release" \
    "released-drift still offers resume — a release did land partially here"
assert_eq "$(git -C "$plugin" tag --list 'v1.2.5')" "" "released-drift creates no tag"
assert_eq "$(market_version)" "1.2.3" "released-drift must not touch the marketplace"
assert_eq "$(cat "$GH_LOG")" "" "released-drift must not call gh"

echo "=== release: an explicit bump on a lost local tag refuses as unverifiable, not as a first release ==="
new_sandbox "1.2.3"
lose_tag "$plugin"
git -C "$plugin" commit --allow-empty -qm "later work"
origin_head_before="$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "lost-tag-bump exit code"
assert_contains "$out" "v1.2.3" "lost-tag-bump names the lost tag"
assert_contains "$out" "git fetch --tags" "lost-tag-bump names the fetch remedy"
assert_not_contains "$out" "never been released" "lost-tag-bump must not read as a first release"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "lost-tag-bump created no local tag"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$origin_head_before" \
    "lost-tag-bump did not advance origin main"
assert_eq "$(cat "$GH_LOG")" "" "lost-tag-bump must not call gh"
assert_eq "$(market_version)" "1.2.3" "lost-tag-bump must not touch the marketplace"

echo "=== release: a lost local tag with no bump argument refuses as unverifiable, not published as a first release ==="
new_sandbox ""
lose_tag "$plugin"
git -C "$plugin" commit --allow-empty -qm "later work"
origin_head_before="$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "lost-tag-no-bump exit code"
assert_contains "$out" "v1.2.3" "lost-tag-no-bump names the lost tag"
assert_contains "$out" "git fetch --tags" "lost-tag-no-bump names the fetch remedy"
assert_not_contains "$out" "never been released" "lost-tag-no-bump must not read as a first release"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "lost-tag-no-bump created no local tag"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$origin_head_before" \
    "lost-tag-no-bump did not advance origin main"
assert_eq "$(cat "$GH_LOG")" "" "lost-tag-no-bump must not call gh"
assert_eq "$(market_version)" "" "lost-tag-no-bump must not touch the marketplace"

echo "=== release: a lost local tag refuses even when the manifest was hand-advanced past a different real origin release ==="
# The manifest/entry version (1.3.0) and the lost origin tag (v1.2.3) are
# different strings here — unlike the two lost-tag scenarios above, where the
# manifest and the origin tag agree. That is what lets this scenario tell
# apart "the hint names the origin tag" from "the hint names the manifest
# version": only the former can pass here.
new_sandbox "1.3.0"
jq '.version = "1.3.0"' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" add -A
git -C "$plugin" commit -qm "hand-advance to 1.3.0"
git -C "$plugin" push -q origin main
lose_tag "$plugin"
origin_head_before="$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "hand-advanced-lost-tag exit code"
assert_contains "$out" "v1.2.3" "hand-advanced-lost-tag names the lost origin tag, not the manifest version"
assert_contains "$out" "git fetch --tags" "hand-advanced-lost-tag names the fetch remedy"
assert_not_contains "$out" "never been released" "hand-advanced-lost-tag must not read as a first release"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "hand-advanced-lost-tag created no local tag"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.3.0 | wc -l | tr -d ' ')" "0" \
    "hand-advanced-lost-tag did not push v1.3.0 to origin"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$origin_head_before" \
    "hand-advanced-lost-tag did not advance origin main further"
assert_eq "$(cat "$GH_LOG")" "" "hand-advanced-lost-tag must not call gh"
assert_eq "$(market_version)" "1.3.0" "hand-advanced-lost-tag must not touch the marketplace"

echo "=== release: origin's listing is read version-sorted, not lexicographically ==="
new_sandbox "1.2.3"
lose_tag "$plugin"
for t in v1.9.0 v1.10.0 v1.11.0; do
    git -C "$plugin" tag "$t"
    git -C "$plugin" push -q origin "$t"
    lose_tag "$plugin" "$t"
done
# Set comparison, not a named refutation: which tag the code would create is
# itself under test, and naming one here (e.g. "creates no v1.11.1") would
# pass vacuously against a mutation that creates the wrong one instead.
local_tags_before="$(git -C "$plugin" tag --list 'v*' | sort)"
origin_head_before="$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "origin-sort exit code"
assert_contains "$out" "v1.11.0" "origin-sort names the newest origin tag"
assert_not_contains "$out" "v1.10.0" "origin-sort does not name the second-newest origin tag"
assert_not_contains "$out" "v1.9.0" "origin-sort does not name the third-newest origin tag"
# With the local tag listing empty here (every local copy was lost above),
# a refusal that skipped the lost-tags guard would still hit the unrelated
# "explicit bump on a plugin that has never been released" refusal a few
# lines further down — same rc, same absence of every side effect below, so
# only this needle tells the two apart. Verified by mutation: turning the
# lost-tags guard's `die` into a fall-through `note` reaches that other
# refusal here and every assertion but this one stays green.
assert_not_contains "$out" "never been released" "origin-sort must not read as a first release"
assert_eq "$(git -C "$plugin" tag --list 'v*' | sort)" "$local_tags_before" \
    "origin-sort local tag set unchanged"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$origin_head_before" \
    "origin-sort did not advance origin main"
assert_eq "$(cat "$GH_LOG")" "" "origin-sort must not call gh"
assert_eq "$(market_version)" "1.2.3" "origin-sort must not touch the marketplace"

echo "=== release: the lost-tag probe runs before the version-drift check ==="
new_sandbox "1.2.3"
make_virgin "1.2.3"
jq '.version = "1.2.4"' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" commit -qam "hand-advance to 1.2.4"
git -C "$plugin" push -q origin main
git -C "$plugin" tag v1.2.4
git -C "$plugin" push -q origin v1.2.4
lose_tag "$plugin" v1.2.4
# Set comparison, not a named refutation — see the origin-sort scenario above.
local_tags_before="$(git -C "$plugin" tag --list 'v*' | sort)"
origin_head_before="$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "probe-before-drift exit code"
assert_contains "$out" "v1.2.4" "probe-before-drift names the lost origin tag"
assert_contains "$out" "git fetch --tags" "probe-before-drift names the fetch remedy"
assert_not_contains "$out" "version drift" "probe-before-drift must not read as a drift refusal"
assert_not_contains "$out" "just resume-release" "probe-before-drift must not offer the drift recovery command"
assert_eq "$(git -C "$plugin" tag --list 'v*' | sort)" "$local_tags_before" \
    "probe-before-drift local tag set unchanged"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$origin_head_before" \
    "probe-before-drift did not advance origin main"
assert_eq "$(cat "$GH_LOG")" "" "probe-before-drift must not call gh"
assert_eq "$(market_version)" "1.2.3" "probe-before-drift must not touch the marketplace"

echo "=== release: a listing that fails on an unreachable origin URL refuses, saying nothing was done ==="
new_sandbox "1.2.3"
make_virgin "1.2.3"
git -C "$plugin" remote set-url origin "$sandbox/does-not-exist"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "unreachable-origin exit code"
assert_contains "$out" "could not verify this plugin's release history on origin" \
    "unreachable-origin names the unverifiable probe"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "unreachable-origin created no local tag"
assert_eq "$(cat "$GH_LOG")" "" "unreachable-origin must not call gh"

echo "=== release: a listing that fails with no origin remote at all refuses, saying nothing was done ==="
new_sandbox "1.2.3"
make_virgin "1.2.3"
git -C "$plugin" remote remove origin
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "no-origin exit code"
assert_contains "$out" "could not verify this plugin's release history on origin" \
    "no-origin names the unverifiable probe"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "no-origin created no local tag"
assert_eq "$(cat "$GH_LOG")" "" "no-origin must not call gh"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release lost-tag scenarios passed\n'

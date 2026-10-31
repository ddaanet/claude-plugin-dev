#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: --resume's refusals and the hint each names -- virgin repo, missing tag,
# a different semver tag on origin, a lost local tag, no remote to probe, a
# healthy no-op.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-resume-hint-test.sh   (run from repo root)
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

echo "=== resume: on a virgin repo, the hint has no bump argument ==="
# Branch selected: the ladder's third branch (release_tags empty, origin
# probe empty too — origin_release_tags succeeds and returns nothing, since
# make_virgin drops the tag from origin as well as locally). Selected rather
# than the second branch because origin carries no semver tag at all to name,
# and rather than the fourth (today's default) because release_tags is empty:
# nothing local for that branch to point at.
new_sandbox ""
make_virgin "0.1.0"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "virgin resume exit code"
assert_contains "$out" "no tag v0.1.0 for plugin.json version 0.1.0" "virgin resume message"
# The needle is the backtick immediately after "release", with nothing
# between: `just release <bump>` has " <bump>" there instead, so this cannot
# match the bump form — see the substring-collision note in the report.
assert_contains "$out" 'just release`' "virgin resume hint names just release with no bump argument"
assert_not_contains "$out" "just release <bump>" "virgin resume hint must not advise the bump form"
assert_eq "$(cat "$GH_LOG")" "" "virgin resume must not call gh"

echo "=== resume: refuses when no tag exists for the manifest version ==="
# Branch selected: the ladder's first branch (v$V present on origin) — origin
# still holds v1.2.3, the tag lost only from this clone, and v1.2.3 IS $V
# here. Selected rather than the second branch (which fires only when origin's
# tag is some OTHER semver value than $V) and rather than the third or fourth
# (both local-only) because the origin probe has direct evidence for this
# exact version.
new_sandbox "1.2.3"
git -C "$plugin" tag -d v1.2.3 >/dev/null
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "no-tag resume exit code"
assert_contains "$out" "no tag v1.2.3 for plugin.json version 1.2.3" "no-tag resume message"
assert_contains "$out" "git fetch --tags" "no-tag resume hint names the fetch remedy"
assert_contains "$out" "just resume-release" "no-tag resume hint names resume-release, not a fresh release"
assert_not_contains "$out" "just release <bump>" "no-tag resume hint must not advise the bump form"
assert_eq "$(cat "$GH_LOG")" "" "no-tag resume must not call gh"

echo "=== resume: a different semver tag on origin than v\$V names the bump hint ==="
# Branch selected: the ladder's second branch — origin carries v1.2.3, which
# is a real semver tag but not $V ($V is 1.3.0 here). Selected rather than
# the first branch because origin's tag disagrees with $V, and rather than
# the third or fourth because origin DOES have evidence (unlike the virgin
# case above, where origin has nothing at all).
new_sandbox "1.3.0"
jq '.version = "1.3.0"' "$plugin/.claude-plugin/plugin.json" \
    > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" add -A
git -C "$plugin" commit -qm "hand-advance to 1.3.0"
git -C "$plugin" push -q origin main
lose_tag "$plugin"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "other-origin-tag resume exit code"
assert_contains "$out" "no tag v1.3.0 for plugin.json version 1.3.0" "other-origin-tag resume message"
assert_contains "$out" "git fetch --tags" "other-origin-tag resume hint names the fetch remedy"
assert_contains "$out" "just release <bump>" "other-origin-tag resume hint names the bump form"
assert_eq "$(cat "$GH_LOG")" "" "other-origin-tag resume must not call gh"

echo "=== resume: keeping the local tag while origin drops it still advises the bump form ==="
# Branch selected: the ladder's fourth branch (today's default, unchanged).
# Deleting origin's copy of v1.2.3 is what keeps this off the second branch —
# origin has no semver tag at all to name, exactly as in the virgin scenario
# above. What keeps it off the third branch (and so distinguishes it from
# that same virgin scenario) is that release_tags is NOT empty: v1.2.3 is
# still the local clone's own tag, kept rather than dropped.
new_sandbox "1.2.3"
git -C "$plugin" push -q origin :refs/tags/v1.2.3
jq '.version = "1.2.4"' "$plugin/.claude-plugin/plugin.json" \
    > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" add -A
git -C "$plugin" commit -qm "hand-advance to 1.2.4"
git -C "$plugin" push -q origin main
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "local-tag-survives resume exit code"
assert_contains "$out" "no tag v1.2.4 for plugin.json version 1.2.4" "local-tag-survives resume message"
assert_contains "$out" "just release <bump>" "local-tag-survives resume hint names the bump form"
assert_not_contains "$out" "git fetch --tags" \
    "local-tag-survives resume hint must not advise a fetch — origin has no evidence to fetch"
assert_eq "$(cat "$GH_LOG")" "" "local-tag-survives resume must not call gh"

echo "=== resume: refuses cleanly, with the local no-argument hint, when origin has no remote to probe ==="
# Branch selected: the ladder's third branch, reached the same way as the
# virgin scenario above (release_tags empty) but via a failed origin probe
# instead of a successful empty one — no "origin" remote exists at all, so
# origin_release_tags returns non-zero rather than an empty listing. Guards
# against an implementation that reads that listing in a bare substitution
# (errexit would kill the run before the die/hint ever print) or that treats
# a failed listing as fatal the way release_preflight's origin probe does —
# resume's probe only degrades advice, per the outline, it has no side effect
# to protect.
new_sandbox "1.2.3"
make_virgin "1.2.3"
git -C "$plugin" remote remove origin
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "no-origin resume exit code"
assert_contains "$out" "no tag v1.2.3 for plugin.json version 1.2.3" "no-origin resume message"
assert_contains "$out" 'just release`' "no-origin resume hint names just release with no bump argument"
assert_not_contains "$out" "could not verify this plugin's release history on origin" \
    "no-origin resume output carries no probe-failure wording"
assert_eq "$(cat "$GH_LOG")" "" "no-origin resume must not call gh"

echo "=== resume: origin's copy of v\$V outranks a local tag this clone still has ==="
# Pins the ORDER of the ladder, which the four scenarios above do not: every
# one of them has release_tags empty whenever origin carries evidence, so a
# ladder that tests "local tags present" FIRST and only then consults origin
# satisfies all four (measured — that permutation passes the four-scenario
# suite whole). Here the two disagree: v1.1.0 is still this clone's own tag,
# so release_tags is non-empty, while origin holds v1.2.3, which IS $V. The
# origin branch must win — advising a fresh bump release here would publish
# over the very tag origin already has.
new_sandbox "1.2.3"
git -C "$plugin" tag -a v1.1.0 -m "Release 1.1.0"
lose_tag "$plugin"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "origin-outranks-local resume exit code"
assert_contains "$out" "no tag v1.2.3 for plugin.json version 1.2.3" "origin-outranks-local resume message"
assert_contains "$out" "git fetch --tags" "origin-outranks-local resume hint names the fetch remedy"
assert_contains "$out" "just resume-release" "origin-outranks-local resume hint names resume-release"
assert_not_contains "$out" "just release <bump>" \
    "origin-outranks-local resume hint must not advise the bump form over origin's own v1.2.3"
assert_eq "$(cat "$GH_LOG")" "" "origin-outranks-local resume must not call gh"

echo "=== resume: v\$V among origin's tags counts even when a newer tag sorts above it ==="
# Pins that the first branch tests MEMBERSHIP of v$V in origin's listing, not
# equality against its newest line. In every scenario above, origin's listing
# is one tag long, so "contains v$V" and "newest is v$V" are the same
# predicate and a newest-only implementation passes them all (measured).
# Here origin carries v1.3.0 above v1.2.3 while $V is 1.2.3: a newest-only
# read sees "some other tag" and advises a bump release, over a v1.2.3 that
# origin demonstrably already has.
new_sandbox "1.2.3"
git -C "$plugin" tag -a v1.3.0 -m "Release 1.3.0"
git -C "$plugin" push -q origin v1.3.0
lose_tag "$plugin" v1.3.0
lose_tag "$plugin"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "origin-newer-tag resume exit code"
assert_contains "$out" "no tag v1.2.3 for plugin.json version 1.2.3" "origin-newer-tag resume message"
assert_contains "$out" "git fetch --tags" "origin-newer-tag resume hint names the fetch remedy"
assert_contains "$out" "just resume-release" "origin-newer-tag resume hint names resume-release"
assert_not_contains "$out" "just release <bump>" \
    "origin-newer-tag resume hint must not advise the bump form when origin holds v1.2.3 itself"
assert_eq "$(cat "$GH_LOG")" "" "origin-newer-tag resume must not call gh"

echo "=== resume: a failed local tag listing advises the bump form, not the bare one ==="
# Pins resume_preflight's no_local_tags flag, set only by a listing that
# SUCCEEDED and came back empty. Virgin fixture: origin lists nothing, so the
# elif chain reaches the local-evidence branches; a `git` wrapper fails only
# `tag --list` (release_tags's one read), so the listing fails rather than
# comes back empty. A fold of failure into the empty case routes to the bare
# `just release` hint (measured: that mutant passed every other suite).
# Origin is read with ls-remote, which the wrapper delegates untouched.
new_sandbox ""
make_virgin "0.1.0"
git_wrapper_dir="$sandbox/git-wrapper"
mkdir -p "$git_wrapper_dir"
real_git="$(command -v git)"
cat > "$git_wrapper_dir/git" <<STUB
#!/bin/sh
if [ "\$1" = "tag" ] && [ "\$2" = "--list" ]; then
    echo "git: fatal: stub git failing tag --list" >&2
    exit 1
fi
exec "$real_git" "\$@"
STUB
chmod +x "$git_wrapper_dir/git"
saved_path="$PATH"
export PATH="$git_wrapper_dir:$PATH"
run_in "$plugin" bash plugin-dev/release.sh --resume
export PATH="$saved_path"
assert_eq "$rc" "1" "failed-listing resume exit code"
assert_contains "$out" "no tag v0.1.0 for plugin.json version 0.1.0" "failed-listing resume message"
assert_contains "$out" "just release <bump>" "failed-listing resume hint names the bump form"
assert_not_contains "$out" 'just release`' "failed-listing resume hint must not advise the bare form"
assert_eq "$(cat "$GH_LOG")" "" "failed-listing resume must not call gh"

echo "=== resume: no-op on a healthy repo ==="
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "setup release exit code"
: > "$GH_LOG"
marketplace_head_before="$(git -C "$marketplace" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "healthy resume exit code"
assert_contains "$out" "already complete (nothing to do)" "healthy resume summary"
assert_contains "$(cat "$GH_LOG")" "release view v1.2.4" "healthy resume probed the release"
if grep -q "release create" "$GH_LOG"; then
    fail "healthy resume re-created the GitHub release"
fi
assert_eq "$(git -C "$marketplace" rev-parse HEAD)" "$marketplace_head_before" \
    "healthy resume left the marketplace untouched"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release resume-hint scenarios passed\n'

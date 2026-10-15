#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: the resume hint names the tag already on origin, at ordinary size and
# at 1MB of tag rows.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-hint-size-test.sh   (run from repo root)
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

echo "=== resume hint names the tag already on origin ==="
# Item 1.2, slice 1: the control. Proves the ladder in `resume_preflight`'s
# `git rev-parse -q --verify "refs/tags/$tag"` failure group is reached and
# that its first branch — v$V present in origin's semver listing — is the one
# that fires, via a `git` stub that controls `origin_release_tags`'s
# `ls-remote --tags --sort=-v:refname origin` output rather than real tags.
# Same stub idiom as the pipefail-stripped `tag --list` scenarios above,
# matched positionally on `ls-remote`/`--tags` and delegating everything else
# to the real binary.
#
# Slice 1 is the small-list control for Item 1.2's defect (N1): at a handful
# of synthetic tags, `printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"`
# in the ladder has time to finish writing before `grep -qxF` exits on its
# early match, so the SIGPIPE/pipefail hazard slice 2 exercises at >=1 MB does
# not manifest here — this scenario is expected to pass against unchanged
# `toolkit/release.sh` and establishes only that the fixture reaches the
# ladder and that branch 1 is the one that fires.
#
# Origin's real copy of v1.2.3 is deleted too, so the stub is the ONLY source
# of an origin listing: without it `origin_release_tags` comes back empty, the
# ladder falls through to its `no_local_tags` branch ("no release was started
# at this version" / "run `just release` instead") and both the branch-1
# assertion and the `just release` absence below fail. Left in place, origin's
# real tag would satisfy branch 1 by itself and every assertion here would hold
# with the stub never consulted — measured, and the reason slice 2 could not
# then trust its own listing size.
new_sandbox "1.2.3"
lose_tag "$plugin"
git -C "$plugin" push -q origin :refs/tags/v1.2.3
git_wrapper_dir="$sandbox/git-wrapper"
mkdir -p "$git_wrapper_dir"
real_git="$(command -v git)"
# The matching tag is emitted first, and the loop's range starts past it, so
# v1.2.3 appears exactly once: a duplicate would leave "first row matches"
# true by accident of the loop rather than by construction.
cat > "$git_wrapper_dir/git" <<STUB
#!/bin/sh
if [ "\$1" = "ls-remote" ] && [ "\$2" = "--tags" ]; then
    printf '%040d\trefs/tags/v1.2.3\n' 0
    seq 4 8 | while IFS= read -r n; do
        printf '%040d\trefs/tags/v1.2.%s\n' "\$n" "\$n"
    done
    exit 0
fi
exec "$real_git" "\$@"
STUB
chmod +x "$git_wrapper_dir/git"
saved_path="$PATH"
export PATH="$git_wrapper_dir:$PATH"
run_in "$plugin" bash plugin-dev/release.sh --resume
export PATH="$saved_path"
assert_eq "$rc" "1" "resume hint names the tag already on origin exit code"
assert_contains "$out" "origin already has v1.2.3" \
    "resume hint names the tag already on origin"
assert_contains "$out" "git fetch --tags" \
    "resume hint names the tag already on origin remedy"
assert_not_contains "$out" "just release" \
    "resume hint names the tag already on origin must not advise a fresh release"
assert_eq "$(cat "$GH_LOG")" "" "resume hint names the tag already on origin must not call gh"

echo "=== resume hint names the tag already on origin at 1MB ==="
# Item 1.2, slice 2: the genuine red. Same scenario shape as slice 1 above —
# same `lose_tag` + origin-tag-deletion fixture, same `git` stub idiom, same
# ladder in `resume_preflight`'s `git rev-parse -q --verify "refs/tags/$tag"`
# failure group — sized so the ladder's
# `printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"` hits the
# SIGPIPE/pipefail hazard (N1): at this size `printf` has not finished
# writing before `grep -qxF` exits on its first-line match, so
# `set -euo pipefail` promotes printf's SIGPIPE status 141 over grep's 0 and
# the ladder falls through past branch 1 to "origin has release tags, but
# none matching" — the wrong hint, advising `just release <bump>` on a
# release that origin already has.
new_sandbox "1.2.3"
lose_tag "$plugin"
git -C "$plugin" push -q origin :refs/tags/v1.2.3
git_wrapper_dir="$sandbox/git-wrapper"
mkdir -p "$git_wrapper_dir"
real_git="$(command -v git)"

# The rows the stub serves for `ls-remote --tags`, in one file so the stub
# and the size guard below run the identical generator and can never drift
# apart. One seq-backed printf, not ~100000 real `git tag` calls (minutes,
# per the runbook) — the matching tag first, then 100000 more rows from a
# single `seq`, each cycling the same two-conversion format string. The
# unquoted `$(seq …)` splits on whitespace by design and is safe for exactly
# one reason: seq emits nothing but digits and newlines.
cat > "$sandbox/origin-tag-rows.sh" <<'ROWS'
#!/bin/sh
printf '%040d\trefs/tags/v1.2.3\n' 0
printf '0000000000000000000000000000000000000000\trefs/tags/v1.2.%s\n' $(seq 4 100003)
ROWS
chmod +x "$sandbox/origin-tag-rows.sh"

cat > "$git_wrapper_dir/git" <<STUB
#!/bin/sh
if [ "\$1" = "ls-remote" ] && [ "\$2" = "--tags" ]; then
    "$sandbox/origin-tag-rows.sh"
    exit 0
fi
exec "$real_git" "\$@"
STUB
chmod +x "$git_wrapper_dir/git"

# Guard on the *post-filter* size, not the row count: origin_release_tags
# runs the rows through `cut -f2 | sed 's|^refs/tags/||'` and then
# semver_tags's own `grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'` before the ladder
# ever sees `$origin_tag_list`, and the >=1 MB bound (>=1048576 bytes) is on
# THAT output — sizing the stub by row count alone under-sizes the fixture by
# the ~5.7x the runbook measured (100000 tags: 6188895 raw bytes but only
# 1088895 bytes post-filter). Measured here directly, per the slice-1 test
# review's recommendation, so a later change that shrinks the fixture is loud
# — this assertion fails — rather than silently no longer exercising the
# hazard. grep's no-match 1 is absorbed exactly as semver_tags absorbs it
# (`{ grep … || [ "$?" -eq 1 ]; }`), so a fixture that stopped matching at all
# reports 0 bytes through this assertion instead of failing the pipeline and
# killing the suite silently under `set -euo pipefail`.
post_filter_size=$("$sandbox/origin-tag-rows.sh" | cut -f2 | sed 's|^refs/tags/||' \
    | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || [ "$?" -eq 1 ]; } | wc -c | tr -d ' ')
assert_eq "$([ "$post_filter_size" -ge 1048576 ] && echo yes || echo no)" "yes" \
    "resume hint names the tag already on origin at 1MB fixture clears the post-filter 1MB bound ($post_filter_size bytes)"

saved_path="$PATH"
export PATH="$git_wrapper_dir:$PATH"
run_in "$plugin" bash plugin-dev/release.sh --resume
export PATH="$saved_path"
assert_eq "$rc" "1" "resume hint names the tag already on origin at 1MB exit code"
assert_contains "$out" "origin already has v1.2.3" \
    "resume hint names the tag already on origin at 1MB"
assert_contains "$out" "git fetch --tags" \
    "resume hint names the tag already on origin at 1MB remedy"
assert_not_contains "$out" "just release" \
    "resume hint names the tag already on origin at 1MB must not advise a fresh release"
assert_eq "$(cat "$GH_LOG")" "" \
    "resume hint names the tag already on origin at 1MB must not call gh"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release hint-size scenarios passed\n'

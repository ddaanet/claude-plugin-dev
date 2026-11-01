#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: the origin probes failing closed with pipefail stripped from the
# sourced script.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-pipefail-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/release-pipefail.XXXXXX")"
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

echo "=== the origin probes fail closed with pipefail stripped ==="
# The three `git ls-remote origin <ref>` reads are captured whole and trimmed
# with a parameter expansion rather than piped into `cut`, because cut succeeds
# on the empty input a failed ls-remote hands it — so the failure would read as
# "the ref is not on origin", which is the answer every caller treats as licence
# to act. push_tag is the sharp one: absence there is what lets it push, so a
# misread walks past the refusal that keeps a published tag from being moved.
# `set -o pipefail` covers all three today, which is exactly why this runs a
# pipefail-stripped copy: a `set -o` line is easy to lose, and nothing else in
# the suite would notice.
new_sandbox "1.2.3"
nopipefail="$plugin/plugin-dev/release-nopipefail.sh"
sed '/^set -euo pipefail$/s//set -eu/' "$repo_root/toolkit/release.sh" > "$nopipefail"
grep -qx 'set -eu' "$nopipefail" || fail "pipefail-stripped copy: the set line was not rewritten"
git -C "$plugin" remote set-url origin "$sandbox/unreachable.git"
run_in "$plugin" bash plugin-dev/release-nopipefail.sh --resume
assert_eq "$rc" "1" "no-pipefail probe exit code"
assert_contains "$out" "git ls-remote origin refs/heads/main failed" \
    "no-pipefail probe reports the probe's own failure"
assert_contains "$out" "just resume-release" \
    "no-pipefail probe names the command that finishes the release"
assert_not_contains "$out" "push of main failed" \
    "no-pipefail probe refused before attempting the push"
assert_eq "$(cat "$GH_LOG")" "" "no-pipefail probe must not call gh"

echo "=== pipefail-stripped release_tags failure refuses ==="
# Item A1, slice 1. Mutation-must-go-red case for the release_tags() fix: under
# the stripped copy, a `git tag --list` failure must abort release_preflight
# rather than being absorbed by semver_tags's status-1 rescue and misread as
# "no tags yet". Today's body — `git tag --list 'v*' --sort=-v:refname |
# semver_tags` (release_tags()'s own comment: "Local semver release tags") —
# depends on `set -o pipefail` to carry that failure past the filter, exactly
# the property the origin-probes harness above strips to test the same class
# of hazard. A `git` wrapper here fails only `tag --list`, delegating every
# other call to the real binary: common_preflight runs ahead of
# release_preflight and makes git calls of its own, and release_tags holds the
# script's only `git tag --list`, so failing that one form targets exactly the
# read under test. The wrapper matches it positionally ($1/$2), which covers
# every `git tag --list` the script has; a `git -C … tag --list` would slip
# past, and none exists. `$real_git` is interpolated into the stub body, so a
# git path holding a quote, backslash or `$` would break it — a space is
# handled, since the emitted `exec` quotes it.
new_sandbox "1.2.3"
nopipefail_tags="$plugin/plugin-dev/release-nopipefail-tags.sh"
sed '/^set -euo pipefail$/s//set -eu/' "$repo_root/toolkit/release.sh" > "$nopipefail_tags"
grep -qx 'set -eu' "$nopipefail_tags" || fail "pipefail-stripped copy: the set line was not rewritten"
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
run_in "$plugin" bash plugin-dev/release-nopipefail-tags.sh patch
export PATH="$saved_path"
assert_eq "$rc" "1" "pipefail-stripped release_tags failure refuses exit code"
assert_contains "$out" "could not list this plugin's release tags" \
    "pipefail-stripped release_tags failure refuses names release_preflight's die"
assert_not_contains "$out" "git fetch --tags" \
    "pipefail-stripped release_tags failure refuses did not take the lost-tags branch"

echo "=== pipefail-stripped release_tags failure publishes nothing ==="
# Item A1, slice 2. Same stub idiom as the scenario above, but on a
# make_virgin fixture (no v* tag locally or on origin) rather than the
# already-released one: with real origin tags present, origin_release_tags
# (untouched by the stub) finds v1.2.3 and release_preflight's lost-tags
# branch ("local release tags are missing — refusing to guess whether ... was
# published") fires either way — the scenario above already proves that
# branch's wording, but it cannot exercise the sharper hazard, because that
# refusal also happens to leave nothing published. On a virgin plugin,
# origin_release_tags legitimately returns empty too, so a stripped copy that
# absorbs the `git tag --list` failure reaches release_preflight's
# `first_release=1` branch ("a plugin that has never been released has no
# last-released version to bump forward from") and actually tags, pushes and
# publishes v1.2.3 — the defect the item's mutation note names
# ("bump_commit_tag tags HEAD — publishing the manifest version of a plugin
# whose release history it could not read"), reachable only from a fixture
# where that branch is live. No bump argument: a first release refuses an
# explicit one before reaching bump_commit_tag, which would refuse for a
# reason unrelated to this defect.
#
# The three assertions below are all absences, so they would also hold if the
# run never reached the read under test — a broken fixture, or a stripped copy
# that died in common_preflight, publishes nothing either. The exit code and
# the die message pin that the refusal came from release_tags's own status,
# which is what makes those absences evidence.
new_sandbox "1.2.3"
make_virgin "1.2.3"
nopipefail_tags="$plugin/plugin-dev/release-nopipefail-tags.sh"
sed '/^set -euo pipefail$/s//set -eu/' "$repo_root/toolkit/release.sh" > "$nopipefail_tags"
grep -qx 'set -eu' "$nopipefail_tags" || fail "pipefail-stripped copy: the set line was not rewritten"
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
local_tags_before="$(git -C "$plugin" tag --list | sort)"
origin_tags_before="$(git -C "$plugin-origin.git" tag --list | sort)"
saved_path="$PATH"
export PATH="$git_wrapper_dir:$PATH"
run_in "$plugin" bash plugin-dev/release-nopipefail-tags.sh
export PATH="$saved_path"
assert_eq "$rc" "1" \
    "pipefail-stripped release_tags failure publishes nothing exit code"
assert_contains "$out" "could not list this plugin's release tags" \
    "pipefail-stripped release_tags failure publishes nothing refused at the tag read"
assert_eq "$(git -C "$plugin" tag --list | sort)" "$local_tags_before" \
    "pipefail-stripped release_tags failure publishes nothing local tag set unchanged"
assert_eq "$(git -C "$plugin-origin.git" tag --list | sort)" "$origin_tags_before" \
    "pipefail-stripped release_tags failure publishes nothing origin tag set unchanged"
assert_eq "$(cat "$GH_LOG")" "" \
    "pipefail-stripped release_tags failure publishes nothing gh log empty"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release pipefail scenarios passed\n'

#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: common_preflight refusing a diverged remote.origin.pushurl, for release
# and for resume with and without work to do. A branch.<b>.pushRemote or a
# remote.pushDefault no longer refuses: the release's pushes name origin, so the
# push still lands on origin and nothing reaches the other repository.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-push-route-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/release-push-route.XXXXXX")"
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

echo "=== release: common_preflight refuses a diverged remote.origin.pushurl ==="
# The redirect target's path carries a space deliberately: `pushurl` stores a
# filesystem path as its value, and the value is asserted verbatim against
# `$out`, so the space must survive `assert_contains`'s BRE read.
new_sandbox "1.2.3"
other="$sandbox/push-target repo.git"
git init -q --bare -b main "$other"
git -C "$plugin" config remote.origin.pushurl "$other"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "diverged-push-route (pushurl) exit code"
assert_contains "$out" "remote.origin.pushurl" "diverged-push-route (pushurl) names the setting"
assert_contains "$out" "$other" "diverged-push-route (pushurl) names the value"
assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
    "no" "diverged-push-route (pushurl) created no v1.2.4 tag"
assert_eq "$(cat "$GH_LOG")" "" "diverged-push-route (pushurl) must not call gh"
assert_eq "$(market_version)" "1.2.3" "diverged-push-route (pushurl) marketplace untouched"

echo "=== release: a set pushRemote or pushDefault no longer refuses, and the push lands on origin ==="
# Each names the remote an unqualified `git push` would use. The release's pushes
# name origin, so the set key changes nothing: the release lands on origin, and
# the redirect target receives no ref.
for setting in pushRemote pushDefault; do
    new_sandbox "1.2.3"
    other="$sandbox/push-target repo.git"
    git init -q --bare -b main "$other"
    git -C "$plugin" remote add pushtarget "$other"
    case "$setting" in
        pushRemote)  git -C "$plugin" config branch.main.pushRemote pushtarget ;;
        pushDefault) git -C "$plugin" config remote.pushDefault pushtarget ;;
    esac
    run_in "$plugin" bash plugin-dev/release.sh patch
    assert_eq "$rc" "0" "set $setting: exit code"
    rel="$(git -C "$plugin" rev-parse -q --verify 'refs/tags/v1.2.4^{commit}')"
    origin_main="$(git -C "$plugin-origin.git" rev-parse -q --verify refs/heads/main || true)"
    assert_eq "$origin_main" "$rel" "set $setting: origin main at the release"
    origin_tag="$(git -C "$plugin-origin.git" rev-parse -q --verify 'refs/tags/v1.2.4^{commit}' || true)"
    assert_eq "$origin_tag" "$rel" "set $setting: origin has the tag at the release"
    push_target_refs="$(git -C "$other" for-each-ref --format='%(refname)')"
    assert_eq "$push_target_refs" "" "set $setting: nothing reached the redirect target"
    assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "set $setting: GitHub release created"
    assert_eq "$(market_version)" "1.2.4" "set $setting: marketplace bumped"
done

echo "=== resume: common_preflight refuses a diverged remote.origin.pushurl ==="
# The setup release must succeed, or the refusal below would be the only thing
# this scenario observes: nothing downstream would notice a broken fixture.
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "resume-push-route setup release exit code"
: > "$GH_LOG"
other="$sandbox/push-target repo.git"
git init -q --bare -b main "$other"
git -C "$plugin" config remote.origin.pushurl "$other"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "resume diverged-push-route exit code"
assert_contains "$out" "remote.origin.pushurl" "resume diverged-push-route names the setting"
assert_contains "$out" "$other" "resume diverged-push-route names the value"
# The refusal's own reason, not just the key and value: a successful push through
# a pushurl echoes `To <path>` onto stderr, which run_in folds into $out.
assert_contains "$out" "push route diverges from origin" "resume diverged-push-route names the refusal"
assert_eq "$(cat "$GH_LOG")" "" "resume diverged-push-route must not call gh"

echo "=== resume: a diverged pushurl is refused before a resume that HAS work to do ==="
# Here the resume has real work: the commit and tag landed locally and nothing
# was pushed. With the check deleted, push_branch would push main straight into
# the redirect target, so the assertion is on that target's ref list.
new_sandbox "1.2.3"
cat > "$plugin/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
echo "pre-push: refusing" >&2
exit 1
HOOK
chmod +x "$plugin/.git/hooks/pre-push"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "resume-with-work (pushurl) setup release exit code"
assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
    "yes" "resume-with-work (pushurl) setup left the tag local"
rm -f "$plugin/.git/hooks/pre-push"
: > "$GH_LOG"
other="$sandbox/push-target repo.git"
git init -q --bare -b main "$other"
git -C "$plugin" config remote.origin.pushurl "$other"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "resume-with-work (pushurl) exit code"
assert_contains "$out" "push route diverges from origin" "resume-with-work (pushurl) names the refusal"
push_target_refs="$(git -C "$other" for-each-ref --format='%(refname)')"
assert_eq "$push_target_refs" "" "resume-with-work (pushurl) wrote nothing to the redirect target"
assert_eq "$(cat "$GH_LOG")" "" "resume-with-work (pushurl) must not call gh"
assert_eq "$(market_version)" "1.2.3" "resume-with-work (pushurl) marketplace untouched"

echo "=== resume: a set pushRemote or pushDefault does not stop a resume with work to do ==="
# The same local-only tag, then the key is set and the resume finishes on origin.
for setting in pushRemote pushDefault; do
    new_sandbox "1.2.3"
    cat > "$plugin/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
echo "pre-push: refusing" >&2
exit 1
HOOK
    chmod +x "$plugin/.git/hooks/pre-push"
    run_in "$plugin" bash plugin-dev/release.sh patch
    assert_eq "$rc" "1" "resume-with-work ($setting) setup release exit code"
    rm -f "$plugin/.git/hooks/pre-push"
    : > "$GH_LOG"
    other="$sandbox/push-target repo.git"
    git init -q --bare -b main "$other"
    git -C "$plugin" remote add pushtarget "$other"
    case "$setting" in
        pushRemote)  git -C "$plugin" config branch.main.pushRemote pushtarget ;;
        pushDefault) git -C "$plugin" config remote.pushDefault pushtarget ;;
    esac
    run_in "$plugin" bash plugin-dev/release.sh --resume
    assert_eq "$rc" "0" "resume-with-work ($setting) exit code"
    rel="$(git -C "$plugin" rev-parse -q --verify 'refs/tags/v1.2.4^{commit}')"
    origin_main="$(git -C "$plugin-origin.git" rev-parse -q --verify refs/heads/main || true)"
    assert_eq "$origin_main" "$rel" "resume-with-work ($setting) origin main at the release"
    push_target_refs="$(git -C "$other" for-each-ref --format='%(refname)')"
    assert_eq "$push_target_refs" "" "resume-with-work ($setting) wrote nothing to the redirect target"
    assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "resume-with-work ($setting) GitHub release created"
done

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release push-route scenarios passed\n'

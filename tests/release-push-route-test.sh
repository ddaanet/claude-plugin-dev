#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: common_preflight refusing a diverged push route, for release and for
# resume with and without work to do.
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

echo "=== release: common_preflight refuses a diverged push route ==="
# `git config --get` exits 1 when the key is unset; a GREEN implementation
# must read that status and treat it as "not diverged", not fail closed on
# every unset key — none of the three keys below is set in a healthy fixture,
# so a naive implementation that failed on ANY non-zero status would also
# break the happy-path scenario above, not just this one. Residual bound:
# this loop does not tell "absorbs status 1 only" from "absorbs every
# non-zero status", and nothing else can either — the only way to make
# `git config --get` fail with anything but 1 is a config file git cannot
# parse, and that makes EVERY git call exit 128 (verified: symbolic-ref,
# status and diff all die identically), so the run refuses whatever the
# push-route read does with the status. The discipline is a code-review
# check on the GREEN, not a scenario.
#
# The redirect target's path carries a space deliberately: `pushurl` stores a
# filesystem path as its value, and the value is asserted verbatim against
# `$out` — `assert_contains`'s BRE read of that value must not choke on the
# space.
#
# The remote is named `pushtarget` and NOT `other`: for pushRemote and
# pushDefault the config value IS the remote name, so that name is the needle
# the "names the value" assertion greps for. `other` is a substring of
# `another`, and a refusal saying "pushes to another repository" — naming the
# key and not the value — passed that assertion. Verified: with `other`, a
# key-only GREEN using that wording failed 1 of 3 value assertions; with
# `pushtarget` it fails all 3. The needle must be a token no English refusal
# message can contain. The directory keeps a hyphen (`push-target repo.git`)
# so the pushurl path is not itself a match for the pushRemote needle.
for setting in pushurl pushRemote pushDefault; do
    new_sandbox "1.2.3"
    other="$sandbox/push-target repo.git"
    git init -q --bare -b main "$other"
    # Sentinels, not empty strings: a `case` arm added later without setting
    # these must fail loudly. An empty needle would make `grep -q` match
    # anything and the assertion would pass on a stale value from the
    # previous iteration.
    key="NO-CASE-ARM-SET-key"
    value="NO-CASE-ARM-SET-value"
    case "$setting" in
        pushurl)
            git -C "$plugin" config remote.origin.pushurl "$other"
            key="remote.origin.pushurl"
            value="$other"
            ;;
        pushRemote)
            # pushRemote and pushDefault take a remote *name*, not a path —
            # the redirect target must exist as a named remote first.
            git -C "$plugin" remote add pushtarget "$other"
            git -C "$plugin" config branch.main.pushRemote pushtarget
            key="branch.main.pushRemote"
            value="pushtarget"
            ;;
        pushDefault)
            git -C "$plugin" remote add pushtarget "$other"
            git -C "$plugin" config remote.pushDefault pushtarget
            key="remote.pushDefault"
            value="pushtarget"
            ;;
    esac
    run_in "$plugin" bash plugin-dev/release.sh patch
    assert_eq "$rc" "1" "diverged-push-route ($setting) exit code"
    assert_contains "$out" "$key" "diverged-push-route ($setting) names the setting"
    assert_contains "$out" "$value" "diverged-push-route ($setting) names the value"
    assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
        "no" "diverged-push-route ($setting) created no v1.2.4 tag"
    assert_eq "$(cat "$GH_LOG")" "" "diverged-push-route ($setting) must not call gh"
    assert_eq "$(market_version)" "1.2.3" "diverged-push-route ($setting) marketplace untouched"
done

echo "=== resume: common_preflight refuses a diverged push route ==="
# Same predicate as the release-mode block above, reached through --resume
# instead of `release`: outline.md decision 3 requires the refusal on both
# modes, and common_preflight runs unconditionally before the
# release/resume branch (`5fa9e0d`'s :714), so nothing resume-specific
# should be needed to reach it.
#
# The fixture is deliberately "healthy" in the sense that matters: a real,
# completed release already sits on origin, so an unmodified --resume here
# has somewhere to go and something to say — see "resume: no-op on a
# healthy repo" above, which is this exact setup without the diverged
# route, and which DOES call `gh release view v1.2.4` and reports
# "already complete (nothing to do)". Establishing that first is what makes
# `$GH_LOG` empty below a real assertion about ordering (refused before any
# resume probing) rather than an accident of resume having nothing to do
# for an unrelated reason.
#
# The setup's exit code is asserted because nothing downstream would notice a
# broken fixture: the push-route check is the first thing common_preflight
# does after the clean-tree and branch checks, so ANY fixture with pushurl set
# produces exit 1, the key, the value and an empty $GH_LOG — verified against a
# sandbox whose setup release died at `gh release create`, where all four
# behaviour assertions below still passed. The setup assertion is the only
# thing pinning the "healthy repo" the paragraph above claims.
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
# The refusal's own reason, not just the key and value. `$other` is a
# filesystem path, and a successful `git push` through a pushurl echoes
# `To <path>` onto stderr, which run_in folds into $out — so "names the value"
# alone can be satisfied by the very push this check exists to prevent
# (measured: under a release.sh with the check deleted outright, slice 1's
# `diverged-push-route (pushurl) names the value` assertion PASSES on a
# release that pushed to the wrong repo). Pinning the reason means no future
# refusal that merely mentions the key — a resume-specific guard, say — can
# stand in for this one.
assert_contains "$out" "push route diverges from origin" "resume diverged-push-route names the refusal"
assert_eq "$(cat "$GH_LOG")" "" "resume diverged-push-route must not call gh"

echo "=== resume: a diverged push route is refused before a resume that HAS work to do ==="
# The scenario above establishes the refusal on a resume with nothing left to
# do, where an empty $GH_LOG is weak evidence of ordering: push_branch would
# report "already pushed" and push_tag "already pushed" even with the check
# deleted, so gh is the first step that could have been reached. Here the
# resume has real work — the commit and tag landed locally and NOTHING was
# pushed — so with the check deleted push_branch would push main straight into
# the redirect target. The assertion is on that target's ref list, which is the
# only thing that tells "refused before any side effect" from "refused before
# gh". All three settings, because they do not redirect the same commands:
# push_branch's unqualified `git push` follows all three, while push_tag's
# `git push origin <tag>` follows only pushurl.
for setting in pushurl pushRemote pushDefault; do
    new_sandbox "1.2.3"
    cat > "$plugin/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
echo "pre-push: refusing" >&2
exit 1
HOOK
    chmod +x "$plugin/.git/hooks/pre-push"
    run_in "$plugin" bash plugin-dev/release.sh patch
    assert_eq "$rc" "1" "resume-with-work ($setting) setup release exit code"
    # The setup's whole point: a tag that exists locally and nowhere else, so
    # the resume below genuinely reaches push_branch unless something stops it.
    assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
        "yes" "resume-with-work ($setting) setup left the tag local"
    rm -f "$plugin/.git/hooks/pre-push"
    : > "$GH_LOG"
    other="$sandbox/push-target repo.git"
    git init -q --bare -b main "$other"
    case "$setting" in
        pushurl)     git -C "$plugin" config remote.origin.pushurl "$other" ;;
        pushRemote)  git -C "$plugin" remote add pushtarget "$other"
                     git -C "$plugin" config branch.main.pushRemote pushtarget ;;
        pushDefault) git -C "$plugin" remote add pushtarget "$other"
                     git -C "$plugin" config remote.pushDefault pushtarget ;;
    esac
    run_in "$plugin" bash plugin-dev/release.sh --resume
    assert_eq "$rc" "1" "resume-with-work ($setting) exit code"
    assert_contains "$out" "push route diverges from origin" \
        "resume-with-work ($setting) names the refusal"
    # A bare assignment, not a substitution inside the assertion: the suite runs
    # under set -euo pipefail, so a for-each-ref that fails aborts loudly here
    # instead of yielding "" and passing this vacuously.
    push_target_refs="$(git -C "$other" for-each-ref --format='%(refname)')"
    assert_eq "$push_target_refs" "" \
        "resume-with-work ($setting) wrote nothing to the redirect target"
    assert_eq "$(cat "$GH_LOG")" "" "resume-with-work ($setting) must not call gh"
    assert_eq "$(market_version)" "1.2.3" "resume-with-work ($setting) marketplace untouched"
done

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release push-route scenarios passed\n'

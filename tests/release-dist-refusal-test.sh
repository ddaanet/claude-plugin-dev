#!/usr/bin/env bash
# End-to-end test of release.sh's dist publishing against real git repos in a
# temp dir: the pre-flight validation, the dist branch and its tag, the
# marketplace `ref`, the resume paths and the not-opted-in case. Same fixture
# shape as release-core-test.sh: origins are local bare repos, `gh` is a stub on
# PATH, and so is `claude`, which logs its argv and exits with a status taken
# from CLAUDE_STUB_RC. The fixture plugin opts in with a committed
# dist.include and carries a dev file (plans/x.md) outside the list.
#
# Scope: what a dist release refuses and leaves alone -- a foreign or a local dist
# tag, a rejected dist push (never forced), a tree refusal from dist.sh before
# any commit. Its siblings release-dist-publish-test.sh,
# release-dist-resume-test.sh and release-dist-optin-test.sh cover the publish,
# resume and opt-in handling.
#
# Usage: bash tests/release-dist-refusal-test.sh   (run from repo root)
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

base_path="$PATH"
real_git="$(type -P git)"

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
    # $1=haystack $2=needle $3=label : a fixed string, matched line by line.
    # A here-string, never a pipe: under pipefail grep -q exits on its first
    # match, the writer can take SIGPIPE, and the pipeline reports failure.
    if ! grep -qF -- "$2" <<<"$1"; then
        fail "$3: output did not contain '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}
assert_not_contains() {
    # $1=haystack $2=needle $3=label
    if grep -qF -- "$2" <<<"$1"; then
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
    # $2=optin: "optin" commits a dist.include, anything else leaves it out.
    # Sets $sandbox, $plugin, $origin, $marketplace; exports MARKETPLACE_DIR,
    # PATH, GH_*, CLAUDE_*. The git wrapper in $sandbox/wrap fails a push whose
    # arguments match $FAIL_PUSH_GLOB and is a pass-through otherwise.
    local entry_version="$1" optin="${2:-optin}"
    sandbox="$(mktemp -d)"
    sandboxes+=("$sandbox")
    plugin="$sandbox/plugin"
    origin="$plugin-origin.git"
    marketplace="$sandbox/marketplace"

    mkdir -p "$sandbox/bin" "$sandbox/wrap" "$sandbox/releases"
    cat > "$sandbox/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
    "release view")   [ -f "$GH_RELEASES/$3" ] || exit 1 ;;
    "release create") [ -z "${GH_FAIL_CREATE:-}" ] || exit 1; : > "$GH_RELEASES/$3" ;;
    *) printf 'gh stub: unhandled: %s\n' "$*" >&2; exit 127 ;;
esac
STUB
    cat > "$sandbox/bin/claude" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >> "$CLAUDE_LOG"
exit "${CLAUDE_STUB_RC:-0}"
STUB
    cat > "$sandbox/wrap/git" <<STUB
#!/bin/sh
# Logs every push's argv to push.log. Refuses a push whose arguments match
# \$FAIL_PUSH_GLOB. The suite relies on release.sh pushing the dist branch and
# the dist tag separately, and the tag push naming dist-v<V> in its arguments.
is_push=0
hit=0
for a in "\$@"; do
    [ "\$a" = push ] && is_push=1
    if [ -n "\${FAIL_PUSH_GLOB:-}" ]; then
        case "\$a" in \$FAIL_PUSH_GLOB) hit=1 ;; esac
    fi
done
[ "\$is_push" = 1 ] && echo "\$*" >> "$sandbox/push.log"
if [ "\$is_push" = 1 ] && [ "\$hit" = 1 ]; then
    echo "git: stub refusing this push" >&2
    exit 1
fi
exec "$real_git" "\$@"
STUB
    chmod +x "$sandbox/bin/gh" "$sandbox/bin/claude" "$sandbox/wrap/git"
    export GH_LOG="$sandbox/gh.log"
    export GH_RELEASES="$sandbox/releases"
    export CLAUDE_LOG="$sandbox/claude.log"
    export CLAUDE_STUB_RC=0
    unset GH_FAIL_CREATE FAIL_PUSH_GLOB
    : > "$GH_LOG"
    : > "$sandbox/push.log"
    export PATH="$sandbox/bin:$sandbox/wrap:$base_path"

    git_init "$plugin"
    mkdir -p "$plugin/.claude-plugin" "$plugin/plugin-dev" "$plugin/skills/demo" "$plugin/plans"
    cat > "$plugin/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.2.3",
  "description": "test fixture",
  "license": "MIT"
}
JSON
    printf 'word %.0s' $(seq 1 45) > "$plugin/README.md"
    printf '\n' >> "$plugin/README.md"
    printf '# demo skill\n' > "$plugin/skills/demo/SKILL.md"
    printf 'a plan, not shipped\n' > "$plugin/plans/x.md"
    if [ "$optin" = optin ]; then
        printf '%s\n' .claude-plugin README.md skills > "$plugin/dist.include"
    fi
    cp "$repo_root"/toolkit/*.sh "$plugin/plugin-dev/"
    git -C "$plugin" add -A
    git -C "$plugin" commit -qm "init"
    git -C "$plugin" tag -a v1.2.3 -m "Release 1.2.3"
    git -C "$plugin" push -q -u origin main
    git -C "$plugin" push -q origin v1.2.3
    git -C "$plugin" remote set-head origin main

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

# no_claude_path: build $sandbox/nobin, a directory of symlinks to the tools
# release.sh needs and to nothing else, so the system's real claude cannot be
# found through it. gh is the sandbox stub. Sets $nobin.
no_claude_path() {
    local t p
    nobin="$sandbox/nobin"
    mkdir -p "$nobin"
    for t in git bash sh env jq mktemp tar sed awk grep cat tr wc sort cut head tail rm \
        mkdir dirname basename find xargs od ls cp mv date uniq tee readlink realpath \
        chmod ln cmp stat expr gzip printf sleep touch true false test; do
        p="$(PATH="$base_path" type -P "$t" 2>/dev/null || true)"
        if [[ -n "$p" ]]; then ln -s "$p" "$nobin/$t"; fi
    done
    ln -s "$sandbox/bin/gh" "$nobin/gh"
    assert_eq "$(PATH="$nobin" type -P claude 2>/dev/null || true)" "" \
        "fixture: no claude reachable on the stripped PATH"
}

# --- origin readers: the end state is read from origin, never the clone ---

origin_sha() {
    # $1=full ref name. Empty when origin lacks it.
    git ls-remote "$origin" "$1" | cut -f1
}

origin_release_commit() {
    # $1=version. The commit the release tag v$1 names on origin.
    git -C "$origin" rev-parse "refs/tags/v$1^{commit}" 2>/dev/null || true
}

entry_source() {
    # The marketplace entry's source, keys sorted, on one line.
    jq -S -c '.plugins[] | select(.name=="fixture") | .source' \
        "$marketplace/.claude-plugin/marketplace.json"
}

state_snapshot() {
    # Everything a refused release must leave alone, as one string: the clone's
    # HEAD, tags and manifest version, origin's refs, the marketplace file.
    printf '%s\n%s\n%s\n%s\n%s\n' \
        "$(git -C "$plugin" rev-parse HEAD)" \
        "$(git -C "$plugin" tag --list | sort | tr '\n' ' ')" \
        "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" \
        "$(git ls-remote "$origin" | sort)" \
        "$(cat "$marketplace/.claude-plugin/marketplace.json")"
}

expect_published() {
    # $1=version $2=expected dist commit count on origin $3=label.
    # The whole dist end state at origin for release $1.
    local v="$1" count="$2" label="$3" tip tag_sha rel parents
    tip="$(origin_sha refs/heads/dist)"
    rel="$(origin_release_commit "$v")"
    if [[ -z "$tip" ]]; then
        fail "$label: origin has no refs/heads/dist"
        return
    fi
    assert_eq "$(git -C "$origin" rev-list --count "$tip" 2>/dev/null || true)" "$count" \
        "$label: dist commit count"
    assert_eq "$(git -C "$origin" log -1 --format=%s "$tip" 2>/dev/null || true)" \
        "dist v$v from $rel" "$label: dist commit message names the release commit"
    assert_eq "$(git -C "$origin" ls-tree -r --name-only -z "$tip" 2>/dev/null \
        | LC_ALL=C sort -z | tr '\0' '|' || true)" \
        ".claude-plugin/plugin.json|README.md|skills/demo/SKILL.md|" \
        "$label: dist tree holds exactly the listed paths"
    assert_eq "$(git -C "$origin" show "$tip:.claude-plugin/plugin.json" 2>/dev/null \
        | jq -r .version || true)" "$v" "$label: shipped manifest carries the release version"
    # dist-v<V>: one line from ls-remote (no ^{} peel), at the dist commit, and
    # a commit object, not a tag object.
    assert_eq "$(git ls-remote "$origin" "refs/tags/dist-v$v*" | wc -l | tr -d ' ')" "1" \
        "$label: dist-v$v is a lightweight tag (no peeled line)"
    tag_sha="$(origin_sha "refs/tags/dist-v$v")"
    assert_eq "$tag_sha" "$tip" "$label: dist-v$v points at the dist tip"
    assert_eq "$(git -C "$origin" cat-file -t "refs/tags/dist-v$v" 2>/dev/null || true)" "commit" \
        "$label: dist-v$v names a commit directly"
    parents="$(git -C "$origin" rev-list --parents -n1 "$tip" 2>/dev/null | wc -w | tr -d ' ' || true)"
    if [[ "$count" = 1 ]]; then
        assert_eq "$parents" "1" "$label: first dist commit is a root"
    else
        assert_eq "$parents" "2" "$label: dist commit has one parent"
    fi
    assert_eq "$(jq -r '.plugins[] | select(.name=="fixture") | .source.ref' \
        "$marketplace/.claude-plugin/marketplace.json")" "dist" "$label: marketplace entry ref"
    assert_eq "$(jq -r '.plugins[] | select(.name=="fixture") | .version' \
        "$marketplace/.claude-plugin/marketplace.json")" "$v" "$label: marketplace entry version"
}

assert_no_force() {
    # $1=label. No push of this sandbox carried a force flag or a +refspec.
    local n
    # -f alone or in a short-flag cluster (-fq), and every --force spelling,
    # --force-with-lease=<ref> included.
    n="$(grep -Ecs '(^| )(-[a-zA-Z]*f[a-zA-Z]*|--force[a-z-]*(=[^ ]*)?|\+[^ ]+)( |$)' "$sandbox/push.log" || true)"
    assert_eq "${n:-0}" "0" "$1: no push was forced"
}

tweak_commit() {
    # $1=message. Commit the fixture's pending changes and push main, leaving
    # the clone clean and in step with origin.
    git -C "$plugin" add -A
    git -C "$plugin" commit -qm "$1"
    git -C "$plugin" push -q origin main
}

marketplace_version() {
    jq -r '.plugins[] | select(.name=="fixture") | .version' \
        "$marketplace/.claude-plugin/marketplace.json"
}

echo "=== foreign dist tag on origin: refused, nothing moved ==="
new_sandbox "1.2.3"
foreign="$(git -C "$plugin" commit-tree -m foreign "$(git -C "$plugin" mktree </dev/null)")"
git -C "$plugin" push -q origin "$foreign:refs/tags/dist-v1.2.4"
assert_eq "$(origin_sha refs/tags/dist-v1.2.4)" "$foreign" "foreign tag fixture: planted on origin"
run_in "$plugin" bash plugin-dev/release.sh patch
if [[ "$rc" = 0 ]]; then fail "foreign dist tag: release did not refuse"; fi
assert_contains "$out" "dist-v1.2.4" "foreign dist tag: message names the tag"
assert_eq "$(origin_sha refs/tags/dist-v1.2.4)" "$foreign" "foreign dist tag: origin's tag did not move"
local_dist_tag="$(git -C "$plugin" rev-parse -q --verify refs/tags/dist-v1.2.4 || true)"
if [[ -n "$local_dist_tag" && "$local_dist_tag" != "$foreign" ]]; then
    fail "foreign dist tag: the local dist-v1.2.4 was created at another sha: $local_dist_tag"
fi
# The conflicting tag is probed before the branch is pushed, so a refusal
# leaves no orphan dist commit on origin.
assert_eq "$(origin_sha refs/heads/dist)" "" "foreign dist tag: no dist branch on origin"
assert_eq "$([ -f "$GH_RELEASES/v1.2.4" ] && echo yes || echo no)" "no" \
    "foreign dist tag: no github release was created"
assert_eq "$(jq -r '.plugins[] | select(.name=="fixture") | .version' \
    "$marketplace/.claude-plugin/marketplace.json")" "1.2.3" "foreign dist tag: marketplace not bumped"

echo "=== a local dist tag at another sha: refused, nothing moved ==="
new_sandbox "1.2.3"
foreign="$(git -C "$plugin" commit-tree -m foreign "$(git -C "$plugin" mktree </dev/null)")"
git -C "$plugin" tag dist-v1.2.4 "$foreign"
run_in "$plugin" bash plugin-dev/release.sh patch
if [[ "$rc" = 0 ]]; then fail "local foreign dist tag: release did not refuse"; fi
assert_contains "$out" "dist-v1.2.4" "local foreign dist tag: message names the tag"
assert_eq "$(git -C "$plugin" rev-parse refs/tags/dist-v1.2.4)" "$foreign" "local foreign dist tag: local tag did not move"
assert_eq "$(origin_sha refs/tags/dist-v1.2.4)" "" "local foreign dist tag: nothing for it on origin"
assert_eq "$(origin_sha refs/heads/dist)" "" "local foreign dist tag: no dist branch on origin"
assert_eq "$([ -f "$GH_RELEASES/v1.2.4" ] && echo yes || echo no)" "no" "local foreign dist tag: no github release"

echo "=== a rejected dist push: hint names resume-release, never forced ==="
new_sandbox "1.2.3"
cat > "$origin/hooks/pre-receive" <<'HOOK'
#!/bin/sh
while read -r old new ref; do
    if [ "$ref" = refs/heads/dist ]; then
        echo "pre-receive: dist rejected" >&2
        exit 1
    fi
done
exit 0
HOOK
chmod +x "$origin/hooks/pre-receive"
run_in "$plugin" bash plugin-dev/release.sh patch
if [[ "$rc" = 0 ]]; then fail "rejected dist push: release did not fail"; fi
assert_contains "$out" "resume-release" "rejected dist push: hint names resume-release"
assert_eq "$(origin_sha refs/heads/dist)" "" "rejected dist push: no dist branch on origin"
assert_eq "$(origin_sha refs/tags/dist-v1.2.4)" "" "rejected dist push: no dist tag on origin"
assert_eq "$([ -f "$GH_RELEASES/v1.2.4" ] && echo yes || echo no)" "no" "rejected dist push: no github release"
assert_eq "$(marketplace_version)" "1.2.3" "rejected dist push: marketplace not bumped"
assert_eq "$(grep -c 'refs/heads/dist' "$sandbox/push.log" || true)" "1" \
    "rejected dist push: exactly one push targeted refs/heads/dist (no retry)"
assert_no_force "rejected dist push"
rm -f "$origin/hooks/pre-receive"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "resume after a rejected dist push: exit code"
expect_published 1.2.4 1 "resume after a rejected dist push"
assert_no_force "resume after a rejected dist push"

echo "=== pre-flight: a tree refusal from dist.sh refuses the release before any commit ==="
for variant in missing-path symlink; do
    new_sandbox "1.2.3"
    case "$variant" in
        missing-path) printf 'nothere/file.md\n' >> "$plugin/dist.include"; needle="nothere/file.md" ;;
        symlink)      ln -s ../README.md "$plugin/skills/link.md"; needle="link.md" ;;
    esac
    tweak_commit "break the tree ($variant)"
    before="$(state_snapshot)"
    run_in "$plugin" bash plugin-dev/release.sh patch
    assert_eq "$rc" "1" "tree refusal ($variant): exit code"
    assert_contains "$out" "$needle" "tree refusal ($variant): message names the offender"
    assert_eq "$(state_snapshot)" "$before" "tree refusal ($variant): clone, origin and marketplace untouched"
    assert_eq "$([ -s "$CLAUDE_LOG" ] && echo called || echo never)" "never" \
        "tree refusal ($variant): validation never reached"
    assert_eq "$(cat "$GH_LOG")" "" "tree refusal ($variant): gh not called"
done

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release dist refusal scenarios passed\n'

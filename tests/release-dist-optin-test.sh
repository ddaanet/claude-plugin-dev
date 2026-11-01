#!/usr/bin/env bash
# End-to-end test of release.sh's dist publishing against real git repos in a
# temp dir: the pre-flight validation, the dist branch and its tag, the
# marketplace `ref`, the resume paths and the not-opted-in case. Same fixture
# shape as release-core-test.sh: origins are local bare repos, `gh` is a stub on
# PATH, and so is `claude`, which logs its argv and exits with a status taken
# from CLAUDE_STUB_RC. The fixture plugin opts in with a committed
# dist.include and carries a dev file (plans/x.md) outside the list.
#
# Scope: how opt-in is read -- from the release commit on resume, not from HEAD --
# a complete release's resume leaving the marketplace byte-identical, and a
# release that is not opted in. Its siblings release-dist-publish-test.sh,
# release-dist-resume-test.sh and release-dist-refusal-test.sh cover the publish,
# resume and refusals.
#
# Usage: bash tests/release-dist-optin-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/release-dist-optin.XXXXXX")"
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

echo "=== resume: opt-in is read from the release commit, not from HEAD ==="
new_sandbox "1.2.3"
export FAIL_PUSH_GLOB='*:refs/heads/dist'
run_in "$plugin" bash plugin-dev/release.sh patch
unset FAIL_PUSH_GLOB
if [[ "$rc" = 0 ]]; then fail "opt-in from the tag: the release was not interrupted"; fi
git -C "$plugin" rm -q dist.include
tweak_commit "drop the allowlist after the release commit"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "opt-in dropped after the tag: resume exit code"
expect_published 1.2.4 1 "opt-in dropped after the tag"

new_sandbox "1.2.3" plain
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "opt-in added after the tag: setup release exit code"
printf '%s\n' .claude-plugin README.md skills > "$plugin/dist.include"
tweak_commit "add an allowlist after the release commit"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "opt-in added after the tag: resume exit code"
assert_contains "$out" "already complete (nothing to do)" "opt-in added after the tag: nothing to do"
assert_eq "$(origin_sha refs/heads/dist)" "" "opt-in added after the tag: no dist branch"
assert_eq "$([ -s "$CLAUDE_LOG" ] && echo called || echo never)" "never" "opt-in added after the tag: claude never called"

echo "=== a complete release: resume leaves the marketplace byte-identical ==="
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "no-op guard setup release exit code"
cp "$marketplace/.claude-plugin/marketplace.json" "$sandbox/marketplace.before"
mp_head="$(git -C "$marketplace" rev-parse HEAD)"
mp_origin_head="$(git ls-remote "$marketplace-origin.git" refs/heads/main | cut -f1)"
dist_refs="$(git ls-remote "$origin" | sort)"
for pass in 1 2; do
    run_in "$plugin" bash plugin-dev/release.sh --resume
    assert_eq "$rc" "0" "no-op guard resume $pass: exit code"
    assert_contains "$out" "already complete (nothing to do)" "no-op guard resume $pass: nothing to do"
    if ! cmp -s "$sandbox/marketplace.before" "$marketplace/.claude-plugin/marketplace.json"; then
        fail "no-op guard resume $pass: marketplace.json changed"
    fi
    assert_eq "$(git -C "$marketplace" rev-parse HEAD)" "$mp_head" "no-op guard resume $pass: marketplace HEAD unchanged"
    assert_eq "$(git ls-remote "$marketplace-origin.git" refs/heads/main | cut -f1)" "$mp_origin_head" \
        "no-op guard resume $pass: marketplace origin unchanged"
    assert_eq "$(git ls-remote "$origin" | sort)" "$dist_refs" "no-op guard resume $pass: plugin origin unchanged"
done
assert_eq "$(entry_source)" '{"ref":"dist","repo":"o/fixture","source":"github"}' "no-op guard: ref dist kept"

echo "=== not opted in: output and refs are those of a plain release ==="
new_sandbox "1.2.3" plain
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "not opted in exit code"
assert_not_contains "$out" "dist:" "not opted in: no dist note"
assert_not_contains "$out" "dist tag" "not opted in: no dist tag note"
assert_eq "$(origin_sha refs/heads/dist)" "" "not opted in: no dist branch on origin"
assert_eq "$(git ls-remote "$origin" 'refs/tags/dist-v*' | wc -l | tr -d ' ')" "0" \
    "not opted in: no dist tag on origin"
assert_eq "$([ -s "$CLAUDE_LOG" ] && echo called || echo never)" "never" "not opted in: claude never called"
assert_eq "$(jq -r '.plugins[] | select(.name=="fixture") | .source.ref' \
    "$marketplace/.claude-plugin/marketplace.json")" "null" "not opted in: marketplace entry has no ref"
assert_eq "$(entry_source)" '{"repo":"o/fixture","source":"github"}' "not opted in: source untouched"

echo "=== not opted in: a created entry has no ref and needs no claude ==="
new_sandbox "" plain
no_claude_path
set +e
out="$(cd "$plugin" && PATH="$nobin" "$(type -P bash)" plugin-dev/release.sh minor 2>&1)"
rc=$?
set -e
assert_eq "$rc" "0" "not opted in, no claude: exit code"
assert_eq "$(jq -r '.plugins[] | select(.name=="fixture") | .source.ref' \
    "$marketplace/.claude-plugin/marketplace.json")" "null" "not opted in, created entry: no ref"
assert_eq "$(origin_sha refs/heads/dist)" "" "not opted in, created entry: no dist branch"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release dist opt-in scenarios passed\n'

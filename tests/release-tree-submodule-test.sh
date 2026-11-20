#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: what counts as a clean tree where a submodule other than the memory
# store is concerned -- a moved code submodule refuses, under any ignore
# setting, in the plugin root and the marketplace repo; an untracked file
# inside one passes.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -tree-submodule, -first,
# -lost-tag, -push-route, -tags, -rollback, -pipefail, -hint-size).
#
# Usage: bash tests/release-tree-submodule-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/release-tree.XXXXXX")"
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

mount_resting_submodule() {
    # $1=parent repo path. $2=mount path, default `memory`. $3=submodule name,
    # default `gitlore-memory` — the name gitlore's install.sh fixes, and what
    # common_preflight keys its exclusion on. Mounts the submodule and commits
    # the mount, then advances the submodule's checked-out HEAD by one commit
    # without folding the moved gitlink into a parent commit — gitlore's
    # ordinary resting state between commits (see release.sh's tree_is_clean).
    local parent="$1" path="${2:-memory}" name="${3:-gitlore-memory}"
    local sub_origin sub_seed
    sub_origin="$parent-$name-origin.git"
    sub_seed=$(mktemp -d "${TMPDIR:-/tmp}/release-tree.XXXXXX")
    git init -q --bare -b main "$sub_origin"
    git init -q -b main "$sub_seed"
    git -C "$sub_seed" config user.email test@example.com
    git -C "$sub_seed" config user.name "Toolkit Test"
    git -C "$sub_seed" config commit.gpgsign false
    printf 'seed\n' > "$sub_seed/MEMORY.md"
    git -C "$sub_seed" add -A
    git -C "$sub_seed" commit -qm seed
    git -C "$sub_seed" remote add origin "$sub_origin"
    git -C "$sub_seed" push -q -u origin main
    rm -rf "$sub_seed"

    env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
        git -C "$parent" submodule add -q --name "$name" "$sub_origin" "$path"
    git -C "$parent" commit -qm "mount $name submodule"

    printf 'advance\n' >> "$parent/$path/MEMORY.md"
    git -C "$parent/$path" add -A
    git -C "$parent/$path" -c user.email=test@example.com -c user.name="Toolkit Test" \
        -c commit.gpgsign=false commit -qm advance
    # Deliberately no parent commit here.
}

echo "=== release: still refuses a resting submodule that is not the memory store ==="
new_sandbox "1.2.3"
mount_resting_submodule "$plugin" vendor vendored-lib
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "non-memory-submodule exit code"
assert_contains "$out" "uncommitted changes" "non-memory-submodule message"
assert_eq "$(cat "$GH_LOG")" "" "non-memory-submodule release must not call gh"

# A consumer may tell git to ignore a code submodule's moves. The check reads the
# tree as it is, so a moved gitlink still refuses under that setting, whether it
# is set in .git/config or in .gitmodules, and in the marketplace repo as well.
echo "=== release: refuses a moved code submodule under submodule.<name>.ignore=all ==="
new_sandbox "1.2.3"
mount_resting_submodule "$plugin" vendor vendored-lib
git -C "$plugin" config submodule.vendored-lib.ignore all
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "ignore-all submodule exit code"
assert_contains "$out" "uncommitted changes" "ignore-all submodule message"
assert_contains "$out" "vendor" "ignore-all submodule names the moved path"
assert_eq "$(cat "$GH_LOG")" "" "ignore-all submodule release must not call gh"

echo "=== release: refuses a moved code submodule under diff.ignoreSubmodules=all ==="
new_sandbox "1.2.3"
mount_resting_submodule "$plugin" "vendor dir" vendored-lib
git -C "$plugin" config diff.ignoreSubmodules all
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "diff.ignoreSubmodules exit code"
assert_contains "$out" "        vendor dir$" "diff.ignoreSubmodules names the spaced path whole"

echo "=== release: refuses a moved code submodule in the marketplace under ignore=all ==="
new_sandbox "1.2.3"
mount_resting_submodule "$marketplace" vendor vendored-lib
git -C "$marketplace" config submodule.vendored-lib.ignore all
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "ignore-all marketplace submodule exit code"
assert_contains "$out" "$MARKETPLACE_DIR has uncommitted changes" "ignore-all marketplace submodule message"
assert_eq "$(cat "$GH_LOG")" "" "ignore-all marketplace submodule release must not call gh"

# Untracked files are not checked in the parent, so they are not inside a
# submodule either. The memory store is moved beside it and still exempt.
echo "=== release: proceeds with only an untracked file inside a code submodule ==="
new_sandbox "1.2.3"
mount_resting_submodule "$plugin"
mount_resting_submodule "$plugin" vendor vendored-lib
git -C "$plugin/vendor" reset -q --hard HEAD~1
printf 'scratch\n' > "$plugin/vendor/untracked.txt"
git -C "$plugin" config submodule.vendored-lib.ignore all
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "untracked-in-submodule release exit code"
assert_contains "$out" "Release v1.2.4 complete" "untracked-in-submodule release summary"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release tree submodule scenarios passed\n'

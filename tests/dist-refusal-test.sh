#!/usr/bin/env bash
# End-to-end test of toolkit/dist.sh against real git repos in a temp dir: the
# dist.include allowlist, the five subcommands (enabled, tree, validate, commit,
# paths), their refusals and their warnings. Each scenario builds a fixture
# plugin repo and runs the script from inside it. `claude` is a stub on PATH
# that records its argv and working directory.
#
# Scope: dist.sh's malformed-allowlist refusals (each line named, a CRLF file),
# running from a subdirectory, and one dist: line per refusal. Its siblings
# dist-build-test.sh, dist-warning-test.sh and dist-subcommands-test.sh cover the
# tree build, the warnings and the other subcommands.
#
# Usage: bash tests/dist-refusal-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo, never this repo, so it
# is always safe to drop them here.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
dist="$repo_root/toolkit/dist.sh"

# Keep the host's git identity and config out of the fixtures.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

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
        fail "$3: output unexpectedly contained '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}
assert_dist_prefix() {
    # $1=stderr $2=label : at least one line, and every line starts "dist:"
    local line bad=""
    if [[ -z "$1" ]]; then
        fail "$2: stderr is empty, expected dist: lines"
        return
    fi
    while IFS= read -r line; do
        [[ "$line" == dist:* ]] || bad="$line"
    done <<<"$1"
    if [[ -n "$bad" ]]; then
        fail "$2: stderr line without the dist: prefix: '$bad'"
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

# Fixed identities and dates, none of them "now", so a copy of the source
# commit's fields is distinguishable from a fresh commit's.
src_author_name="Ann Author"
src_author_email="ann@example.invalid"
src_author_date="2020-01-02T03:04:05+0200"
src_committer_name="Cora Committer"
src_committer_email="cora@example.invalid"
src_committer_date="2021-02-03T04:05:06-0500"

# mk_repo: a fresh sandbox with a plugin repo $repo whose own path contains a
# space, holding the files every scenario starts from (a manifest without a
# license field, a 50-word README, a LICENSE, one skill) and no commit yet.
# Also lays down the claude stub in $sandbox/stubbin.
mk_repo() {
    sandbox="$(cd "$(mktemp -d)" && pwd -P)"
    sandboxes+=("$sandbox")
    repo="$sandbox/plug in"
    gitlinks=()
    stub_rc=0
    mkdir -p "$repo/.claude-plugin" "$repo/skills/demo" "$sandbox/stubbin"
    git -C "$repo" init -q
    printf '{"name":"fixture","version":"1.0.0"}\n' > "$repo/.claude-plugin/plugin.json"
    words 50 > "$repo/README.md"
    printf 'MIT License\n' > "$repo/LICENSE"
    printf '# demo skill\n' > "$repo/skills/demo/SKILL.md"
    cat > "$sandbox/stubbin/claude" <<'STUB'
#!/bin/sh
# Records one argument per line, then the cwd, then the files of the directory
# it was pointed at (an argument naming a directory, else the cwd).
{
    echo "--- call"
    for a in "$@"; do echo "arg: $a"; done
    echo "cwd: $PWD"
    dir=""
    for a in "$@"; do [ -d "$a" ] && dir="$a"; done
    [ -n "$dir" ] || dir="$PWD"
    (cd "$dir" && find . -type f | sort | sed 's/^\.\///; s/^/file: /')
} >> "$CLAUDE_STUB_LOG"
exit "${CLAUDE_STUB_RC:-0}"
STUB
    chmod +x "$sandbox/stubbin/claude"
    set_include .claude-plugin skills README.md LICENSE
}

# words <n>: n words on one line.
words() {
    printf 'word %.0s' $(seq 1 "$1")
    printf '\n'
}

# set_include <lines...>: write dist.include, one argument per line, raw.
set_include() {
    printf '%s\n' "$@" > "$repo/dist.include"
}

# commit_fixture: commit everything in $repo, force-adding, plus the gitlinks
# named in $gitlinks ("path"), each pointing at a fixed sha. Sets $src to the
# commit's full sha. Author and committer are the fixed identities above.
commit_fixture() {
    local p
    git -C "$repo" add -A -f
    for p in ${gitlinks[@]+"${gitlinks[@]}"}; do
        git -C "$repo" update-index --add --cacheinfo \
            "160000,1111111111111111111111111111111111111111,$p"
    done
    GIT_AUTHOR_NAME="$src_author_name" GIT_AUTHOR_EMAIL="$src_author_email" \
        GIT_AUTHOR_DATE="$src_author_date" \
        GIT_COMMITTER_NAME="$src_committer_name" GIT_COMMITTER_EMAIL="$src_committer_email" \
        GIT_COMMITTER_DATE="$src_committer_date" \
        git -C "$repo" -c commit.gpgsign=false commit -q --allow-empty -m fixture
    src="$(git -C "$repo" rev-parse HEAD)"
}

# run_dist <args...>: run the script with cwd at $repo and the stub claude on
# PATH. Sets $rc, $out (stdout, NULs shown as '|') and $err (stderr). The
# stdout bytes are left in $sandbox/stdout. A missing script is rc 127, a
# failed assertion and not an abort.
run_dist() {
    local errfile="$sandbox/stderr"
    local guard=()
    if command -v timeout >/dev/null; then guard=(timeout 60); fi
    rc=0
    (cd "${run_cwd:-$repo}" && PATH="$sandbox/stubbin:$PATH" \
        CLAUDE_STUB_LOG="$sandbox/claude.log" CLAUDE_STUB_RC="$stub_rc" \
        ${guard[@]+"${guard[@]}"} bash "$dist" "$@" \
        >"$sandbox/stdout" 2>"$errfile") || rc=$?
    out="$(tr '\0' '|' < "$sandbox/stdout")"
    err="$(cat "$errfile")"
}

# tree_listing <tree>: the NUL-delimited file list of a tree, as '|'-joined
# names in git's own order. Empty when the tree is not a tree.
tree_listing() {
    git -C "$repo" ls-tree -r --name-only -z "$1" 2>/dev/null | tr '\0' '|' || true
}

# expect_tree_files <label> <name...>: $out must be a tree whose files are
# exactly the names given, compared NUL-delimited and in sorted order.
expect_tree_files() {
    local label="$1" want got
    shift
    want="$(printf '%s\0' "$@" | LC_ALL=C sort -z | tr '\0' '|')"
    got="$(git -C "$repo" ls-tree -r --name-only -z "$out" 2>/dev/null \
        | LC_ALL=C sort -z | tr '\0' '|' || true)"
    assert_eq "$got" "$want" "$label: files of the built tree"
}

# expect_tree_ok <label> : exit 0 and a tree sha on stdout.
expect_tree_ok() {
    assert_eq "$rc" "0" "$1: exit code"
    if ! [[ "$out" =~ ^[0-9a-f]{40,64}$ ]]; then
        fail "$1: stdout is not a bare object id: '$out'"
    else
        assert_eq "$(git -C "$repo" cat-file -t "$out" 2>/dev/null || true)" "tree" "$1: object type"
    fi
}

# expect_refusal <label> <needle> : exit 1, only dist: lines on stderr naming
# <needle>, nothing on stdout.
expect_refusal() {
    assert_eq "$rc" "1" "$1: exit code"
    assert_eq "$out" "" "$1: stdout is empty"
    assert_dist_prefix "$err" "$1"
    assert_eq "$(grep -c '' <<<"$err")" "1" "$1: exactly one dist: line per refusal"
    assert_contains "$err" "$2" "$1: stderr names the offender"
}

echo "=== tree and paths: refuses each malformed allowlist line, naming it ==="
# Each entry: needle|line|modes|file. Every name a line could resolve to is a
# real committed file (and so in the worktree), so only the line rule can
# refuse it, never the "matches nothing" refusal. The tree-capable forms are
# also refused by paths. An absolute path and a leading .. cannot name a
# committed file, so they are exercised through paths only, spelled to resolve
# to a real file of the worktree (README.md) were the rule not there.
bad_lines=(
    "dotdot-mid|skills/../dotdot-mid|tp|dotdot-mid"
    "blank-lead| blank-lead|tp| blank-lead"
    "blank-lead2| blank-lead2|tp|blank-lead2"
    "blank-trail|blank-trail |tp|blank-trail "
    "blank-trail2|blank-trail2 |tp|blank-trail2"
    "glob-st*ar|glob-st*ar|tp|glob-st*ar"
    "glob-qu?ery|glob-qu?ery|tp|glob-qu?ery"
    "br-op[en|br-op[en|tp|br-op[en"
    "br-clo]se|br-clo]se|tp|br-clo]se"
    "back\\slash|back\\slash|tp|back\\slash"
    "abs|@abs@|p|"
    ".|.|tp|"
    "./README.md|./README.md|tp|"
    ".git|.git|tp|"
    "skills//demo|skills//demo|tp|"
    "skills/./demo|skills/./demo|tp|"
    "../plug in|../plug in/README.md|p|"
)
for entry in "${bad_lines[@]}"; do
    IFS='|' read -r needle line modes file <<<"$entry"
    mk_repo
    if [[ "$line" == "@abs@" ]]; then line="$repo/README.md"; needle="$repo/README.md"; fi
    if [[ -n "$file" ]]; then printf 'x\n' > "$repo/$file"; fi
    set_include .claude-plugin skills README.md LICENSE "$line"
    commit_fixture
    if [[ "$modes" == *t* ]]; then
        run_dist tree "$src"
        expect_refusal "bad line '$needle' (tree)" "$needle"
        assert_not_contains "$err" "matches nothing" "bad line '$needle' (tree): refused by the line rule, not as absent"
    fi
    run_dist paths "$repo"
    expect_refusal "bad line '$needle' (paths)" "$needle"
    assert_not_contains "$err" "matches nothing" "bad line '$needle' (paths): refused by the line rule, not as absent"
done

echo "=== tree and paths: refuses a CRLF dist.include ==="
mk_repo
printf '.claude-plugin\r\nskills\r\nREADME.md\r\nLICENSE\r\n' > "$repo/dist.include"
commit_fixture
for sub in tree paths; do
    if [[ "$sub" == tree ]]; then run_dist tree "$src"; else run_dist paths "$repo"; fi
    assert_eq "$rc" "1" "CRLF ($sub): exit code"
    assert_eq "$out" "" "CRLF ($sub): stdout is empty"
    assert_dist_prefix "$err" "CRLF ($sub)"
    if ! grep -qiE 'carriage|CRLF|line ending|\bCR\b' <<<"$err"; then
        fail "CRLF ($sub): stderr does not name CR or line endings: $err"
    fi
    assert_not_contains "$err" "matches nothing" "CRLF ($sub): refused for the line endings, not as absent"
done

echo "=== enabled and tree: work from a subdirectory of the repo ==="
mk_repo
commit_fixture
run_dist tree "$src"
root_tree="$out"
expect_tree_ok "tree from the root"
run_cwd="$repo/skills"
run_dist enabled "$src"
assert_eq "$rc" "0" "enabled from skills/: exit code"
assert_eq "$err" "" "enabled from skills/: no stderr"
run_dist tree "$src"
expect_tree_ok "tree from skills/"
assert_eq "$out" "$root_tree" "tree from skills/: same sha as from the root"
unset run_cwd

echo "=== tree: one dist: line per refusal, two refusals give two ==="
mk_repo
gitlinks=(skills/one skills/two)
commit_fixture
run_dist tree "$src"
assert_eq "$rc" "1" "two gitlinks: exit code"
assert_eq "$(grep -c '' <<<"$err")" "2" "two gitlinks: one dist: line each"
assert_dist_prefix "$err" "two gitlinks"
assert_contains "$err" "skills/one" "two gitlinks: first named"
assert_contains "$err" "skills/two" "two gitlinks: second named"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dist refusal scenarios passed\n'

#!/usr/bin/env bash
# End-to-end test of toolkit/dist.sh against real git repos in a temp dir: the
# dist.include allowlist, the five subcommands (enabled, tree, validate, commit,
# paths), their refusals and their warnings. Each scenario builds a fixture
# plugin repo and runs the script from inside it. `claude` is a stub on PATH
# that records its argv and working directory.
#
# Scope: dist.sh's warnings do not change the exit status. Its siblings
# dist-build-test.sh, dist-refusal-test.sh and dist-subcommands-test.sh cover the
# tree build, the refusals and the other subcommands.
#
# Usage: bash tests/dist-warning-test.sh   (run from repo root)
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
    sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dist-warning.XXXXXX")" && pwd -P)"
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

echo "=== tree: warnings do not change the exit status ==="
# A quiet baseline first, so each warning below is the fixture's doing.
mk_repo
commit_fixture
run_dist tree "$src"
expect_tree_ok "baseline"
assert_eq "$err" "" "baseline: no warning"

# 512 files is the limit, 513 the first to warn. The fixture holds 4 files.
mk_repo
mkdir -p "$repo/skills/bulk"
for i in $(seq 1 508); do : > "$repo/skills/bulk/f$i"; done
commit_fixture
run_dist tree "$src"
expect_tree_ok "512 files"
assert_eq "$err" "" "512 files: no warning at the limit"

mk_repo
mkdir -p "$repo/skills/bulk"
for i in $(seq 1 509); do : > "$repo/skills/bulk/f$i"; done
commit_fixture
run_dist tree "$src"
expect_tree_ok "513 files"
assert_dist_prefix "$err" "513 files"
assert_contains "$err" "files" "513 files: warning names the file count"
assert_contains "$err" "review" "513 files: warning says directory review"

# 256 KiB is the limit for a non-asset file; image and font suffixes are exempt.
mk_repo
head -c 262144 /dev/zero > "$repo/skills/demo/at-limit.bin"
commit_fixture
run_dist tree "$src"
expect_tree_ok "file at 256 KiB"
assert_eq "$err" "" "file at 256 KiB: no warning"

mk_repo
head -c 262145 /dev/zero > "$repo/skills/demo/over-limit.bin"
commit_fixture
run_dist tree "$src"
expect_tree_ok "file over 256 KiB"
assert_dist_prefix "$err" "file over 256 KiB"
assert_contains "$err" "over-limit.bin" "file over 256 KiB: warning names the file"
assert_contains "$err" "review" "file over 256 KiB: warning says directory review"

mk_repo
for ext in png jpg jpeg gif webp woff woff2 ttf otf; do
    head -c 300000 /dev/zero > "$repo/skills/demo/big.$ext"
done
commit_fixture
run_dist tree "$src"
expect_tree_ok "large assets"
assert_eq "$err" "" "large assets with exempt suffixes: no warning"

mk_repo
head -c 300000 /dev/zero > "$repo/skills/demo/big.png.txt"
commit_fixture
run_dist tree "$src"
expect_tree_ok "large .png.txt"
assert_contains "$err" "big.png.txt" "large file whose suffix only contains .png: warns"

# README: 40 words is enough, 39 warns.
mk_repo
words 40 > "$repo/README.md"
commit_fixture
run_dist tree "$src"
expect_tree_ok "40-word README"
assert_eq "$err" "" "40-word README: no warning"

mk_repo
words 39 > "$repo/README.md"
commit_fixture
run_dist tree "$src"
expect_tree_ok "39-word README"
assert_dist_prefix "$err" "39-word README"
assert_contains "$err" "README" "39-word README: warning names the README"
assert_contains "$err" "review" "39-word README: warning says directory review"

# License: a LICENSE* file or a license in plugin.json is enough.
mk_repo
rm "$repo/LICENSE"
set_include .claude-plugin skills README.md
commit_fixture
run_dist tree "$src"
expect_tree_ok "no license anywhere"
assert_dist_prefix "$err" "no license anywhere"
assert_contains "$err" "license" "no license anywhere: warning names the license"
assert_contains "$err" "review" "no license anywhere: warning says directory review"

mk_repo
rm "$repo/LICENSE"
printf 'MIT\n' > "$repo/LICENSE.md"
set_include .claude-plugin skills README.md LICENSE.md
commit_fixture
run_dist tree "$src"
expect_tree_ok "LICENSE.md"
assert_eq "$err" "" "LICENSE.md counts as a LICENSE* file: no warning"

mk_repo
rm "$repo/LICENSE"
printf '{"name":"fixture","version":"1.0.0","license":"MIT"}\n' > "$repo/.claude-plugin/plugin.json"
set_include .claude-plugin skills README.md
commit_fixture
run_dist tree "$src"
expect_tree_ok "license in plugin.json"
assert_eq "$err" "" "license field in plugin.json: no warning"

# Warnings are about the result tree: unlisted bulk and big files stay quiet.
mk_repo
mkdir -p "$repo/plans/many"
for i in $(seq 1 520); do : > "$repo/plans/many/f$i"; done
head -c 300000 /dev/zero > "$repo/plans/big.bin"
commit_fixture
run_dist tree "$src"
expect_tree_ok "unlisted bulk"
assert_eq "$err" "" "unlisted files and a big unlisted file: no warning"
expect_tree_files "unlisted bulk" .claude-plugin/plugin.json LICENSE README.md skills/demo/SKILL.md

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dist warning scenarios passed\n'

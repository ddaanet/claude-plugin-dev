#!/usr/bin/env bash
# End-to-end test of toolkit/dist.sh against real git repos in a temp dir: the
# dist.include allowlist, the five subcommands (enabled, tree, validate, commit,
# paths), their refusals and their warnings. Each scenario builds a fixture
# plugin repo and runs the script from inside it. `claude` is a stub on PATH
# that records its argv and working directory.
#
# Scope: dist.sh's enabled, commit, validate and paths subcommands. Its siblings
# dist-build-test.sh, dist-refusal-test.sh and dist-warning-test.sh cover the tree
# build, the refusals and the warnings.
#
# Usage: bash tests/dist-subcommands-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/dist-subcommands.XXXXXX")" || exit 1
    sandbox="$(cd "$sandbox" && pwd -P)"
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

echo "=== enabled: reads dist.include from the commit's tree ==="
mk_repo
commit_fixture
rm "$repo/dist.include"
run_dist enabled "$src"
assert_eq "$rc" "0" "enabled when committed (worktree copy deleted): exit code"
assert_eq "$out" "" "enabled: stdout is empty"

mk_repo
rm "$repo/dist.include"
commit_fixture
set_include .claude-plugin skills README.md LICENSE   # untracked, worktree only
run_dist enabled "$src"
assert_eq "$rc" "1" "not enabled when only in the worktree: exit code"
assert_eq "$out" "" "not enabled: stdout is empty"

echo "=== commit: reproducible, copied from the source commit ==="
mk_repo
commit_fixture
run_dist tree "$src"
tree="$out"
run_dist commit "$src" "$tree" 1.2.3
assert_eq "$rc" "0" "commit root: exit code"
first="$out"
if ! [[ "$first" =~ ^[0-9a-f]{40,64}$ ]]; then
    fail "commit root: stdout is not a bare object id: '$first'"
fi
assert_eq "$(git -C "$repo" cat-file -t "$first" 2>/dev/null || true)" "commit" "commit root: object type"
assert_eq "$(git -C "$repo" rev-parse "$first^{tree}" 2>/dev/null || true)" "$tree" "commit root: tree"
assert_eq "$(git -C "$repo" log -1 --format=%s "$first" 2>/dev/null || true)" \
    "dist v1.2.3 from $src" "commit root: message"
assert_eq "$(git -C "$repo" rev-list --parents -n1 "$first" 2>/dev/null || true)" \
    "$first" "commit root: no parent"
fmt='%an|%ae|%ad|%cn|%ce|%cd'
assert_eq "$(git -C "$repo" log -1 --date=raw --format="$fmt" "$first" 2>/dev/null || true)" \
    "$(git -C "$repo" log -1 --date=raw --format="$fmt" "$src")" "commit root: author and committer copied from the source commit"
assert_contains "$(git -C "$repo" log -1 --date=raw --format=%ad "$src")" " +0200" \
    "fixture: source author date is the explicit one, not now"
# Same inputs, a different caller environment: the same commit.
rc=0
second="$(cd "$repo" && GIT_AUTHOR_NAME=Other GIT_AUTHOR_EMAIL=other@example.invalid \
    GIT_COMMITTER_NAME=Other GIT_COMMITTER_EMAIL=other@example.invalid \
    GIT_AUTHOR_DATE="2030-01-01T00:00:00+0000" GIT_COMMITTER_DATE="2030-01-01T00:00:00+0000" \
    bash "$dist" commit "$src" "$tree" 1.2.3 2>/dev/null)" || rc=$?
assert_eq "$rc" "0" "commit twice: second exit code"
assert_eq "$second" "$first" "commit twice: same inputs give the same sha"
run_dist commit "$src" "$tree" 1.2.4
if [[ -n "$out" && "$out" == "$first" ]]; then
    fail "commit: a different version gave the same sha"
fi
assert_eq "$(git -C "$repo" log -1 --format=%s "$out" 2>/dev/null || true)" \
    "dist v1.2.4 from $src" "commit: message carries the version it was given"

echo "=== commit: with a parent, the parent is that sha ==="
parent="$(GIT_AUTHOR_DATE="2019-05-05T05:05:05+0000" GIT_COMMITTER_DATE="2019-05-05T05:05:05+0000" \
    GIT_AUTHOR_NAME=p GIT_AUTHOR_EMAIL=p@example.invalid \
    GIT_COMMITTER_NAME=p GIT_COMMITTER_EMAIL=p@example.invalid \
    git -C "$repo" commit-tree -m previous "$src^{tree}")"
run_dist commit "$src" "$tree" 1.2.3 "$parent"
assert_eq "$rc" "0" "commit with parent: exit code"
with_parent="$out"
assert_eq "$(git -C "$repo" rev-list --parents -n1 "$with_parent" 2>/dev/null || true)" \
    "$with_parent $parent" "commit with parent: the parent is the given sha"
assert_eq "$(git -C "$repo" log -1 --date=raw --format="$fmt" "$with_parent" 2>/dev/null || true)" \
    "$(git -C "$repo" log -1 --date=raw --format="$fmt" "$src")" "commit with parent: fields still copied from the source, not the parent"
run_dist commit "$src" "$tree" 1.2.3 "$parent"
assert_eq "$out" "$with_parent" "commit with parent twice: same sha"
if [[ -n "$with_parent" && "$with_parent" == "$first" ]]; then
    fail "commit: the parent did not change the sha"
fi

echo "=== validate: runs claude plugin validate --strict on the extracted tree ==="
mk_repo
mkdir -p "$repo/plans"
printf 'plan\n' > "$repo/plans/x.md"
commit_fixture
run_dist tree "$src"
tree="$out"
stub_rc=0
run_dist validate "$tree"
assert_eq "$rc" "0" "validate passing stub: exit code"
assert_eq "$out" "" "validate passing stub: stdout is empty"
log="$(cat "$sandbox/claude.log" 2>/dev/null || true)"
assert_contains "$log" "arg: plugin" "validate: claude gets plugin"
assert_contains "$log" "arg: validate" "validate: claude gets validate"
assert_contains "$log" "arg: --strict" "validate: claude gets --strict"
assert_contains "$log" "file: .claude-plugin/plugin.json" "validate: the directory holds the tree's manifest"
assert_contains "$log" "file: skills/demo/SKILL.md" "validate: the directory holds the tree's skills"
assert_not_contains "$log" "plans/x.md" "validate: the directory holds only the tree, no dev file"
assert_not_contains "$log" "dist.include" "validate: the directory holds only the tree, not the allowlist"
assert_not_contains "$log" "cwd: $repo" "validate: not run inside the source repo"
assert_not_contains "$log" "arg: $repo" "validate: not pointed at the source repo"

stub_rc=7
run_dist validate "$tree"
assert_eq "$rc" "7" "validate failing stub: its status propagates"

echo "=== validate: refuses when claude is not on PATH ==="
nobin="$sandbox/nobin"
mkdir -p "$nobin"
for t in git bash sh env mktemp tar sed awk grep cat tr wc sort cut head tail rm mkdir \
    dirname basename find xargs od ls cp mv date uniq tee readlink realpath chmod \
    ln cmp stat expr gzip; do
    p="$(type -P "$t" 2>/dev/null || true)"
    if [[ -n "$p" ]]; then ln -s "$p" "$nobin/$t"; fi
done
bash_path="$(type -P bash)"
assert_eq "$(PATH="$nobin" type -P claude 2>/dev/null || true)" "" "fixture: no claude reachable on the stripped PATH"
rm -f "$sandbox/claude.log"
rc=0
(cd "$repo" && PATH="$nobin" "$bash_path" "$dist" validate "$tree" \
    >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
out="$(tr '\0' '|' < "$sandbox/stdout")"
err="$(cat "$sandbox/stderr")"
expect_refusal "validate without claude" "claude"
if [[ -e "$sandbox/claude.log" ]]; then
    fail "validate without claude: the stub ran anyway"
fi

echo "=== paths: reads the worktree allowlist, NUL-delimited and normalised ==="
mk_repo
set_include '# comment' 'skills/' '' '.claude-plugin' 'README.md' 'LICENSE'
run_dist paths "$repo"
assert_eq "$rc" "0" "paths: exit code"
assert_eq "$out" "skills|.claude-plugin|README.md|LICENSE|" "paths: normalised, in file order, NUL-delimited"
assert_eq "$err" "" "paths: no stderr"
printf 'skills\0.claude-plugin\0README.md\0LICENSE\0' > "$sandbox/want.bin"
if ! cmp -s "$sandbox/want.bin" "$sandbox/stdout"; then
    fail "paths: stdout bytes differ from the NUL-delimited list"
fi

# The root is the argument, not the cwd.
rc=0
(cd "$sandbox" && bash "$dist" paths "$repo" >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
assert_eq "$rc" "0" "paths from an unrelated cwd: exit code"
assert_eq "$(tr '\0' '|' < "$sandbox/stdout")" "skills|.claude-plugin|README.md|LICENSE|" "paths from an unrelated cwd: same list"

echo "=== paths: exits 3 without dist.include ==="
mk_repo
rm "$repo/dist.include"
run_dist paths "$repo"
assert_eq "$rc" "3" "paths without dist.include: exit code"
assert_eq "$out" "" "paths without dist.include: prints nothing"

echo "=== paths: a listed path absent from the worktree is refused ==="
mk_repo
set_include .claude-plugin skills nothere/file.md
run_dist paths "$repo"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dist subcommand scenarios passed\n'

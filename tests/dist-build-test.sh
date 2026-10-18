#!/usr/bin/env bash
# End-to-end test of toolkit/dist.sh against real git repos in a temp dir: the
# dist.include allowlist, the five subcommands (enabled, tree, validate, commit,
# paths), their refusals and their warnings. Each scenario builds a fixture
# plugin repo and runs the script from inside it. `claude` is a stub on PATH
# that records its argv and working directory.
#
# Scope: dist.sh tree -- the allowlist builds exactly the listed paths: the commit
# over the worktree, odd names, literal pathspecs, and the refusals for a gitlink,
# a symlink, no manifest, a path matching nothing and a Markdown reference to a
# path left out of the tree. Its siblings
# dist-refusal-test.sh, dist-warning-test.sh and dist-subcommands-test.sh cover
# the malformed-line refusals, the warnings and the other subcommands.
#
# Usage: bash tests/dist-build-test.sh   (run from repo root)
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

echo "=== tree: handoff's allowlist builds exactly the listed paths ==="
mk_repo
mkdir -p "$repo/hooks" "$repo/scripts" "$repo/bin" "$repo/plans" "$repo/tests" "$repo/docs"
printf '{}\n' > "$repo/hooks/hooks.json"
printf '#!/bin/sh\n' > "$repo/scripts/run.sh"
printf '#!/bin/sh\n' > "$repo/bin/tool"
printf 'plan\n' > "$repo/plans/x.md"
printf 'test\n' > "$repo/tests/t.sh"
printf 'doc\n' > "$repo/docs/d.md"
printf 'recipes\n' > "$repo/justfile"
gitlinks=(memory)
set_include '# the shipped surface' '.claude-plugin' 'skills/' '' 'hooks' 'scripts' 'bin/' 'README.md' 'LICENSE'
commit_fixture
git -C "$repo" diff --cached --quiet || fail "fixture: index not clean after commit"
run_dist tree "$src"
expect_tree_ok "handoff allowlist"
expect_tree_files "handoff allowlist" \
    .claude-plugin/plugin.json LICENSE README.md bin/tool hooks/hooks.json \
    scripts/run.sh skills/demo/SKILL.md
assert_eq "$err" "" "handoff allowlist: no warnings on a clean fixture"
git -C "$repo" diff --cached --quiet || fail "handoff allowlist: tree build touched the repo's own index"
# The blobs are the commit's blobs.
assert_eq "$(git -C "$repo" rev-parse "$out:LICENSE" 2>/dev/null || true)" \
    "$(git -C "$repo" rev-parse "$src:LICENSE")" "handoff allowlist: blob identity"
# The same tree whether the commit is named by sha or by ref.
first_tree="$out"
run_dist tree HEAD
assert_eq "$out" "$first_tree" "handoff allowlist: HEAD names the same tree as its sha"

echo "=== tree: dist.include itself ships only when listed ==="
mk_repo
set_include .claude-plugin dist.include README.md LICENSE
commit_fixture
run_dist tree "$src"
expect_tree_ok "listed dist.include"
expect_tree_files "listed dist.include" \
    .claude-plugin/plugin.json dist.include README.md LICENSE

echo "=== tree: the allowlist and the blobs come from the commit, not the worktree ==="
mk_repo
commit_fixture
printf 'edited after commit\n' > "$repo/skills/demo/SKILL.md"
printf 'README.md\n' > "$repo/dist.include"
printf 'untracked\n' > "$repo/skills/demo/new.md"
run_dist tree "$src"
expect_tree_ok "commit not worktree"
expect_tree_files "commit not worktree" \
    .claude-plugin/plugin.json LICENSE README.md skills/demo/SKILL.md
assert_eq "$(git -C "$repo" rev-parse "$out:skills/demo/SKILL.md" 2>/dev/null || true)" \
    "$(git -C "$repo" rev-parse "$src:skills/demo/SKILL.md")" "commit not worktree: blob is the committed one"

echo "=== tree: a space and a newline in a path survive the build ==="
mk_repo
mkdir -p "$repo/skills/my skill" "$repo/extra dir"
printf 'x\n' > "$repo/skills/my skill/SKILL.md"
printf 'y\n' > "$repo/extra dir/f g.txt"
newline_name=$'skills/new\nline.md'
printf 'z\n' > "$repo/$newline_name"
set_include .claude-plugin skills 'extra dir/f g.txt' README.md LICENSE
commit_fixture
run_dist tree "$src"
expect_tree_ok "space and newline"
want_file="$sandbox/want.bin"
got_file="$sandbox/got.bin"
printf '%s\0' '.claude-plugin/plugin.json' 'LICENSE' 'README.md' 'extra dir/f g.txt' \
    'skills/demo/SKILL.md' "$newline_name" 'skills/my skill/SKILL.md' \
    | LC_ALL=C sort -z > "$want_file"
git -C "$repo" ls-tree -r --name-only -z "$out" 2>/dev/null | LC_ALL=C sort -z > "$got_file" || true
if ! cmp -s "$want_file" "$got_file"; then
    fail "space and newline: NUL-delimited listing differs (want '$(tr '\0' '|' < "$want_file")', got '$(tr '\0' '|' < "$got_file")')"
fi

echo "=== tree: listed paths are literal pathspecs ==="
mk_repo
commit_fixture
set_include .claude-plugin README.md LICENSE ':(exclude)skills/demo'
git -C "$repo" add -f dist.include
git -C "$repo" -c commit.gpgsign=false -c user.name=f -c user.email=f@example.invalid commit -q -m magic
src="$(git -C "$repo" rev-parse HEAD)"
run_dist tree "$src"
expect_refusal "pathspec magic is literal, so it matches nothing" "exclude"

echo "=== tree: refuses a gitlink inside a listed directory ==="
mk_repo
gitlinks=(skills/vendored)
commit_fixture
run_dist tree "$src"
expect_refusal "gitlink in a listed directory" "skills/vendored"

echo "=== tree: refuses a listed path that is itself a gitlink ==="
mk_repo
gitlinks=(memory)
set_include .claude-plugin skills memory README.md LICENSE
commit_fixture
run_dist tree "$src"
expect_refusal "listed gitlink" "memory"

echo "=== tree: refuses a symlink inside a listed directory ==="
mk_repo
ln -s ../README.md "$repo/skills/linked.md"
commit_fixture
run_dist tree "$src"
expect_refusal "symlink in a listed directory" "skills/linked.md"

echo "=== tree: refuses a tree with no plugin.json ==="
mk_repo
set_include skills README.md LICENSE
commit_fixture
run_dist tree "$src"
expect_refusal "no plugin.json" "plugin.json"

echo "=== tree: refuses a listed path that matches nothing ==="
mk_repo
set_include .claude-plugin skills README.md LICENSE nothere/file.md
commit_fixture
run_dist tree "$src"
expect_refusal "listed path missing" "nothere/file.md"

echo "=== tree: refuses a reference from the tree to a path left out of it ==="
mk_repo
mkdir -p "$repo/docs"
printf '# design\n' > "$repo/docs/design.md"
printf '\nSee [the design](docs/design.md).\n' >> "$repo/README.md"
commit_fixture
run_dist tree "$src"
expect_refusal "reference out of the tree" "README.md:3: docs/design.md"
set_include .claude-plugin skills README.md LICENSE docs
commit_fixture
run_dist tree "$src"
expect_tree_ok "reference into a listed path"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dist tree scenarios passed\n'

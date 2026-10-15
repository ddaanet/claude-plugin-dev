#!/usr/bin/env bash
# End-to-end test of toolkit/dist.sh against real git repos in a temp dir: the
# dist.include allowlist, the five subcommands (enabled, tree, validate, commit,
# paths), their refusals and their warnings. Each scenario builds a fixture
# plugin repo and runs the script from inside it. `claude` is a stub on PATH
# that records its argv and working directory.
#
# Usage: bash tests/dist-test.sh   (run from repo root)
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
expect_refusal "paths absent path" "nothere/file.md"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dist scenarios passed\n'

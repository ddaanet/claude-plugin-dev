#!/usr/bin/env bash
# End-to-end test of toolkit/dogfood.sh sync against real git repos in a temp
# dir: what the copy holds, what it leaves out, and the usage message. Each
# scenario builds a consumer fixture and runs the script as a consumer would,
# from its vendored spot at plugin-dev/dogfood.sh. The refusals and failures
# are in dogfood-sync-refusal-test.sh.
#
# Scope: the dist.include allowlist -- only listed paths are copied, with dist.sh
# vendored beside dogfood.sh. Its siblings dogfood-sync-copy-test.sh and
# dogfood-sync-nested-test.sh cover the plain copy and nested repos.
#
# Usage: bash tests/dogfood-sync-allowlist-test.sh   (run from repo root)
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
assert_file() {
    # $1=path $2=label : a regular file, not a link
    if [[ ! -f "$1" || -L "$1" ]]; then
        fail "$2: '$1' is not a regular file"
    fi
}
assert_absent() {
    # $1=path $2=label : neither a file, a directory nor a dangling link
    if [[ -e "$1" || -L "$1" ]]; then
        fail "$2: '$1' exists"
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

# make_consumer: build a consumer fixture in a fresh sandbox. Sets $sandbox
# (physical spelling: macOS $TMPDIR sits under a symlink) and $consumer, a
# git repo whose own path contains a space. Tests append the ignore patterns
# and files they need, then call commit_all.
make_consumer() {
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/dogfood-sync-allowlist.XXXXXX")" || exit 1
    sandbox="$(cd "$sandbox" && pwd -P)"
    sandboxes+=("$sandbox")
    consumer="$sandbox/my consumer"
    mkdir -p "$consumer/.claude-plugin" "$consumer/skills/demo" "$consumer/plugin-dev"
    git -C "$consumer" init -q
    printf '{"name":"fixture","version":"1.0.0"}\n' > "$consumer/.claude-plugin/plugin.json"
    printf '/dist/plugin/\n' > "$consumer/.gitignore"
    printf '# demo skill\n' > "$consumer/skills/demo/SKILL.md"
    cp "$repo_root/toolkit/dogfood.sh" "$consumer/plugin-dev/dogfood.sh"
    commit_all
}

# commit_all: track everything not ignored in $consumer.
commit_all() {
    git -C "$consumer" add -A
    git -C "$consumer" \
        -c user.name=fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false \
        commit -q --allow-empty -m fixture
}

# make_decoy <dir>: make <dir> a plugin root of its own, a git repo with a
# manifest and /dist/plugin/ ignored, so a script that took its root from <dir>
# would sync there and succeed rather than fail on a non-repo.
make_decoy() {
    mkdir -p "$1/.claude-plugin"
    git -C "$1" init -q
    printf '{"name":"decoy","version":"1.0.0"}\n' > "$1/.claude-plugin/plugin.json"
    printf '/dist/plugin/\n' > "$1/.gitignore"
    git -C "$1" add .claude-plugin/plugin.json .gitignore
    git -C "$1" \
        -c user.name=fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false \
        commit -q -m decoy
}

# run_dogfood <args...>: run the vendored script with the cwd at $sandbox and
# CLAUDE_PROJECT_DIR naming a directory that is not the consumer. Sets $rc,
# $out (stdout) and $err (stderr).
run_dogfood() {
    mkdir -p "$sandbox/elsewhere"
    local errfile="$sandbox/stderr"
    # A sync that recurses without bound would hang the suite, not fail it; where
    # timeout exists it ends the run at rc 124. Elsewhere the hang stands.
    local guard=()
    if command -v timeout >/dev/null; then guard=(timeout 20); fi
    set +e
    out="$(cd "$sandbox" && CLAUDE_PROJECT_DIR="$sandbox/elsewhere" \
        ${guard[@]+"${guard[@]}"} bash "$consumer/plugin-dev/dogfood.sh" "$@" 2>"$errfile")"
    rc=$?
    set -e
    err="$(cat "$errfile")"
}

# vendor_dist: put the shipped dist.sh beside dogfood.sh, as a consumer vendors
# both under plugin-dev/. Existing scenarios do not call it: they run with
# dogfood.sh alone and no dist.include, the pre-allowlist shape.
vendor_dist() {
    cp "$repo_root/toolkit/dist.sh" "$consumer/plugin-dev/dist.sh"
}

# set_include <lines...>: write the consumer's dist.include, one per line.
set_include() {
    printf '%s\n' "$@" > "$consumer/dist.include"
}

# make_allowlisted: a consumer with dist.sh vendored and an allowlist naming a
# plain directory, a directory whose name has a space, a nested file whose
# sibling is unlisted, and a root file. Unlisted decoys sit beside each listed
# thing, so an absence is paired with a presence differing only in the listing.
make_allowlisted() {
    make_consumer
    vendor_dist
    printf 'cache.log\n' >> "$consumer/.gitignore"
    mkdir -p "$consumer/my docs" "$consumer/a/b" "$consumer/other dir" \
        "$consumer/skills/demo/deep/er"
    printf 'doc\n' > "$consumer/my docs/guide.md"
    printf 'nested\n' > "$consumer/a/b/file"
    printf 'sibling\n' > "$consumer/a/b/sibling"
    printf 'cousin\n' > "$consumer/a/other"
    printf 'unlisted\n' > "$consumer/other dir/x.md"
    printf 'listed\n' > "$consumer/README.md"
    printf 'unlisted\n' > "$consumer/NOTES.md"
    printf 'deep\n' > "$consumer/skills/demo/deep/er/leaf.md"
    printf 'noise\n' > "$consumer/skills/demo/cache.log"
    mkdir -p "$consumer/a b/c d"
    printf 'spaced\n' > "$consumer/a b/c d/file"
    printf 'sibling\n' > "$consumer/a b/c d/sibling"
    printf 'cousin\n' > "$consumer/a b/other"
    set_include .claude-plugin skills "my docs" a/b/file "a b/c d/file" README.md
    commit_all
}

echo "=== allowlist: only listed paths are copied ==="
make_allowlisted
run_dogfood sync
assert_eq "$rc" "0" "allowlist copies listed paths exit code"
assert_eq "$err" "" "allowlist copies listed paths prints nothing on stderr"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" "allowlist: a listed directory is copied"
assert_file "$consumer/dist/plugin/.claude-plugin/plugin.json" "allowlist: a listed dot-directory is copied"
assert_file "$consumer/dist/plugin/README.md" "allowlist: a listed root file is copied"
assert_absent "$consumer/dist/plugin/NOTES.md" "allowlist: an unlisted root file is left out"
assert_absent "$consumer/dist/plugin/dist.include" "allowlist: an unlisted dist.include is left out"
assert_absent "$consumer/dist/plugin/other dir" "allowlist: an unlisted directory is left out"
assert_absent "$consumer/dist/plugin/plugin-dev" "allowlist: the vendored toolkit is left out"

echo "=== allowlist: listed directories are copied in full ==="
assert_file "$consumer/dist/plugin/skills/demo/deep/er/leaf.md" \
    "allowlist: a deep file inside a listed directory is copied"
if ! cmp -s "$consumer/skills/demo/deep/er/leaf.md" "$consumer/dist/plugin/skills/demo/deep/er/leaf.md"; then
    fail "allowlist: the deep file's bytes differ from the source"
fi

echo "=== allowlist: a listed path with a space, and a nested listed file ==="
assert_file "$consumer/dist/plugin/my docs/guide.md" "allowlist: a listed directory with a space is copied"
assert_file "$consumer/dist/plugin/a/b/file" "allowlist: a listed nested file is copied via its parent rules"
assert_absent "$consumer/dist/plugin/a/b/sibling" "allowlist: the unlisted sibling of a listed nested file is left out"
assert_absent "$consumer/dist/plugin/a/other" "allowlist: an unlisted file in a listed file's grandparent is left out"
assert_file "$consumer/dist/plugin/a b/c d/file" "allowlist: a listed file with spaces in nested parents is copied"
assert_absent "$consumer/dist/plugin/a b/c d/sibling" "allowlist: the unlisted sibling under spaced parents is left out"
assert_absent "$consumer/dist/plugin/a b/other" "allowlist: an unlisted file beside a spaced parent is left out"

echo "=== allowlist: untracked and ignored files inside a listed directory ==="
printf 'fresh\n' > "$consumer/skills/demo/untracked.md"
# Untracked, not yet ignored: a tracked file would stay on disk after being ignored.
printf 'late\n' > "$consumer/skills/demo/later.log"
run_dogfood sync
assert_eq "$rc" "0" "allowlist untracked/ignored exit code"
assert_file "$consumer/dist/plugin/skills/demo/untracked.md" \
    "allowlist: an untracked file inside a listed directory is copied"
assert_absent "$consumer/dist/plugin/skills/demo/cache.log" \
    "allowlist: an ignored file inside a listed directory is left out"
assert_absent "$consumer/dist/plugin/NOTES.md" "allowlist: still left out on a second sync"
assert_file "$consumer/dist/plugin/skills/demo/later.log" "allowlist become-ignored: copied while not ignored"
printf 'later.log\n' >> "$consumer/.gitignore"
run_dogfood sync
assert_eq "$rc" "0" "allowlist become-ignored exit code"
assert_absent "$consumer/dist/plugin/skills/demo/later.log" \
    "allowlist become-ignored: a copied file that becomes ignored leaves the copy"
assert_file "$consumer/dist/plugin/skills/demo/untracked.md" "allowlist become-ignored: its untracked neighbour stays"

echo "=== allowlist: a file deleted from a listed directory leaves the copy ==="
assert_file "$consumer/dist/plugin/skills/demo/untracked.md" "allowlist deletion: present before"
rm "$consumer/skills/demo/untracked.md" "$consumer/skills/demo/deep/er/leaf.md"
run_dogfood sync
assert_eq "$rc" "0" "allowlist deletion exit code"
assert_absent "$consumer/dist/plugin/skills/demo/untracked.md" "allowlist deletion: the deleted file leaves the copy"
assert_absent "$consumer/dist/plugin/skills/demo/deep/er/leaf.md" "allowlist deletion: a deleted deep file leaves the copy"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" "allowlist deletion: the rest of the directory stays"

echo "=== allowlist: a path dropped from the list leaves the copy ==="
set_include .claude-plugin skills README.md
run_dogfood sync
assert_eq "$rc" "0" "allowlist shrink exit code"
assert_absent "$consumer/dist/plugin/my docs" "allowlist shrink: a no-longer-listed directory leaves the copy"
assert_absent "$consumer/dist/plugin/a" "allowlist shrink: a no-longer-listed nested file and its parents leave the copy"
assert_file "$consumer/dist/plugin/README.md" "allowlist shrink: a still-listed file stays"

echo "=== allowlist: a listed path that is missing refuses and leaves the copy intact ==="
make_allowlisted
run_dogfood sync
assert_eq "$rc" "0" "allowlist refusal setup: first sync exit code"
printf 'sentinel\n' > "$consumer/dist/plugin/SENTINEL"
before="$(cd "$consumer/dist/plugin" && find . | LC_ALL=C sort)"
printf 'changed\n' > "$consumer/skills/demo/SKILL.md"
printf 'new\n' > "$consumer/skills/demo/added.md"
set_include .claude-plugin skills README.md "no such.md"
run_dogfood sync
if [[ "$rc" == 0 ]]; then fail "allowlist missing path: sync exited 0"; fi
assert_contains "$err" "no such.md" "allowlist missing path: the message names the path"
assert_file "$consumer/dist/plugin/SENTINEL" "allowlist missing path: the sentinel survives"
assert_eq "$(cd "$consumer/dist/plugin" && find . | LC_ALL=C sort)" "$before" \
    "allowlist missing path: the copy's listing is unchanged"
assert_eq "$(cat "$consumer/dist/plugin/skills/demo/SKILL.md")" "# demo skill" \
    "allowlist missing path: the copy holds the previous bytes"
assert_absent "$consumer/dist/plugin/skills/demo/added.md" "allowlist missing path: a new source file did not land"

echo "=== allowlist: .git and dist/plugin are never copied from a listed directory ==="
make_consumer
vendor_dist
mkdir -p "$consumer/skills/demo/.git" "$consumer/dist"
printf 'ref: x\n' > "$consumer/skills/demo/.git/HEAD"
printf 'tracked\n' > "$consumer/dist/keep.md"
set_include .claude-plugin skills dist
commit_all
assert_file "$consumer/skills/demo/.git/HEAD" "allowlist .git/dist: the fixture holds a .git inside a listed directory"
run_dogfood sync
assert_eq "$rc" "0" "allowlist .git/dist exit code (first sync)"
run_dogfood sync
assert_eq "$rc" "0" "allowlist .git/dist exit code (second sync)"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" "allowlist .git/dist: the listed directory is copied"
assert_file "$consumer/dist/plugin/dist/keep.md" "allowlist .git/dist: a listed dist/ is copied beside the copy"
assert_absent "$consumer/dist/plugin/skills/demo/.git" "allowlist .git/dist: a .git inside a listed directory is left out"
assert_absent "$consumer/dist/plugin/dist/plugin" "allowlist .git/dist: dist/plugin is not copied into itself"

echo "=== no dist.include: an unlisted root file is copied, with dist.sh vendored ==="
make_consumer
vendor_dist
printf 'root\n' > "$consumer/NOTES.md"
commit_all
run_dogfood sync
assert_eq "$rc" "0" "no allowlist exit code"
assert_file "$consumer/dist/plugin/NOTES.md" "no allowlist: a root file is copied"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" "no allowlist: the tree is copied"

echo "=== no dist.include and no dist.sh: sync behaves as today ==="
make_consumer
printf 'root\n' > "$consumer/NOTES.md"
commit_all
assert_absent "$consumer/plugin-dev/dist.sh" "no allowlist, no dist.sh: fixture holds no dist.sh"
run_dogfood sync
assert_eq "$rc" "0" "no allowlist, no dist.sh exit code"
assert_file "$consumer/dist/plugin/NOTES.md" "no allowlist, no dist.sh: a root file is copied"

echo "=== dist.include but no dist.sh: the sync is refused, dist untouched ==="
make_consumer
printf 'root\n' > "$consumer/NOTES.md"
set_include .claude-plugin skills
commit_all
run_dogfood sync
if [[ "$rc" == 0 ]]; then fail "allowlist without dist.sh: sync exited 0"; fi
assert_contains "$err" "dist.sh" "allowlist without dist.sh: the message names dist.sh"
assert_absent "$consumer/dist" "allowlist without dist.sh: dist/ untouched"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood sync allowlist scenarios passed\n'

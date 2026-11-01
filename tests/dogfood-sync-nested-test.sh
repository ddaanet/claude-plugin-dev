#!/usr/bin/env bash
# End-to-end test of toolkit/dogfood.sh sync against real git repos in a temp
# dir: what the copy holds, what it leaves out, and the usage message. Each
# scenario builds a consumer fixture and runs the script as a consumer would,
# from its vendored spot at plugin-dev/dogfood.sh. The refusals and failures
# are in dogfood-sync-refusal-test.sh.
#
# Scope: nested repos, submodules and recursion -- a nested .git, a path ignored
# inside a submodule, an uninitialised submodule, a sync that must not recurse
# into its own copy. Its siblings dogfood-sync-copy-test.sh and
# dogfood-sync-allowlist-test.sh cover the plain copy and the allowlist.
#
# Usage: bash tests/dogfood-sync-nested-test.sh   (run from repo root)
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
    sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/dogfood-sync-nested.XXXXXX")" && pwd -P)"
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

echo "=== a nested repo's .git stays out ==="
# memory/ is a repo of its own, recorded in the consumer as a gitlink the way a
# mounted memory submodule is: its .git is a gitfile pointing into the
# consumer's .git/modules/, which a directory-only '.git/' exclude would copy.
# memory/tier/ nests a second repo with a .git directory, the other shape. Each
# copied fact.md pairs with an absent .git: a sync that skipped a nested repo
# whole would pass the second.
make_consumer
mkdir -p "$consumer/.git/modules"
git init -q --separate-git-dir "$consumer/.git/modules/memory" "$consumer/memory"
git init -q "$consumer/memory/tier"
printf 'a fact\n' | tee "$consumer/memory/fact.md" > "$consumer/memory/tier/fact.md"
git -C "$consumer/memory" add fact.md
git -C "$consumer/memory" \
    -c user.name=fixture -c user.email=fixture@example.invalid \
    -c commit.gpgsign=false commit -q -m fact
git -C "$consumer" update-index --add --cacheinfo \
    "160000,$(git -C "$consumer/memory" rev-parse HEAD),memory"
commit_all
assert_eq "$(git -C "$consumer" ls-files -s memory | cut -c1-6)" "160000" \
    "a nested repo's .git stays out: memory is a gitlink in the fixture"
assert_file "$consumer/memory/.git" \
    "a nested repo's .git stays out: memory/.git is a gitfile in the fixture"
run_dogfood sync
assert_eq "$rc" "0" "a nested repo's .git stays out exit code"
for p in memory memory/tier; do
    assert_file "$consumer/dist/plugin/$p/fact.md" \
        "a nested repo's .git stays out: $p/fact.md is copied"
    assert_absent "$consumer/dist/plugin/$p/.git" "a nested repo's .git stays out: $p"
done

echo "=== a path ignored inside a submodule stays out ==="
# sub/ is a real submodule, and sub/inner/ a submodule of it; "tail sub/" is a
# sibling of sub/ that sorts after it. Each ignores its own build/ through its
# own .gitignore, which the superproject's ls-files does not read. Each absent
# build/ pairs with a copied tracked file beside it, so a sync that dropped
# submodules whole would not pass. "tail sub/" is the one a loop meets only
# after the recursion into sub/ has returned: a recursion that leaked its state
# into the loop would skip it and copy its build/. The
# fixture's git reads no global or system config: its submodules come from
# local paths, which protocol.file.allow must permit, and an excludes file of
# the machine's could ignore build/ on its own.
make_consumer
fixture_git() {
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 git \
        -c user.name=fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false -c protocol.file.allow=always "$@"
}
for src in inner-src sub-src tail-src; do
    fixture_git init -q "$sandbox/$src"
    printf '/build/\n' > "$sandbox/$src/.gitignore"
    printf 'tracked\n' > "$sandbox/$src/tool.md"
    [[ "$src" != sub-src ]] ||
        fixture_git -C "$sandbox/$src" submodule add -q "$sandbox/inner-src" inner
    fixture_git -C "$sandbox/$src" add -A
    fixture_git -C "$sandbox/$src" commit -q -m "$src"
done
fixture_git -C "$consumer" submodule add -q "$sandbox/sub-src" sub
fixture_git -C "$consumer" submodule add -q "$sandbox/tail-src" "tail sub"
fixture_git -C "$consumer" submodule update -q --init --recursive
fixture_git -C "$consumer" commit -q -m submodule
for p in sub sub/inner "tail sub"; do
    mkdir "$consumer/$p/build"
    printf 'noise\n' > "$consumer/$p/build/out.bin"
    assert_eq "$(fixture_git -C "$consumer/$p" ls-files -z -o -i --exclude-standard --directory |
        tr '\0' '|')" "build/|" "a path ignored inside a submodule: $p's own ignore list"
done
assert_eq "$(fixture_git -C "$consumer" ls-files -z -o -i --exclude-standard --directory |
    tr '\0' '|')" "" "a path ignored inside a submodule: the superproject's ignore list"
run_dogfood sync
assert_eq "$rc" "0" "a path ignored inside a submodule exit code"
assert_eq "$err" "" "a path ignored inside a submodule prints nothing on stderr"
for p in sub sub/inner "tail sub"; do
    assert_file "$consumer/dist/plugin/$p/tool.md" \
        "a path ignored inside a submodule: $p/tool.md is copied"
    assert_absent "$consumer/dist/plugin/$p/build" \
        "a path ignored inside a submodule: $p/build is left out"
    assert_absent "$consumer/dist/plugin/$p/.git" \
        "a path ignored inside a submodule: $p/.git is left out"
done

echo "=== an uninitialised submodule is copied empty and not entered ==="
# "bare sub" is a gitlink whose checkout was never initialised, as in a
# consumer cloned without --recursive: an empty directory, no .git. A git run
# in it finds the superproject and lists the same gitlink again, so a sync that
# entered it would recurse without end; run_dogfood's timeout turns that into a
# non-zero rc where one exists. The empty directory is present in the copy.
make_consumer
fixture_git init -q "$sandbox/bare-src"
printf 'tracked\n' > "$sandbox/bare-src/tool.md"
fixture_git -C "$sandbox/bare-src" add -A
fixture_git -C "$sandbox/bare-src" commit -q -m bare-src
fixture_git -C "$consumer" submodule add -q "$sandbox/bare-src" "bare sub"
fixture_git -C "$consumer" submodule deinit -q -f "bare sub"
fixture_git -C "$consumer" commit -q -m uninitialised
assert_eq "$(git -C "$consumer" ls-files -s "bare sub" | cut -c1-6)" "160000" \
    "an uninitialised submodule: bare sub is a gitlink in the fixture"
assert_absent "$consumer/bare sub/.git" \
    "an uninitialised submodule: the fixture's bare sub holds no .git"
run_dogfood sync
assert_eq "$rc" "0" "an uninitialised submodule exit code"
assert_eq "$err" "" "an uninitialised submodule prints nothing on stderr"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "an uninitialised submodule: the rest of the tree is copied"
if [[ ! -d "$consumer/dist/plugin/bare sub" ]]; then
    fail "an uninitialised submodule: the empty directory is missing from the copy"
elif [[ -n "$(ls -A "$consumer/dist/plugin/bare sub")" ]]; then
    fail "an uninitialised submodule: the directory in the copy is not empty"
fi

echo "=== sync never recurses into the copy ==="
# Checked after each sync. The first is the one only the script's own hard
# /dist/plugin/ exclude protects: the copy does not exist when git lists the
# ignored paths, so the ignore list cannot name it. From the second on, the
# ignore list excludes it too, and --delete-excluded clears a nested copy the
# first sync left.
make_consumer
run_dogfood sync
assert_eq "$rc" "0" "sync never recurses into the copy: first sync exit code"
assert_absent "$consumer/dist/plugin/dist/plugin" "sync never recurses into the copy: first sync"
run_dogfood sync
assert_eq "$rc" "0" "sync never recurses into the copy exit code"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "sync never recurses into the copy: the copy exists"
assert_absent "$consumer/dist/plugin/dist/plugin" "sync never recurses into the copy"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood sync nested scenarios passed\n'

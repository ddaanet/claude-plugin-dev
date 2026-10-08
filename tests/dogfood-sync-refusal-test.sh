#!/usr/bin/env bash
# End-to-end test of toolkit/dogfood.sh sync against real git repos in a temp
# dir: what it refuses or aborts on, and how it reports a git or rsync failure.
# Each scenario builds a consumer fixture and runs the script as a consumer
# would, from its vendored spot at plugin-dev/dogfood.sh. The copy behaviour is
# in dogfood-sync-test.sh.
#
# Usage: bash tests/dogfood-sync-refusal-test.sh   (run from repo root)
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
    sandbox="$(cd "$(mktemp -d)" && pwd -P)"
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

# run_dogfood <args...>: run the vendored script with the cwd at $sandbox and
# CLAUDE_PROJECT_DIR naming a directory that is not the consumer. Sets $rc,
# $out (stdout) and $err (stderr).
run_dogfood() {
    mkdir -p "$sandbox/elsewhere"
    local errfile="$sandbox/stderr"
    set +e
    out="$(cd "$sandbox" && CLAUDE_PROJECT_DIR="$sandbox/elsewhere" \
        bash "$consumer/plugin-dev/dogfood.sh" "$@" 2>"$errfile")"
    rc=$?
    set -e
    err="$(cat "$errfile")"
}

echo "=== an ignored entry holding a pattern character aborts ==="
# One fixture per name, so one name cannot mask another. rsync would read the
# entry as a pattern, so the script refuses before it runs: the sentinel
# pre-placed in the copy survives (it is not source, so --delete would remove
# it) and the committed new.md is not copied. The name is matched as a fixed
# string, not through assert_contains, whose needle is a live BRE.
for name in 'a*b.log' 'a?b.log' 'a[b.log' 'a]b.log' 'a\b.log'; do
    make_consumer
    printf '*.log\n' >> "$consumer/.gitignore"
    printf 'noise\n' > "$consumer/$name"
    commit_all
    printf 'new\n' > "$consumer/skills/demo/new.md"
    commit_all
    assert_eq "$(git -C "$consumer" ls-files -z -o -i --exclude-standard --directory |
        tr '\0' '|')" "$name|" \
        "a pattern character ($name): the fixture's ignore list"
    mkdir -p "$consumer/dist/plugin"
    printf 'keep\n' > "$consumer/dist/plugin/sentinel"
    run_dogfood sync
    assert_eq "$rc" "1" "a pattern character ($name) exit code"
    assert_eq "$out" "" "a pattern character ($name) prints nothing on stdout"
    if [[ "$err" != "dogfood: "*"$name"* || "$err" == *$'\n'* ]]; then
        fail "a pattern character ($name): stderr is not one dogfood: line naming it: '$err'"
    fi
    assert_file "$consumer/dist/plugin/sentinel" \
        "a pattern character ($name): the copy is untouched"
    assert_absent "$consumer/dist/plugin/skills/demo/new.md" \
        "a pattern character ($name): rsync never ran"
done
# Only ignore-list entries reach rsync as patterns: a tracked and an untracked
# name holding every pattern character are source, copied as themselves.
make_consumer
odd='a*?[]\b.md'
printf 'tracked\n' > "$consumer/skills/demo/$odd"
commit_all
printf 'untracked\n' > "$consumer/$odd"
run_dogfood sync
assert_eq "$rc" "0" "a pattern character outside the ignore list: exit code"
assert_file "$consumer/dist/plugin/skills/demo/$odd" \
    "a pattern character outside the ignore list: a tracked name is copied"
assert_file "$consumer/dist/plugin/$odd" \
    "a pattern character outside the ignore list: an untracked name is copied"

echo "=== refuses without a root manifest ==="
make_consumer
rm "$consumer/.claude-plugin/plugin.json"
commit_all
run_dogfood sync
assert_eq "$rc" "1" "no manifest exit code"
assert_eq "$out" "" "no manifest prints nothing on stdout"
if [[ "$err" != "dogfood: "*".claude-plugin/plugin.json"* || "$err" == *$'\n'* ]]; then
    fail "no manifest: stderr is not one dogfood: line naming the manifest: '$err'"
fi
assert_absent "$consumer/dist/plugin" "no manifest: the copy is not created"

echo "=== refuses when dist/plugin is not ignored ==="
# The first-sync case: no dist/plugin/ yet. A check that drops the trailing
# slash refuses here too; the first sync of every other test, where
# /dist/plugin/ is ignored, is what reds it. The precondition rules out a
# global excludes file ignoring dist/ behind the emptied .gitignore.
make_consumer
: > "$consumer/.gitignore"
commit_all
assert_absent "$consumer/dist/plugin" "not ignored: the fixture has no copy yet"
if git -C "$consumer" check-ignore -q dist/plugin/; then
    fail "not ignored: the fixture still ignores dist/plugin/"
fi
run_dogfood sync
assert_eq "$rc" "1" "not ignored exit code"
assert_eq "$out" "" "not ignored prints nothing on stdout"
if [[ "$err" != "dogfood: "*"/dist/plugin/"* || "$err" == *$'\n'* ]]; then
    fail "not ignored: stderr is not one dogfood: line naming /dist/plugin/: '$err'"
fi
assert_absent "$consumer/dist/plugin" "not ignored: the copy is not created"

echo "=== refuses without rsync on PATH ==="
# The whole PATH is a directory of symlinks to the other commands the run
# needs, so rsync alone is missing. A sync that makes dist/plugin before it
# finds rsync gone leaves an empty copy, which the shim would launch as a
# promoted one: the refusal must come before dist/ is touched.
make_consumer
mkdir "$sandbox/tools"
for tool in bash cat dirname git mkdir mktemp rm; do
    ln -s "$(command -v "$tool")" "$sandbox/tools/$tool"
done
assert_eq "$(PATH="$sandbox/tools" command -v rsync || true)" "" \
    "no rsync: the fixture's PATH holds no rsync"
PATH="$sandbox/tools" run_dogfood sync
assert_eq "$rc" "1" "no rsync exit code"
assert_eq "$out" "" "no rsync prints nothing on stdout"
if [[ "$err" != "dogfood: "*"rsync"* || "$err" == *$'\n'* ]]; then
    fail "no rsync: stderr is not one dogfood: line naming rsync: '$err'"
fi
assert_absent "$consumer/dist/plugin" "no rsync: the copy is not created"

echo "=== a git failure stops sync before rsync ==="
# A stub git first on PATH fails ls-files alone, after the refusal checks have
# passed. Removing .git instead would fail the ignore check's own git call
# first, leaving an unguarded ignore list green. Nothing may reach dist/: rsync
# on a partial ignore list would copy into it.
make_consumer
mkdir "$sandbox/stub"
real_git="$(command -v git)"
cat > "$sandbox/stub/git" <<EOF
#!/usr/bin/env bash
for a; do [[ "\$a" == ls-files ]] && { echo 'git: stub failure' >&2; exit 128; }; done
exec "$real_git" "\$@"
EOF
chmod +x "$sandbox/stub/git"
PATH="$sandbox/stub:$PATH" run_dogfood sync
if [[ "$rc" == "0" ]]; then
    fail "a git failure: exit code is 0"
fi
assert_contains "$err" "git: stub failure" "a git failure: the run reached ls-files"
assert_absent "$consumer/dist" "a git failure: dist/ is not created"

# make_submodule: make $consumer/memory a repo of its own, recorded as a gitlink
# with a gitfile .git, the shape of a mounted memory submodule, ignoring *.log.
# No network and no clone, so no protocol.file.allow and no global config.
make_submodule() {
    mkdir -p "$consumer/.git/modules"
    git init -q --separate-git-dir "$consumer/.git/modules/memory" "$consumer/memory"
    printf '*.log\n' > "$consumer/memory/.gitignore"
    printf 'a fact\n' > "$consumer/memory/fact.md"
    git -C "$consumer/memory" add .gitignore fact.md
    git -C "$consumer/memory" \
        -c user.name=fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false commit -q -m fact
    git -C "$consumer" update-index --add --cacheinfo \
        "160000,$(git -C "$consumer/memory" rev-parse HEAD),memory"
    commit_all
}

echo "=== a git failure inside a submodule stops sync before rsync ==="
# The stub fails ls-files only when run on the submodule, so the root's own
# listing succeeds and only the recursion meets the failure. Nothing may reach
# dist/, as for a failure at the root.
make_consumer
make_submodule
mkdir "$sandbox/stub"
cat > "$sandbox/stub/git" <<EOF
#!/usr/bin/env bash
[[ "\$1" == -C && "\$2" == */memory && " \$* " == *" ls-files "* ]] &&
    { echo 'git: stub failure in memory' >&2; exit 128; }
exec "$real_git" "\$@"
EOF
chmod +x "$sandbox/stub/git"
PATH="$sandbox/stub:$PATH" run_dogfood sync
if [[ "$rc" == "0" ]]; then
    fail "a git failure inside a submodule: exit code is 0"
fi
assert_contains "$err" "git: stub failure in memory" \
    "a git failure inside a submodule: the run reached the submodule's ls-files"
assert_absent "$consumer/dist" "a git failure inside a submodule: dist/ is not created"

echo "=== a git failure on the gitlink listing stops sync before rsync ==="
# The stub fails ls-files only when asked for the staged listing, -s, which
# comes after the ignored listing: that one succeeds, so only the gitlink
# listing meets the failure. A listing that swallowed it would skip the repo's
# submodules in silence and let rsync copy their ignored files.
make_consumer
mkdir "$sandbox/stub"
cat > "$sandbox/stub/git" <<EOF
#!/usr/bin/env bash
[[ " \$* " == *" ls-files "* && " \$* " == *" -s "* ]] &&
    { echo 'git: stub failure on -s' >&2; exit 128; }
exec "$real_git" "\$@"
EOF
chmod +x "$sandbox/stub/git"
PATH="$sandbox/stub:$PATH" run_dogfood sync
if [[ "$rc" == "0" ]]; then
    fail "a git failure on the gitlink listing: exit code is 0"
fi
assert_contains "$err" "git: stub failure on -s" \
    "a git failure on the gitlink listing: the run reached the -s listing"
assert_absent "$consumer/dist" "a git failure on the gitlink listing: dist/ is not created"

echo "=== a pattern character inside a submodule aborts ==="
# memory/a*b.log is ignored by the submodule's own *.log, so it reaches the
# exclude list as memory/a*b.log and is refused with its prefix, before rsync
# runs or dist/ is touched.
make_consumer
make_submodule
printf 'noise\n' > "$consumer/memory/a*b.log"
run_dogfood sync
assert_eq "$rc" "1" "a pattern character inside a submodule exit code"
if [[ "$err" != "dogfood: "*"memory/a*b.log"* || "$err" == *$'\n'* ]]; then
    fail "a pattern character inside a submodule: stderr is not one dogfood: line naming memory/a*b.log: '$err'"
fi
assert_absent "$consumer/dist" "a pattern character inside a submodule: dist/ is not created"

echo "=== a symlinked dist/plugin is refused and the root survives ==="
# dist/plugin links to the root itself, so rsync would mirror the root onto
# itself and --delete-excluded would delete its .git. Nothing in sync checks
# for the link: git check-ignore fails on a pathspec beyond a symbolic link
# (exit 128), and that git error alone stops the run. The link comes after
# commit_all, since /dist/plugin/ matches directories only and add -A would
# track it. An explicit --git-dir keeps git from finding a parent repo once
# .git is gone.
make_consumer
mkdir "$consumer/dist"
ln -s .. "$consumer/dist/plugin"
run_dogfood sync
if [[ "$rc" == "0" ]]; then
    fail "a symlinked dist/plugin: exit code is 0"
fi
assert_eq "$out" "" "a symlinked dist/plugin prints nothing on stdout"
assert_contains "$err" "beyond a symbolic link" \
    "a symlinked dist/plugin: git's diagnosis reaches stderr"
assert_file "$consumer/.git/HEAD" "a symlinked dist/plugin: the root's .git survives"
if ! git --git-dir="$consumer/.git" --work-tree="$consumer" diff-index --quiet HEAD --; then
    fail "a symlinked dist/plugin: the root's tracked files changed"
fi

echo "=== an rsync failure keeps its status and stderr ==="
# The stub stands in for rsync alone: git runs for real, so the run reaches
# rsync. Its status and its one stderr line must arrive unaltered.
make_consumer
mkdir "$sandbox/stub"
cat > "$sandbox/stub/rsync" <<'EOF'
#!/usr/bin/env bash
echo 'rsync: stub failure' >&2
exit 23
EOF
chmod +x "$sandbox/stub/rsync"
PATH="$sandbox/stub:$PATH" run_dogfood sync
assert_eq "$rc" "23" "an rsync failure: exit code is rsync's own"
assert_eq "$(printf '%s\n' "$err" | grep -c -x 'rsync: stub failure')" "1" \
    "an rsync failure: its stderr line appears exactly once"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood sync refusal scenarios passed\n'

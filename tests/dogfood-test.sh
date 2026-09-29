#!/usr/bin/env bash
# End-to-end test of toolkit/dogfood.sh against real git repos in a temp dir.
# Each scenario builds a consumer fixture and runs the script as a consumer
# would, from its vendored spot at plugin-dev/dogfood.sh.
#
# Usage: bash tests/dogfood-test.sh   (run from repo root)
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
    if ! printf '%s' "$1" | grep -q -- "$2"; then
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
    set +e
    out="$(cd "$sandbox" && CLAUDE_PROJECT_DIR="$sandbox/elsewhere" \
        bash "$consumer/plugin-dev/dogfood.sh" "$@" 2>"$errfile")"
    rc=$?
    set -e
    err="$(cat "$errfile")"
}

echo "=== sync copies a tracked file ==="
make_consumer
run_dogfood sync
assert_eq "$rc" "0" "sync copies a tracked file exit code"
assert_eq "$out" "" "sync copies a tracked file prints nothing on stdout"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" "sync copies a tracked file"
if ! cmp -s "$consumer/skills/demo/SKILL.md" "$consumer/dist/plugin/skills/demo/SKILL.md"; then
    fail "sync copies a tracked file: copy bytes differ from the source"
fi
# -ef is true for a hardlink and for a path through a symlinked directory,
# neither of which -L on the file itself sees.
if [[ "$consumer/skills/demo/SKILL.md" -ef "$consumer/dist/plugin/skills/demo/SKILL.md" ]]; then
    fail "sync copies a tracked file: the copy is the source file itself"
fi

echo "=== sync leaves out an ignored file and .git ==="
# Each absence is paired with a presence differing only in what excludes it:
# the tracked kept.log beside the ignored build.log, the tracked
# .claude-plugin/ beside .git. The deep skills/ copy alone would let a sync
# that drops root-level files, or dot-directories, pass.
make_consumer
printf 'build.log\n' >> "$consumer/.gitignore"
printf 'noise\n' > "$consumer/build.log"
printf 'kept\n' > "$consumer/kept.log"
commit_all
run_dogfood sync
assert_eq "$rc" "0" "sync leaves out an ignored file exit code"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "sync leaves out an ignored file: the copy exists"
assert_file "$consumer/dist/plugin/kept.log" \
    "sync leaves out an ignored file: a tracked root-level file is copied"
assert_file "$consumer/dist/plugin/.claude-plugin/plugin.json" \
    "sync leaves out .git: the tracked .claude-plugin/ is copied"
assert_absent "$consumer/dist/plugin/build.log" "sync leaves out an ignored file"
assert_absent "$consumer/dist/plugin/.git" "sync leaves out .git"

echo "=== sync resolves the root from its own location ==="
# The cwd and CLAUDE_PROJECT_DIR are both valid plugin roots, so a script that
# prefers either one, falling back to its own location, syncs the decoy.
make_consumer
make_decoy "$sandbox"
make_decoy "$sandbox/elsewhere"
run_dogfood sync
assert_eq "$rc" "0" "sync resolves the root exit code"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "sync resolves the root from its own location"
assert_absent "$sandbox/elsewhere/dist" "sync resolves the root: CLAUDE_PROJECT_DIR untouched"
assert_absent "$sandbox/dist" "sync resolves the root: cwd untouched"

echo "=== unknown subcommand is usage ==="
make_consumer
run_dogfood bogus
assert_eq "$rc" "2" "unknown subcommand exit code"
assert_eq "$out" "" "unknown subcommand prints nothing on stdout"
for word in sync pre-tool session-start; do
    assert_contains "$err" "$word" "unknown subcommand usage names $word"
done
run_dogfood
assert_eq "$rc" "2" "no subcommand exit code"
assert_eq "$out" "" "no subcommand prints nothing on stdout"
for word in sync pre-tool session-start; do
    assert_contains "$err" "$word" "no subcommand usage names $word"
done

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood scenarios passed\n'

#!/usr/bin/env bash
# End-to-end test of toolkit/bin/claude, the dogfood launcher shim: what it
# hands the next claude on PATH. Each scenario builds a consumer fixture with
# the shim vendored at plugin-dev/bin/claude, puts a stub claude behind it, and
# launches `claude` by PATH lookup as a developer would.
#
# Usage: bash tests/dogfood-launcher-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo via `-C`, never this
# repo, so it's always safe to drop them here.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below
# A runner launched through some plugin's dogfood shim carries its own copy
# here; a scenario that wants an inherited value exports one itself.
unset CLAUDE_CODE_PLUGIN_DIRS
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
# (physical spelling: macOS $TMPDIR sits under a symlink) and:
#   $consumer    a git repo whose own path contains a space, with the shim and
#                dogfood.sh vendored under plugin-dev/
#   $shim_dir    the spelling of the shim's directory put on PATH
#   $launch_dir  the directory claude is launched from, $consumer
#   $stubdir     a stub claude that records under $sandbox/rec/ its argv, pid,
#                PWD, PATH, CDPATH, CLAUDE_CODE_PLUGIN_DIRS and whether the
#                copy's manifest existed as it started, then exits 0
make_consumer() {
    sandbox="$(cd "$(mktemp -d)" && pwd -P)"
    sandboxes+=("$sandbox")
    consumer="$sandbox/my consumer"
    shim_dir="$consumer/plugin-dev/bin"
    launch_dir="$consumer"
    stubdir="$sandbox/stub"
    mkdir -p "$consumer/.claude-plugin" "$consumer/skills/demo" \
        "$consumer/plugin-dev/bin" "$stubdir" "$sandbox/rec"
    git -C "$consumer" init -q
    printf '{"name":"fixture","version":"1.0.0"}\n' > "$consumer/.claude-plugin/plugin.json"
    printf '/dist/plugin/\n' > "$consumer/.gitignore"
    printf '# demo skill\n' > "$consumer/skills/demo/SKILL.md"
    cp "$repo_root/toolkit/dogfood.sh" "$consumer/plugin-dev/dogfood.sh"
    cp "$repo_root/toolkit/bin/claude" "$consumer/plugin-dev/bin/claude"
    chmod +x "$consumer/plugin-dev/bin/claude"
    cat > "$stubdir/claude" <<STUB
#!/usr/bin/env bash
rec="$sandbox/rec"
if [[ -f "$consumer/dist/plugin/.claude-plugin/plugin.json" ]]; then
    printf 'present' > "\$rec/copy"
else
    printf 'absent' > "\$rec/copy"
fi
printf '%s\0' "\$@" > "\$rec/argv"
printf '%s' "\$\$" > "\$rec/pid"
printf '%s' "\$PWD" > "\$rec/pwd"
printf '%s' "\$PATH" > "\$rec/path"
printf '%s' "\${CDPATH-<unset>}" > "\$rec/cdpath"
printf '%s' "\${CLAUDE_CODE_PLUGIN_DIRS-<unset>}" > "\$rec/plugin_dirs"
exit 0
STUB
    chmod +x "$stubdir/claude"
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

# run_claude <args...>: launch `claude` by PATH lookup from $launch_dir, the
# shim first by its $shim_dir spelling, then the stub. CDPATH goes in as /tmp.
# Bounded by a watchdog: run in the background and killed after 10 s, which
# fails the test. Sets $rc and $launch_pid, the pid `claude` was launched as;
# stdout and stderr are left in $sandbox/stdout and $sandbox/stderr.
run_claude() {
    local errfile="$sandbox/stderr" outfile="$sandbox/stdout" watcher
    rm -f "$sandbox/killed"
    set +e
    (
        cd "$launch_dir"
        export PATH="$shim_dir:$stubdir:$PATH"
        export CDPATH=/tmp
        exec claude "$@"
    ) >"$outfile" 2>"$errfile" &
    launch_pid=$!
    # Killing the watcher orphans its sleep; pointed at /dev/null, the orphan
    # holds no pipe of the suite's caller open for the rest of the 10 s.
    ( sleep 10 >/dev/null 2>&1; : > "$sandbox/killed"; kill "$launch_pid" ) &
    watcher=$!
    wait "$launch_pid"
    rc=$?
    if [[ -e "$sandbox/killed" ]]; then
        fail "the launcher ran past the 10 s watchdog"
    else
        kill "$watcher"
    fi
    wait "$watcher"
    set -e
}

# recorded <name>: what the stub wrote, or a marker when it never ran.
recorded() {
    if [[ -f "$sandbox/rec/$1" ]]; then
        cat "$sandbox/rec/$1"
    else
        printf '<stub did not record %s>' "$1"
    fi
}

echo "=== the shim execs the next claude with argv intact ==="
make_consumer
run_claude --foo 'a b'
assert_eq "$rc" "0" "the shim execs with argv intact exit code"
assert_eq "$(recorded argv | tr '\0' '|')" "--foo|a b|" \
    "the shim execs the next claude with argv intact"
assert_eq "$(recorded pid)" "$launch_pid" \
    "the shim execs the next claude in its own process, not a child"

echo "=== the shim syncs before exec ==="
make_consumer
assert_absent "$consumer/dist" "the fixture starts with no copy"
run_claude
assert_eq "$(recorded copy)" "present" \
    "the shim syncs before exec: the copy existed as the next claude started"
assert_file "$consumer/dist/plugin/.claude-plugin/plugin.json" \
    "the shim syncs before exec"

# <root> comes from the shim's physical location alone: the shim is reached
# through a symlinked spelling of the consumer, which a <root> resolved
# logically would record, and launched from outside the consumer, which a
# <root> taken from the launch directory would record.
echo "=== the shim exports the copy ==="
make_consumer
ln -s "$consumer" "$sandbox/link"
shim_dir="$sandbox/link/plugin-dev/bin"
mkdir "$sandbox/elsewhere"
launch_dir="$sandbox/elsewhere"
run_claude
assert_eq "$(recorded plugin_dirs)" "$consumer/dist/plugin" \
    "the shim exports the copy"

echo "=== the shim unsets CDPATH ==="
make_consumer
run_claude
assert_eq "$(recorded cdpath)" "<unset>" "the shim unsets CDPATH"

echo "=== an inherited variable is overwritten ==="
make_consumer
CLAUDE_CODE_PLUGIN_DIRS=/elsewhere/dist/plugin run_claude
assert_eq "$(recorded plugin_dirs)" "$consumer/dist/plugin" \
    "an inherited variable is overwritten"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood launcher scenarios passed\n'

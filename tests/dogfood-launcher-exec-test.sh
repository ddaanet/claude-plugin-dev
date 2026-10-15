#!/usr/bin/env bash
# End-to-end test of toolkit/bin/claude, the dogfood launcher shim: what it
# hands the next claude on PATH. Each scenario builds a consumer fixture with
# the shim vendored at plugin-dev/bin/claude, puts a stub claude behind it, and
# launches `claude` by PATH lookup as a developer would.
#
# Scope: what the shim execs and when it warns -- argv, no sync, a missing or
# non-directory copy, no next claude. Its sibling dogfood-launcher-path-test.sh
# covers the exported copy and the PATH handling.
#
# Usage: bash tests/dogfood-launcher-exec-test.sh   (run from repo root)
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
#   $path_head   the PATH entries put ahead of the inherited PATH; empty means
#                $shim_dir:$stubdir
#   $path_exact  when set, the whole PATH, nothing inherited appended; empty
#                means $path_head's rule
#   $stubdir     a stub claude that records under $sandbox/rec/ its argv, pid,
#                PWD, PATH, CDPATH, CLAUDE_CODE_PLUGIN_DIRS and whether the
#                copy's manifest existed as it started, then exits 0
# The copy exists and is empty, as if promoted before the manifest was written:
# a sync at launch would put the manifest in it.
make_consumer() {
    sandbox="$(cd "$(mktemp -d)" && pwd -P)"
    sandboxes+=("$sandbox")
    consumer="$sandbox/my consumer"
    shim_dir="$consumer/plugin-dev/bin"
    launch_dir="$consumer"
    stubdir="$sandbox/stub"
    path_head=""
    path_exact=""
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
    mkdir -p "$consumer/dist/plugin"
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
# shim first by its $shim_dir spelling, then the stub, unless $path_head says
# otherwise, or $path_exact, when set, is the whole PATH. CDPATH goes in as
# /tmp.
# Bounded by a watchdog: run in the background and killed after 10 s, which
# fails the test. Sets $rc and $launch_pid, the pid `claude` was launched as;
# stdout and stderr are left in $sandbox/stdout and $sandbox/stderr.
run_claude() {
    local errfile="$sandbox/stderr" outfile="$sandbox/stdout" watcher
    rm -f "$sandbox/killed"
    set +e
    (
        cd "$launch_dir"
        # shellcheck disable=SC2030  # the subshell's PATH is the point
        if [[ -n "${path_exact:-}" ]]; then
            export PATH="$path_exact"
        else
            export PATH="${path_head:-$shim_dir:$stubdir}:$PATH"
        fi
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

# Only `just dogfood` promotes: a launch from a plain shell, the variable unset,
# loads the copy as it stands. The copy starts empty, so a sync at launch shows
# as the manifest in it.
echo "=== a launch does not sync, the variable unset ==="
make_consumer
run_claude
assert_eq "$rc" "0" "a launch does not sync, the variable unset: exit code"
assert_eq "$(recorded copy)" "absent" \
    "a launch does not sync, the variable unset: the copy as the next claude started"
assert_absent "$consumer/dist/plugin/.claude-plugin" \
    "a launch does not sync, the variable unset: the copy after the launch"
assert_eq "$(recorded plugin_dirs)" "$consumer/dist/plugin" \
    "a launch does not sync, the variable unset: the next claude gets the copy"
assert_eq "$(cat "$sandbox/stderr")" "" \
    "a launch does not sync, the variable unset: stderr is empty"

# With no copy the shim still launches: it warns on one line naming the step
# that makes the copy, and exports nothing, so the session starts plain and
# session-start reports it. Creating the copy would be a promotion nobody asked
# for, and exporting a path that is not there would hand the next claude a
# plugin dir with nothing in it.
echo "=== a missing copy warns and launches without it ==="
make_consumer
rm -r "$consumer/dist"
run_claude --foo 'a b'
assert_eq "$rc" "0" "a missing copy warns and launches: exit code"
assert_eq "$(wc -l < "$sandbox/stderr" | tr -d ' ')" "1" \
    "a missing copy warns and launches: stderr is one line"
if ! grep -qE '^dogfood: .*just dogfood' "$sandbox/stderr"; then
    fail "a missing copy warns and launches: no dogfood: line naming just dogfood: $(cat "$sandbox/stderr")"
fi
assert_eq "$(recorded argv | tr '\0' '|')" "--foo|a b|" \
    "a missing copy warns and launches: the next claude gets argv intact"
assert_eq "$(recorded pid)" "$launch_pid" \
    "a missing copy warns and launches: exec, not a child"
assert_eq "$(recorded plugin_dirs)" "<unset>" \
    "a missing copy warns and launches: the variable stays unset"
assert_absent "$consumer/dist" "a missing copy warns and launches: no copy made"

# An inherited value is the environment's, not the shim's: with no copy to
# point at, the shim leaves it as it came.
echo "=== a missing copy passes an inherited variable through ==="
make_consumer
rm -r "$consumer/dist"
CLAUDE_CODE_PLUGIN_DIRS="/elsewhere/dist/plugin:/other" run_claude
assert_eq "$rc" "0" "a missing copy passes an inherited variable through: exit code"
assert_eq "$(recorded plugin_dirs)" "/elsewhere/dist/plugin:/other" \
    "a missing copy passes an inherited variable through"

# A regular file where the copy belongs is no copy: exported, it would hand
# the next claude a variable naming a file, and session-start, comparing it as
# spelled, would stay silent.
echo "=== a file at dist/plugin is no copy ==="
make_consumer
rmdir "$consumer/dist/plugin"
printf 'not a copy\n' > "$consumer/dist/plugin"
run_claude --foo
assert_eq "$rc" "0" "a file at dist/plugin is no copy: exit code"
if ! grep -qE '^dogfood: .*just dogfood' "$sandbox/stderr"; then
    fail "a file at dist/plugin is no copy: no dogfood: line naming just dogfood: $(cat "$sandbox/stderr")"
fi
assert_eq "$(recorded plugin_dirs)" "<unset>" \
    "a file at dist/plugin is no copy: the variable stays unset"
assert_file "$consumer/dist/plugin" "a file at dist/plugin is no copy: the file is left alone"

# With no copy and no other claude both lines appear, the warning first: the
# copy check runs before the lookup. The PATH is the 127 scenario's: the shim
# and the commands it runs.
echo "=== a missing copy and no next claude: the warning, then 127 ==="
make_consumer
rm -r "$consumer/dist"
mkdir "$sandbox/tools"
for tool in bash dirname; do
    ln -s "$(command -v "$tool")" "$sandbox/tools/$tool"
done
path_exact="$shim_dir:$sandbox/tools"
run_claude
assert_eq "$rc" "127" "a missing copy and no next claude: exit code"
assert_eq "$(wc -l < "$sandbox/stderr" | tr -d ' ')" "2" \
    "a missing copy and no next claude: stderr is two lines"
first="$(head -n1 "$sandbox/stderr")"
if ! grep -qE '^dogfood: .*just dogfood' <<<"$first"; then
    fail "a missing copy and no next claude: the first line is not the warning: $(cat "$sandbox/stderr")"
fi
assert_eq "$(tail -n1 "$sandbox/stderr")" "dogfood: no other claude on PATH" \
    "a missing copy and no next claude: the second line is the 127 line"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood launcher exec scenarios passed\n'

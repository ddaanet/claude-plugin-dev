#!/usr/bin/env bash
# End-to-end test of toolkit/bin/claude, the dogfood launcher shim: the copy's
# bin/ on the PATH it hands the next claude. Each scenario builds a consumer
# fixture with the shim vendored at plugin-dev/bin/claude, puts a stub claude
# behind it, and launches `claude` by PATH lookup as a developer would.
#
# Scope: the directory <root>/dist/plugin/bin appended to PATH -- after the
# user's entries, with or without a copy. Its siblings
# dogfood-launcher-path-test.sh and dogfood-launcher-exec-test.sh cover the rest
# of the PATH handling, and the exec, argv and missing-copy paths.
#
# Usage: bash tests/dogfood-launcher-bin-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/dogfood-launcher-bin.XXXXXX")" || exit 1
    sandbox="$(cd "$sandbox" && pwd -P)"
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

# Claude Code puts a marketplace-installed plugin's bin/ last on the Bash tool's
# PATH and puts none there for a plugin loaded through CLAUDE_CODE_PLUGIN_DIRS,
# so the shim stands in for the install and appends <root>/dist/plugin/bin.
# $consumer holds a space: an unquoted append would split it into two entries.
# Residual bound: a root holding a colon would split on PATH's own delimiter,
# and nothing here claims to survive that.
echo "=== the shim appends the copy's bin to PATH ==="
make_consumer
bin="$consumer/dist/plugin/bin"
mkdir -p "$bin"
printf '#!/bin/sh\n' > "$bin/demo-tool"
chmod +x "$bin/demo-tool"
run_claude
# shellcheck disable=SC2031  # the suite's own PATH, which the launch appended
assert_eq "$(recorded path)" "$stubdir:$PATH:$bin" \
    "the shim appends the copy's bin to PATH: last, after every inherited entry"
found="$(PATH="$(recorded path)" command -v demo-tool || true)"
assert_eq "$found" "$bin/demo-tool" \
    "the shim appends the copy's bin to PATH: a bin command resolves"
assert_eq "$(recorded plugin_dirs)" "$consumer/dist/plugin" \
    "the shim appends the copy's bin to PATH: the copy is still exported"

# Neither the copy nor its bin/ is probed: `just dogfood` can create either in a
# session already running, and a PATH directory that does not exist is inert, so
# the entry is there for a copy without a bin/ and for no copy at all.
echo "=== a copy without a bin gets the entry ==="
make_consumer
run_claude
# shellcheck disable=SC2031  # the suite's own PATH, which the launch appended
assert_eq "$(recorded path)" "$stubdir:$PATH:$consumer/dist/plugin/bin" \
    "a copy without a bin gets the entry"

echo "=== no copy still gets the entry ==="
make_consumer
rm -rf "$consumer/dist"
run_claude
# shellcheck disable=SC2031  # the suite's own PATH, which the launch appended
assert_eq "$(recorded path)" "$stubdir:$PATH:$consumer/dist/plugin/bin" \
    "no copy still gets the entry"

# The appended directory is added after the check for another claude: a claude
# the plugin ships in bin/ is not the next claude, and must not be exec'd when
# there is none.
echo "=== a claude in the copy's bin is not the next claude ==="
make_consumer
mkdir "$sandbox/tools" "$consumer/dist/plugin/bin"
for tool in bash dirname; do
    ln -s "$(command -v "$tool")" "$sandbox/tools/$tool"
done
printf '#!/bin/sh\nprintf ran > "%s/rec/shipped"\n' "$sandbox" > "$consumer/dist/plugin/bin/claude"
chmod +x "$consumer/dist/plugin/bin/claude"
path_exact="$shim_dir:$sandbox/tools"
run_claude
assert_eq "$rc" "127" "a claude in the copy's bin is not the next claude: exit"
assert_absent "$sandbox/rec/shipped" \
    "a claude in the copy's bin is not the next claude: it did not run"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood launcher bin scenarios passed\n'

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
#   $path_head   the PATH entries put ahead of the inherited PATH; empty means
#                $shim_dir:$stubdir
#   $path_exact  when set, the whole PATH, nothing inherited appended; empty
#                means $path_head's rule
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

echo "=== the shim syncs before exec ==="
make_consumer
assert_absent "$consumer/dist" "the fixture starts with no copy"
unset CLAUDE_CODE_PLUGIN_DIRS
run_claude
assert_eq "$(recorded copy)" "present" \
    "the shim syncs before exec: the copy existed as the next claude started"
assert_file "$consumer/dist/plugin/.claude-plugin/plugin.json" \
    "the shim syncs before exec"
assert_eq "$(recorded plugin_dirs)" "$consumer/dist/plugin" \
    "the shim syncs before exec: the variable unset, the next claude gets the copy"
# The other half of a failed sync's not-started line: a launch whose sync
# succeeds leaves stderr empty.
assert_eq "$(cat "$sandbox/stderr")" "" "the shim syncs before exec: stderr is empty"

# A session already loading this repo's copy is a dogfood session of it: a
# claude an agent runs inside it inherits the variable and must not sync. The
# variable is the physical copy the shim exports, and the shim is reached
# through a symlinked spelling of the consumer: a match taken against a <root>
# resolved logically would miss and sync.
echo "=== a variable equal to this copy skips the sync ==="
make_consumer
ln -s "$consumer" "$sandbox/link"
shim_dir="$sandbox/link/plugin-dev/bin"
CLAUDE_CODE_PLUGIN_DIRS="$consumer/dist/plugin" run_claude
assert_eq "$rc" "0" "a variable equal to this copy skips the sync: exit code"
assert_absent "$consumer/dist" "a variable equal to this copy skips the sync: no copy made"
assert_eq "$(recorded copy)" "absent" \
    "a variable equal to this copy skips the sync: no copy as the next claude started"
assert_eq "$(recorded plugin_dirs)" "$consumer/dist/plugin" \
    "a variable equal to this copy skips the sync: the next claude still gets the copy"
assert_eq "$(recorded pid)" "$launch_pid" \
    "a variable equal to this copy skips the sync: the next claude still ran"

# <root> comes from the shim's physical location alone: the shim is reached
# through a symlinked spelling of the consumer, which a <root> resolved
# logically would record, and launched from outside the consumer, inside
# another consumer that sync accepts: a git repo with a manifest, the ignore
# rule and dogfood.sh vendored. A <root> taken from the launch directory, from
# git's toplevel there or from the nearest manifest above it syncs that repo
# and records its copy, rather than aborting on a sync refusal.
echo "=== the shim exports the copy ==="
make_consumer
ln -s "$consumer" "$sandbox/link"
shim_dir="$sandbox/link/plugin-dev/bin"
mkdir -p "$sandbox/elsewhere/.claude-plugin" "$sandbox/elsewhere/plugin-dev"
git init -q "$sandbox/elsewhere"
printf '{"name":"decoy","version":"1.0.0"}\n' > "$sandbox/elsewhere/.claude-plugin/plugin.json"
printf '/dist/plugin/\n' > "$sandbox/elsewhere/.gitignore"
cp "$repo_root/toolkit/dogfood.sh" "$sandbox/elsewhere/plugin-dev/dogfood.sh"
launch_dir="$sandbox/elsewhere"
run_claude
assert_eq "$(recorded plugin_dirs)" "$consumer/dist/plugin" \
    "the shim exports the copy"
assert_absent "$sandbox/elsewhere/dist" \
    "the shim exports the copy: the launch directory's repo is not synced"
# The other half of the contract: session-start, reached by the same symlinked
# spelling, accepts what the shim exported and rejects another repo's copy.
session_start() {
    (cd "$launch_dir" && CLAUDE_CODE_PLUGIN_DIRS="$1" \
        bash "$shim_dir/../dogfood.sh" session-start </dev/null)
}
assert_eq "$(session_start "$(recorded plugin_dirs)")" "" \
    "session-start takes the copy the shim exported"
if [[ "$(session_start /elsewhere/dist/plugin)" != *"does not load $consumer/dist/plugin"* ]]; then
    fail "session-start takes the copy the shim exported: another repo's copy is not rejected"
fi

echo "=== the shim unsets CDPATH ==="
make_consumer
run_claude
assert_eq "$(recorded cdpath)" "<unset>" "the shim unsets CDPATH"

echo "=== an inherited variable is overwritten ==="
make_consumer
CLAUDE_CODE_PLUGIN_DIRS=/elsewhere/dist/plugin run_claude
assert_eq "$(recorded plugin_dirs)" "$consumer/dist/plugin" \
    "an inherited variable is overwritten"
assert_eq "$(recorded copy)" "present" \
    "an inherited variable naming another path still syncs"
assert_file "$consumer/dist/plugin/.claude-plugin/plugin.json" \
    "an inherited variable naming another path still syncs"

# Only a variable equal to this copy skips the sync: one listing the copy as
# an entry beside another plugin directory, as session-start would match it,
# still syncs and is replaced.
echo "=== a variable listing this copy among others syncs ==="
make_consumer
CLAUDE_CODE_PLUGIN_DIRS="$consumer/dist/plugin:/elsewhere/dist/plugin" run_claude
assert_eq "$(recorded copy)" "present" \
    "a variable listing this copy among others syncs"
assert_eq "$(recorded plugin_dirs)" "$consumer/dist/plugin" \
    "a variable listing this copy among others syncs: the next claude gets the copy alone"

# The shim is on PATH twice ahead of the stub, once with a trailing slash, and
# twice behind it, through a symlinked directory and a /./ spelling. The stub's
# PATH may hold no entry whose claude is the shim. An entry behind the stub is
# never hopped through, so only the first hop can strip it, and only -ef, not
# a normalised spelling, recognises it.
echo "=== the shim strips its own entry in any spelling ==="
make_consumer
ln -s "$consumer" "$sandbox/link"
path_head="$shim_dir/:$shim_dir:$stubdir:$sandbox/link/plugin-dev/bin"
path_head+=":$consumer/plugin-dev/./bin"
run_claude
assert_file "$sandbox/rec/path" \
    "the shim strips its own entry in any spelling: the stub ran"
left=0 stubs=0
if [[ -f "$sandbox/rec/path" ]]; then
    IFS=: read -r -a entries < "$sandbox/rec/path" || true
    for entry in "${entries[@]}"; do
        [[ -n "$entry" && "$entry/claude" -ef "$shim_dir/claude" ]] && left=$((left + 1))
        [[ -n "$entry" && "$entry/claude" -ef "$stubdir/claude" ]] && stubs=$((stubs + 1))
    done
fi
assert_eq "$stubs" "1" \
    "the shim strips its own entry in any spelling: the recorded PATH splits to the stub's entry"
assert_eq "$left" "0" \
    "the shim strips its own entry in any spelling: entries of the shim left on PATH"

echo "=== the shim keeps another bin/claude ==="
make_consumer
mkdir -p "$sandbox/other tools/bin"
cat > "$sandbox/other tools/bin/claude" <<OTHER
#!/usr/bin/env bash
printf ran > "$sandbox/rec/other"
exit 0
OTHER
chmod +x "$sandbox/other tools/bin/claude"
path_head="$shim_dir:$sandbox/other tools/bin:$stubdir"
run_claude
assert_eq "$(recorded other)" "ran" \
    "the shim keeps another bin/claude: the one ahead of the stub ran"
assert_absent "$sandbox/rec/argv" \
    "the shim keeps another bin/claude: the stub behind it did not"

# A leading empty entry is the working directory: dropping it would change
# which claude a later lookup finds.
echo "=== the shim keeps the rest of PATH as spelled ==="
make_consumer
path_head=":$shim_dir:$stubdir"
run_claude
# shellcheck disable=SC2031  # the suite's own PATH, which the launch appended
assert_eq "$(recorded path)" ":$stubdir:$PATH" \
    "the shim keeps the rest of PATH as spelled"

echo "=== a subdirectory launch resolves the root ==="
make_consumer
launch_dir="$consumer/skills/demo"
run_claude
assert_eq "$(recorded plugin_dirs)" "$consumer/dist/plugin" \
    "a subdirectory launch resolves the root: the copy"
assert_eq "$(recorded pwd)" "$consumer/skills/demo" \
    "a subdirectory launch resolves the root: the shim did not change directory"

# From the shim's own directory a leading empty entry is the shim: the one case
# where dropping an empty entry is required, else the exec finds the shim again.
# The launch appends only the runner's absolute entries: an empty or relative
# one would name plugin-dev/bin too, and the shim rightly drops it as well.
echo "=== a launch from plugin-dev/bin drops the empty entry ==="
make_consumer
launch_dir="$consumer/plugin-dev/bin"
path_head=":$shim_dir:$stubdir"
# shellcheck disable=SC2031  # the suite's own PATH, not run_claude's subshell's
runner_path="" rest="$PATH:"
while [[ -n "$rest" ]]; do
    entry="${rest%%:*}"
    rest="${rest#*:}"
    [[ "$entry" == /* ]] && runner_path+="${runner_path:+:}$entry"
done
PATH="$runner_path" run_claude
assert_file "$sandbox/rec/path" \
    "a launch from plugin-dev/bin drops the empty entry: the stub ran"
assert_eq "$(recorded path)" "$stubdir:$runner_path" \
    "a launch from plugin-dev/bin drops the empty entry"

echo "=== a failed sync aborts the launch ==="
make_consumer
rm "$consumer/.claude-plugin/plugin.json"
run_claude
assert_eq "$rc" "1" "a failed sync aborts the launch: the shim exits with sync's status"
# Sync's own refusal line, root included, reaching the terminal unredirected.
if ! grep -qF "dogfood: $consumer/.claude-plugin/plugin.json" "$sandbox/stderr"; then
    fail "a failed sync aborts the launch: stderr does not carry sync's refusal: $(cat "$sandbox/stderr")"
fi
# The shim's own line, once, beside sync's: the terminal learns claude was not
# started, not only that a sync refused. claude must stand as a word: sync's
# line names the root, and both .claude-plugin and a $TMPDIR such as
# /tmp/claude-1000 spell it inside a path.
not_started_re="^dogfood: (.*[[:space:]\`'])?claude[[:space:]\`'].*not started"
shim_lines="$(grep -cE "$not_started_re" "$sandbox/stderr" || true)"
assert_eq "$shim_lines" "1" \
    "a failed sync aborts the launch: one dogfood: line says claude was not started"
assert_eq "$(cat "$sandbox/stdout")" "" "a failed sync aborts the launch: stdout is empty"
assert_absent "$sandbox/rec/argv" "a failed sync aborts the launch: the next claude did not run"
assert_absent "$sandbox/rec/pid" "a failed sync aborts the launch: the stub left no record"

# Sync exits with rsync's status, and the shim with sync's: an rsync failing 23
# tells a status passed through from a fixed exit 1, which the refusal above
# cannot.
echo "=== a failed rsync keeps its status ==="
make_consumer
mkdir "$sandbox/failing rsync"
cat > "$sandbox/failing rsync/rsync" <<'RSYNC'
#!/usr/bin/env bash
printf 'rsync: stub failure (code 23)\n' >&2
exit 23
RSYNC
chmod +x "$sandbox/failing rsync/rsync"
path_head="$shim_dir:$sandbox/failing rsync:$stubdir"
run_claude
assert_eq "$rc" "23" "a failed rsync keeps its status: the shim exits with rsync's status"
if ! grep -qxF 'rsync: stub failure (code 23)' "$sandbox/stderr"; then
    fail "a failed rsync keeps its status: stderr does not carry rsync's line: $(cat "$sandbox/stderr")"
fi
assert_eq "$(grep -cE "$not_started_re" "$sandbox/stderr" || true)" "1" \
    "a failed rsync keeps its status: one dogfood: line says claude was not started"
assert_absent "$sandbox/rec/argv" "a failed rsync keeps its status: the next claude did not run"

# The whole PATH is the shim's directory and a directory of symlinks to the
# commands the shim and sync run: no claude, and nothing inherited that could
# hold one. The negative only means something if a lookup under this PATH finds
# the shim, and one under what the shim leaves of it finds nothing. Bash's own
# exec failure also exits 127, and so does a sync missing a command, so stderr
# must be the shim's one line and nothing else.
echo "=== no next claude exits 127 ==="
make_consumer
mkdir "$sandbox/tools"
for tool in bash dirname git rsync mktemp rm mkdir; do
    ln -s "$(command -v "$tool")" "$sandbox/tools/$tool"
done
path_exact="$shim_dir:$sandbox/tools"
found="$(PATH="$path_exact" command -v claude || true)"
assert_eq "$found" "$shim_dir/claude" \
    "no next claude exits 127: the shim is the claude on the PATH"
found="$(PATH="$sandbox/tools" command -v claude || true)"
assert_eq "$found" "" \
    "no next claude exits 127: the PATH without the shim holds no claude"
run_claude
assert_eq "$rc" "127" "no next claude exits 127"
assert_eq "$(cat "$sandbox/stderr")" "dogfood: no other claude on PATH" \
    "no next claude exits 127: stderr is the shim's one line"
assert_file "$consumer/dist/plugin/.claude-plugin/plugin.json" \
    "no next claude exits 127: the sync ran, so the 127 is not a sync failure"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood launcher scenarios passed\n'

#!/usr/bin/env bash
# End-to-end test of toolkit/dogfood.sh pre-tool against real git repos in a
# temp dir: the PreToolUse hook that denies an edit into the synced copy. Each
# scenario builds a consumer fixture and runs the script as a consumer would,
# from its vendored spot at plugin-dev/dogfood.sh.
#
# Scope: which paths the hook denies and allows -- the copy, a source edit, a path
# outside the copy, symlinked repos, .. segments, odd names. Its sibling
# dogfood-pre-tool-jq-test.sh covers a missing or failing jq and leaf symlinks.
#
# Usage: bash tests/dogfood-pre-tool-paths-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/dogfood-pre-tool-paths.XXXXXX")" || exit 1
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

# run_pre_tool <tool> <field> <path>: run_dogfood pre-tool, fed
# pre_tool_payload <tool> <field> <path> on stdin.
run_pre_tool() {
    run_dogfood pre-tool <<<"$(pre_tool_payload "$@")"
}

# pre_tool_payload <tool> <field> <path>: a payload for <tool> that names <path>
# under .tool_input.<field>. It is built with jq so a spaced path survives, and
# carries a cwd that is a real directory but not the consumer: a root taken from
# the payload's cwd would judge every path against the decoy and give the wrong
# verdict.
pre_tool_payload() {
    jq -cn --arg t "$1" --arg f "$2" --arg p "$3" --arg cwd "$sandbox/elsewhere" \
        '{tool_name:$t,cwd:$cwd,tool_input:{($f):$p}}'
}

# make_jqless_bin <dir>: <dir> holds symlinks to the commands the script and
# run_dogfood invoke, jq left out. A PATH of <dir> alone reaches those and not
# jq; the caller asserts `command -v jq` fails under it.
make_jqless_bin() {
    local c
    mkdir -p "$1"
    for c in bash dirname mkdir cat; do
        ln -s "$(command -v "$c")" "$1/$c"
    done
}

# jq_holds <label> <filter> [jq options...]: fail unless <filter> is true over
# $out. Checked in jq rather than on `jq -r` text: its contains() is literal
# where assert_contains' needle is a BRE, a non-string field cannot pass as its
# printed JSON, and a trailing newline in a value is not lost to $(...).
jq_holds() {
    local label="$1" filter="$2"
    shift 2
    if ! printf '%s' "$out" | jq -e "$@" "$filter" >/dev/null; then
        fail "$label: $filter is not true over stdout '$out'"
    fi
}

# assert_denied <label> <root>: the last pre-tool run denied an edit into
# <root>/dist/plugin/skills/demo/SKILL.md, naming that path and its source.
assert_denied() {
    local label="$1" root="$2"
    assert_denied_source "$label" "$root"
    # shellcheck disable=SC2016  # $p is a jq variable bound by --arg
    jq_holds "$label: reason names the denied path" \
        '.hookSpecificOutput.permissionDecisionReason | type == "string" and contains($p)' \
        --arg p "$root/dist/plugin/skills/demo/SKILL.md"
}

# assert_denied_source <label> <root>: the last pre-tool run denied, naming the
# source path <root>/skills/demo/SKILL.md. The reason is not checked for a path:
# the payload may reach the copy without spelling it.
assert_denied_source() {
    local label="$1" root="$2"
    assert_eq "$rc" "0" "$label exit code"
    assert_eq "$err" "" "$label prints nothing on stderr"
    # Slurped, so a second value or trailing garbage after the object fails here:
    # a per-field jq reads the first object and errors only after it.
    jq_holds "$label: stdout is one JSON object" 'length == 1 and (.[0] | type) == "object"' -s
    jq_holds "$label: hookEventName" '.hookSpecificOutput.hookEventName == "PreToolUse"'
    jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
    # shellcheck disable=SC2016  # $p is a jq variable bound by --arg
    jq_holds "$label: additionalContext names the source path" \
        '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
        --arg p "$root/skills/demo/SKILL.md"
    jq_holds "$label: systemMessage names the copy" \
        '.systemMessage | type == "string" and contains("dist/plugin")'
    jq_holds "$label: systemMessage is one line" \
        '.systemMessage | type == "string" and (test("[\r\n]") | not)'
}

echo "=== pre-tool denies an Edit into the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
run_pre_tool Edit file_path "$root/dist/plugin/skills/demo/SKILL.md"
assert_denied "pre-tool denies an Edit into the copy" "$root"

echo "=== pre-tool denies a NotebookEdit into the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
run_pre_tool NotebookEdit notebook_path "$root/dist/plugin/skills/demo/SKILL.md"
assert_denied "pre-tool denies a NotebookEdit into the copy" "$root"

echo "=== pre-tool allows a source edit ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
run_pre_tool Edit file_path "$root/skills/demo/SKILL.md"
assert_eq "$rc" "0" "pre-tool allows a source edit exit code"
assert_eq "$out" "" "pre-tool allows a source edit prints nothing on stdout"
assert_eq "$err" "" "pre-tool allows a source edit prints nothing on stderr"

# The outside path holds /dist/plugin/ itself, so only an anchored prefix
# match, not a substring one, lets it through. It also lies under
# run_dogfood's CLAUDE_PROJECT_DIR, so a root taken from there denies it.
echo "=== pre-tool allows a path outside the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
for pair in \
    "a path outside the repo:$sandbox/elsewhere/dist/plugin/x" \
    "a sibling of the copy:$root/dist/other" \
    "a prefix-sharing sibling:$root/dist/plugin-old/x"; do
    run_pre_tool Edit file_path "${pair#*:}"
    assert_eq "$rc" "0" "pre-tool allows ${pair%%:*} exit code"
    assert_eq "$out" "" "pre-tool allows ${pair%%:*} prints nothing on stdout"
    assert_eq "$err" "" "pre-tool allows ${pair%%:*} prints nothing on stderr"
done

# new/ does not exist under the copy, so the physical comparison has to resolve
# the nearest existing ancestor (dist/plugin) and re-append the rest.
echo "=== pre-tool denies a copy path through a symlinked repo ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$consumer" "$sandbox/link"
label="pre-tool denies a copy path through a symlinked repo"
assert_absent "$consumer/dist/plugin/new" "$label: new/ is not in the copy"
run_pre_tool Edit file_path "$sandbox/link/dist/plugin/new/file.md"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "$label: additionalContext names the physical source path" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
    --arg p "$root/new/file.md"

# The payload spells no /dist/plugin/ at all: only resolving the path's own
# nearest existing ancestor finds the copy. Splitting the text at /dist/plugin/
# and resolving the part before it passes the test above and allows this one.
echo "=== pre-tool denies a copy path through a symlink to the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$consumer/dist/plugin" "$sandbox/copy-link"
run_pre_tool Edit file_path "$sandbox/copy-link/new/file.md"
label="pre-tool denies a copy path through a symlink to the copy"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "$label: additionalContext names the physical source path" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
    --arg p "$root/new/file.md"

# nope/ and new/ do not exist, so the kernel cannot resolve the .. after them;
# the edit lands where the .. leads. Keeping the missing tail as spelled leaves
# the .. in the compared path: it allows the first path, into the copy, and
# denies the second, a source path spelled through the copy.
echo "=== pre-tool follows .. past a directory not yet created ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="pre-tool follows .. into the copy"
assert_absent "$consumer/skills/nope" "$label: nope/ is not in the source"
run_pre_tool Edit file_path "$root/skills/nope/../../dist/plugin/skills/demo/SKILL.md"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "$label: additionalContext names the physical source path" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
    --arg p "$root/skills/demo/SKILL.md"
label="pre-tool follows .. out of the copy"
assert_absent "$consumer/dist/plugin/new" "$label: new/ is not in the copy"
run_pre_tool Edit file_path "$root/dist/plugin/new/../../../skills/demo/SKILL.md"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

# A $(...) capture strips a name's trailing newline: a dirname taken through one
# turns lnk<newline>, a link to the copy, into lnk, a directory outside it. The
# source path keeps the leaf's own trailing newline, pinned by the full stop
# the message puts after it. The link named - pins that a relative cd onto it
# does not read as cd -.
echo "=== pre-tool keeps a trailing newline and a bare - in a name ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
nl=$'\n'
mkdir "$sandbox/lnk"
ln -s "$consumer/dist/plugin" "$sandbox/lnk$nl"
label="pre-tool keeps a trailing newline"
run_pre_tool Edit file_path "$sandbox/lnk$nl/new/file.md$nl"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "$label: additionalContext names the source path, newline kept" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p + ".")' \
    --arg p "$root/new/file.md$nl"
ln -s "$consumer/dist/plugin" "$sandbox/-"
label="pre-tool follows a link named -"
run_pre_tool Edit file_path "$sandbox/-/new/file.md"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "$label: additionalContext names the physical source path" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
    --arg p "$root/new/file.md"

echo "=== pre-tool invoked through the symlink denies a physical path ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$consumer" "$sandbox/link"
consumer="$sandbox/link"
run_pre_tool Edit file_path "$root/dist/plugin/skills/demo/SKILL.md"
assert_denied "pre-tool invoked through the symlink denies a physical path" "$root"

# A $(...) capture of the root strips the newline, and the copy path no longer
# falls under the root it names. $sandbox is physical, so $consumer is too.
echo "=== pre-tool denies an edit into the copy of a root ending in a newline ==="
make_consumer
mv "$consumer" "$consumer"$'\n'
consumer+=$'\n'
run_dogfood sync
run_pre_tool Edit file_path "$consumer/dist/plugin/skills/demo/SKILL.md"
assert_denied "pre-tool denies an edit into the copy of a root ending in a newline" "$consumer"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood pre-tool path scenarios passed\n'

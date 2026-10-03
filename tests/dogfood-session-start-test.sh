#!/usr/bin/env bash
# End-to-end test of toolkit/dogfood.sh session-start against real git repos in
# a temp dir: the SessionStart hook that warns when the session did not load the
# synced copy. Each scenario builds a consumer fixture and runs the script as a
# consumer would, from its vendored spot at plugin-dev/dogfood.sh.
#
# Usage: bash tests/dogfood-session-start-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo via `-C`, never this
# repo, so it's always safe to drop them here.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below
# A parent Claude Code session exports this. The session-start tests set it per
# run or rely on its absence, whichever session launched the suite.
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

# run_session_start: run_dogfood session-start, fed a SessionStart payload whose
# cwd is not the consumer, as a resumed session's can be. A script taking its
# root from the payload, even as a fallback, would name the wrong copy.
run_session_start() {
    run_dogfood session-start <<<"$(jq -cn --arg cwd "$sandbox/elsewhere" \
        '{session_id:"fixture",hook_event_name:"SessionStart",source:"resume",cwd:$cwd}')"
}

# assert_session_warns <label> <root>: the last run_session_start printed one
# object, the warning on both channels, each naming <root>/dist/plugin.
assert_session_warns() {
    local label="$1" copy="$2/dist/plugin"
    assert_eq "$rc" "0" "$label exit code"
    assert_eq "$err" "" "$label prints nothing on stderr"
    jq_holds "$label: stdout is one JSON object" 'length == 1 and (.[0] | type) == "object"' -s
    # shellcheck disable=SC2016  # $p is a jq variable bound by --arg
    jq_holds "$label: systemMessage leads with an ANSI reset and names the copy" \
        '.systemMessage | type == "string" and startswith("\u001b[0m") and contains($p)' \
        --arg p "$copy"
    jq_holds "$label: hookEventName" '.hookSpecificOutput.hookEventName == "SessionStart"'
    # shellcheck disable=SC2016  # $p is a jq variable bound by --arg
    jq_holds "$label: additionalContext names the copy" \
        '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
        --arg p "$copy"
}

# CLAUDE_CODE_PLUGIN_DIRS is unset by the preamble; a test wanting it passes it
# as a prefix. The warn test below is this one's positive: the same fixture,
# differing only in the variable.
echo "=== session-start is silent on the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start is silent on the copy"
CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

echo "=== session-start warns when the variable is unset ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start warns when the variable is unset"
run_session_start
assert_session_warns "$label" "$root"

# Each spelling below names the copy, so each is silent; the variable, and for
# the last a link to the root, is all that differs from the warn test above.
# The copy sits between two entries, so neither the first nor the last entry
# alone, nor a suffix of the whole value, can stand in for splitting on ':'.
# The link spelling is set while the script is invoked at the physical path, so
# only an entry resolved to its physical spelling matches the root.
echo "=== session-start matches the copy among several entries ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start is silent on one entry of several"
CLAUDE_CODE_PLUGIN_DIRS="/x/other:$root/dist/plugin:/y/other" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

echo "=== session-start matches the copy with a trailing slash ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start is silent on a trailing slash"
CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin/" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

echo "=== session-start matches the copy through a symlink ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$root" "$sandbox/link"
label="session-start is silent on a symlinked spelling"
CLAUDE_CODE_PLUGIN_DIRS="$sandbox/link/dist/plugin" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

# The other direction of the link: the script is invoked through a symlinked
# spelling of the repo, as a hook command's path can be, while the variable
# carries the physical copy. A root resolved logically, from the invocation
# spelling, names $sandbox/link/dist/plugin and misses it. $consumer is pointed
# at the link, the spelling run_dogfood invokes the script through.
echo "=== session-start invoked through a symlinked repo matches the physical copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$root" "$sandbox/link"
consumer="$sandbox/link"
label="session-start invoked through a symlinked repo is silent on the physical copy"
CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

# A $(...) capture of the root strips the newline, so the copy it names is not
# the entry's. $sandbox is physical, so $consumer is too.
echo "=== session-start matches the copy of a root ending in a newline ==="
make_consumer
mv "$consumer" "$consumer"$'\n'
consumer+=$'\n'
run_dogfood sync
label="session-start is silent on the copy of a root ending in a newline"
CLAUDE_CODE_PLUGIN_DIRS="$consumer/dist/plugin" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

# The link resolves to a sibling of the copy whose name is the copy's plus a
# newline, so a resolution read through a $(...) capture loses the newline and
# names the copy.
echo "=== session-start keeps a resolved entry's trailing newline ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
mkdir "$root/dist/plugin"$'\n'
ln -s "$root/dist/plugin"$'\n' "$sandbox/nl"
label="session-start warns on an entry resolving to plugin<LF>"
CLAUDE_CODE_PLUGIN_DIRS="$sandbox/nl" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: stdout is the warning" '.hookSpecificOutput.hookEventName == "SessionStart"'

# Claude Code drops a relative entry, so it loads nothing; run_dogfood runs from
# $sandbox, where this spelling would resolve to the copy.
echo "=== session-start does not resolve a relative entry ==="
make_consumer
run_dogfood sync
label="session-start warns on a relative entry"
CLAUDE_CODE_PLUGIN_DIRS="my consumer/dist/plugin" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: stdout is the warning" '.hookSpecificOutput.hookEventName == "SessionStart"'

# A directory that cannot be entered does not resolve; its neighbour still
# names the copy. Running as root, the mode blocks nothing and this cannot red.
echo "=== session-start passes over a directory it cannot enter ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
mkdir "$sandbox/sealed"
chmod 000 "$sandbox/sealed"
label="session-start is silent past a sealed directory"
CLAUDE_CODE_PLUGIN_DIRS="$sandbox/sealed:$root/dist/plugin" run_session_start
chmod 755 "$sandbox/sealed"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

# Each entry below names something other than the copy, so each warns. The
# other repo's copy is real and synced, so an entry that merely is an existing
# plugin directory, or ends in /dist/plugin, does not match; the /x entry does
# not exist, so it is compared literally and a substring does not match; the
# skills entry is a real directory inside the copy, so a prefix does not match.
echo "=== session-start warns on another repo's real copy ==="
make_consumer
run_dogfood sync
other_root="$(cd "$consumer" && pwd -P)"
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
[[ -d "$other_root/dist/plugin" ]] || fail "fixture: the other repo's copy does not exist"
label="session-start warns on another repo's copy"
CLAUDE_CODE_PLUGIN_DIRS="$other_root/dist/plugin" run_session_start
assert_session_warns "$label" "$root"

echo "=== session-start warns on a longer, non-existent entry ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start warns on /x<root>/dist/plugin"
CLAUDE_CODE_PLUGIN_DIRS="/x$root/dist/plugin" run_session_start
assert_session_warns "$label" "$root"

echo "=== session-start warns on a longer, real entry ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
[[ -d "$root/dist/plugin/skills" ]] || fail "fixture: the copy has no skills directory"
label="session-start warns on <root>/dist/plugin/skills"
CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin/skills" run_session_start
assert_session_warns "$label" "$root"

# The payload is built with the real jq before the PATH narrows, and stdout is
# read with the suite's own jq after the run. The message is static, and only a
# user can install jq, so it stays off hookSpecificOutput. The copy check needs
# jq's absence to be skipped, not merely survived: the second run names the copy
# in the variable, where the check would be silent, and still gets the message.
# Their jq-present controls are `session-start is silent on the copy` and
# `session-start warns when the variable is unset` above: the same fixture and
# payload, differing only in the PATH. The sandbox path is random and may hold
# "jq", so it is cut out of the message before the message is searched for jq.
echo "=== session-start reports a missing jq on systemMessage only ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
make_jqless_bin "$sandbox/nojq"
label="session-start reports a missing jq on systemMessage only"
if PATH="$sandbox/nojq" command -v jq >/dev/null; then
    fail "$label: jq is still reachable on the jq-less PATH"
fi
payload="$(jq -cn --arg cwd "$sandbox/elsewhere" \
    '{session_id:"fixture",hook_event_name:"SessionStart",source:"resume",cwd:$cwd}')"
for spelling in unset names-the-copy; do
    if [[ "$spelling" == unset ]]; then
        PATH="$sandbox/nojq" run_dogfood session-start <<<"$payload"
    else
        CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin" PATH="$sandbox/nojq" \
            run_dogfood session-start <<<"$payload"
    fi
    assert_eq "$rc" "0" "$label ($spelling) exit code"
    assert_eq "$err" "" "$label ($spelling) prints nothing on stderr"
    jq_holds "$label ($spelling): stdout is one JSON object" 'length == 1 and (.[0] | type) == "object"' -s
    jq_holds "$label ($spelling): systemMessage opens with an ANSI reset" \
        '(.systemMessage | type) == "string" and (.systemMessage | startswith("\u001b[0m"))'
    # shellcheck disable=SC2016  # $s is a jq variable bound by --arg
    jq_holds "$label ($spelling): systemMessage names jq" \
        '(.systemMessage | type) == "string" and (.systemMessage | split($s) | join("") | contains("jq"))' \
        --arg s "$sandbox"
    jq_holds "$label ($spelling): hookSpecificOutput is absent" 'has("hookSpecificOutput") | not'
done

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood session-start scenarios passed\n'

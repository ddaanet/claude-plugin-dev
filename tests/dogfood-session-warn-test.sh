#!/usr/bin/env bash
# End-to-end test of toolkit/dogfood.sh session-start against real git repos in
# a temp dir: what the SessionStart hook says, and to whom, when the session did
# not load the synced copy or the copy is not there. Each scenario builds a
# consumer fixture and runs the script as a consumer would, from its vendored
# spot at plugin-dev/dogfood.sh. Its sibling dogfood-session-start-test.sh
# covers when the hook stays silent and the jq-less message.
#
# Usage: bash tests/dogfood-session-warn-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/dogfood-session-warn.XXXXXX")" || exit 1
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

# The three messages, pinned whole. None names the shim: the user's control is
# direnv allow, which loads the .envrc that puts the shim first on PATH.
echo "=== session-start warns when the variable is unset ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start warns when the variable is unset"
run_session_start
assert_session_warns "$label" "$root"
# shellcheck disable=SC2016  # $c and $r are jq variables bound by --arg
jq_holds "$label: systemMessage is the direnv allow line" \
    '.systemMessage == "\u001b[0mdogfood: this session does not load " + $c + "; run direnv allow in " + $r + ", then relaunch claude from a shell there"' \
    --arg c "$root/dist/plugin" --arg r "$root"
# shellcheck disable=SC2016  # $c is a jq variable bound by --arg
jq_holds "$label: additionalContext is the not-the-promoted-copy fact" \
    '.hookSpecificOutput.additionalContext == "This session does not load " + $c + ", so plugin behaviour observed in it is not that of the promoted copy."' \
    --arg c "$root/dist/plugin"
jq_holds "$label: systemMessage does not name the shim" \
    '.systemMessage | contains("bin/claude") | not'

# A session past the shim with no copy: the remedy is the promotion, then
# direnv allow and a relaunch. The agent gets the fact and no command: the
# promotion is the human's act. A file where the copy belongs is no copy either.
# Their copy-present control is the test above.
for shape in absent file; do
    echo "=== session-start names the promotion when the copy is $shape ==="
    make_consumer
    root="$(cd "$consumer" && pwd -P)"
    if [[ "$shape" == file ]]; then
        mkdir "$root/dist"
        printf 'not a copy\n' > "$root/dist/plugin"
    fi
    label="session-start with the copy $shape"
    run_session_start
    assert_session_warns "$label" "$root"
    # shellcheck disable=SC2016  # $c and $r are jq variables bound by --arg
    jq_holds "$label: systemMessage is the just dogfood, direnv allow line" \
        '.systemMessage == "\u001b[0mdogfood: no copy at " + $c + ", so this session does not load it; run just dogfood to create it, then direnv allow in " + $r + " and relaunch claude from a shell there"' \
        --arg c "$root/dist/plugin" --arg r "$root"
    jq_holds "$label: systemMessage does not name the shim" \
        '.systemMessage | contains("bin/claude") | not'
    jq_holds "$label: additionalContext states no copy exists" \
        '.hookSpecificOutput.additionalContext | ascii_downcase | contains("no copy exists")'
    for word in "just dogfood" sync promote direnv; do
        # shellcheck disable=SC2016  # $w is a jq variable bound by --arg
        jq_holds "$label: additionalContext does not name '$word'" \
            '.hookSpecificOutput.additionalContext | ascii_downcase | contains($w) | not' \
            --arg w "$word"
    done
done

# A shim launch before the first just dogfood: the variable names the path, so
# the session loads it once the directory exists, and /reload-plugins is enough.
# The check is the variable plus a directory at the path, so a file there warns
# as well. Their control is the silent test on the synced copy in
# dogfood-session-start-test.sh.
for shape in absent file; do
    echo "=== session-start names /reload-plugins when the copy is $shape and named ==="
    make_consumer
    root="$(cd "$consumer" && pwd -P)"
    if [[ "$shape" == file ]]; then
        mkdir "$root/dist"
        printf 'not a copy\n' > "$root/dist/plugin"
    elif [[ -e "$root/dist" ]]; then
        fail "the fixture already has a dist/"
    fi
    label="session-start with the copy $shape and named"
    CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin" run_session_start
    assert_session_warns "$label" "$root"
    # shellcheck disable=SC2016  # $c is a jq variable bound by --arg
    jq_holds "$label: systemMessage is the just dogfood, /reload-plugins line" \
        '.systemMessage == "\u001b[0mdogfood: no copy at " + $c + " yet; run just dogfood to create it, then /reload-plugins, no relaunch needed"' \
        --arg c "$root/dist/plugin"
    jq_holds "$label: systemMessage does not name direnv or the shim" \
        '.systemMessage | (contains("direnv") or contains("bin/claude")) | not'
    jq_holds "$label: additionalContext states no copy exists" \
        '.hookSpecificOutput.additionalContext | ascii_downcase | contains("no copy exists")'
    for word in "just dogfood" sync promote reload direnv; do
        # shellcheck disable=SC2016  # $w is a jq variable bound by --arg
        jq_holds "$label: additionalContext does not name '$word'" \
            '.hookSpecificOutput.additionalContext | ascii_downcase | contains($w) | not' \
            --arg w "$word"
    done
done

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

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood session-warn scenarios passed\n'

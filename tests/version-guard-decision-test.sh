#!/usr/bin/env bash
# End-to-end test of toolkit/version-guard.sh against synthetic tool-event
# payloads. Each scenario is a real invocation of the hook with a
# hand-crafted JSON input; assertions exit non-zero on failure.
#
# One script under test per file: the toolkit's other consumer-side script,
# check-version.sh, is covered by tests/check-version-test.sh, which shares
# nothing with this one but the six-line assertion harness every suite here
# carries its own copy of.
#
# Scope: the deny/allow decision against a plain (non-repo) manifest -- Edit and
# Write of .version, unrelated fields and files, a drifted payload cwd, a
# relative path, BSD realpath. Its siblings version-guard-wording-test.sh and
# version-guard-git-test.sh cover the refusal wording and the tag-listing
# paths.
#
# Usage: bash tests/version-guard-decision-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. The new
# git-repo fixture below runs real git commands of its own, and a leaked
# GIT_DIR would redirect them at this repo instead. See
# `tests/release-core-test.sh`'s own header comment, just above its own
# `unset $(git rev-parse --local-env-vars)` line, for the same explanation.
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
    # $1=haystack $2=needle $3=label. Match against a specific extracted
    # field (e.g. permissionDecisionReason alone), never the whole payload
    # blob -- an unrelated line can satisfy a needle and hide the miss.
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
assert_not_contains() {
    # $1=haystack $2=needle $3=label
    # Residual bound: the needle is a grep BRE matched line by line --
    # a metacharacter in it is live, and a needle that spans a newline
    # can never match.
    # A here-string, never a pipe: under pipefail grep -q exits on its first
    # match, the writer can take SIGPIPE, and the pipeline reports failure.
    if grep -q -- "$2" <<<"$1"; then
        fail "$3: output contained '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}

# version-guard scenarios use a fake plugin root with a hand-crafted
# .claude-plugin/plugin.json fixture, so assertions are independent of
# whatever consumer plugin happens to vendor this toolkit.
proj="$(mktemp -d)"
guard_err="$(mktemp)"
trap 'rm -rf "$proj" "$guard_err"' EXIT
mkdir -p "$proj/.claude-plugin"
cat > "$proj/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.2.3",
  "license": "MIT"
}
JSON

# The hook reads CLAUDE_PROJECT_DIR, so every scenario passes it explicitly;
# the payload `cwd` a scenario sets is deliberately not what locates the
# manifest. guard_path exists so one scenario can prepend a PATH stub.
guard_path="$PATH"
run_guard() {
    # $1 = payload JSON. $2 = project dir (default $proj, the non-repo
    # fixture) -- pass $git_proj for the tagless-repo scenarios. $3... =
    # extra "NAME=value" assignments for the hook's environment; the
    # leaked-GIT_DIR scenario below is the one caller that passes any.
    # Captures stdout ONLY -- stderr is diverted to a file rather than
    # folded in with 2>&1, so an assertion below can only pass if the hook
    # JSON really is on stdout, where Claude Code parses it.
    # Both array forms below are the bash-3.2-safe ones: under `set -u`,
    # bash before 4.4 (macOS ships 3.2) errors on expanding an empty array,
    # and all but that one call site passes no $3.
    local payload="$1"
    local project="${2:-$proj}"
    local extra_env=()
    if [[ $# -gt 2 ]]; then extra_env=("${@:3}"); fi
    set +e
    guard_out="$(printf '%s' "$payload" \
        | env CLAUDE_PROJECT_DIR="$project" PATH="$guard_path" ${extra_env[@]+"${extra_env[@]}"} \
              bash toolkit/version-guard.sh 2>"$guard_err")"
    guard_rc=$?
    set -e
}
assert_deny() {
    # $1 = label. A deny is stdout JSON + exit 0: `permissionDecision: "deny"`
    # blocks the call the same as exit 2 and additionally carries systemMessage,
    # which exit 2 discards.
    assert_eq "$guard_rc" "0" "$1 exit code"
    grep -q '"permissionDecision":"deny"' <<<"$guard_out" \
        || fail "$1: no deny decision on stdout"
    grep -q '"permissionDecisionReason"' <<<"$guard_out" \
        || fail "$1: no permissionDecisionReason on stdout"
    grep -q '"systemMessage"' <<<"$guard_out" \
        || fail "$1: no systemMessage on stdout"
    if [[ -s "$guard_err" ]]; then
        fail "$1: wrote to stderr: $(cat "$guard_err")"
    fi
}
assert_allow() {
    # $1 = label. An allow is silence: no JSON at all, exit 0.
    assert_eq "$guard_rc" "0" "$1 exit code"
    if [[ -n "$guard_out" ]]; then
        fail "$1: expected no output, got '$guard_out'"
    fi
}

# version-guard denies an Edit that changes .version.
echo "=== version-guard (Edit version change: deny) ==="
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"\"version\": \"1.2.3\"", new_string:"\"version\": \"1.3.0\""}}')"
assert_deny "version-guard Edit-bump"

# The shortest edit that bumps the version replaces the value alone and
# repeats no "version" key, so a guard that pattern-matches new_string for
# one lets it straight through.
echo "=== version-guard (Edit bare version value: deny) ==="
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')"
assert_deny "version-guard Edit-bare-value"

# version-guard allows an Edit that touches plugin.json without changing version.
echo "=== version-guard (Edit unrelated field: allow) ==="
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"\"license\": \"MIT\"", new_string:"\"license\": \"Apache-2.0\""}}')"
assert_allow "version-guard Edit-unrelated"

# version-guard denies a Write whose content changes .version.
echo "=== version-guard (Write version change: deny) ==="
new_content="$(jq -c '.version="9.9.9"' "$proj/.claude-plugin/plugin.json")"
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/.claude-plugin/plugin.json" --arg c "$new_content" \
    '{cwd:$cwd, tool_name:"Write", tool_input:{file_path:$fp, content:$c}}')"
assert_deny "version-guard Write-bump"

# version-guard ignores Edits to unrelated files.
echo "=== version-guard (unrelated file: allow) ==="
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/README.md" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"a", new_string:"b"}}')"
assert_allow "version-guard unrelated-file"

# The payload `cwd` tracks the Bash tool's shell and drifts with `cd` or
# /add-dir. Locating the manifest from it disables the guard silently, so
# the drifted value must not change the verdict.
echo "=== version-guard (drifted payload cwd: deny) ==="
mkdir -p "$proj/sub/dir"
run_guard "$(jq -nc --arg cwd "$proj/sub/dir" --arg fp "$proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')"
assert_deny "version-guard drifted-cwd"

# tool_input.file_path is whatever the model emitted, and it is not always
# absolute -- a repo-root-relative form must still be recognised.
echo "=== version-guard (relative file_path: deny) ==="
run_guard "$(jq -nc --arg cwd "$proj" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:".claude-plugin/plugin.json", old_string:"1.2.3", new_string:"9.9.9"}}')"
assert_deny "version-guard relative-path"

# BSD/macOS realpath has no -m. A guard built on it gets two empty strings,
# compares them equal, and fires on files that are not the manifest. The
# stub makes Linux CI reproduce that, so the fix stays fixed.
echo "=== version-guard (BSD realpath, unrelated file: allow) ==="
stubdir="$proj/stubbin"
mkdir -p "$stubdir"
real_realpath="$(command -v realpath || true)"
# Unquoted heredoc: $real_realpath is baked in now, \$@ is left for run time.
cat > "$stubdir/realpath" <<EOF
#!/bin/sh
for a in "\$@"; do
    case "\$a" in -m) echo 'realpath: illegal option -- m' >&2; exit 1 ;; esac
done
exec ${real_realpath:-/bin/false} "\$@"
EOF
chmod 755 "$stubdir/realpath"
other_content="$(jq -nc '{name:"other", version:"9.9.9"}')"
guard_path="$stubdir:$PATH"
run_guard "$(jq -nc --arg cwd "$proj" --arg fp "$proj/other.json" --arg c "$other_content" \
    '{cwd:$cwd, tool_name:"Write", tool_input:{file_path:$fp, content:$c}}')"
guard_path="$PATH"
assert_allow "version-guard bsd-realpath-unrelated"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall version-guard decision scenarios passed\n'

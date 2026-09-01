#!/usr/bin/env bash
# End-to-end test of the toolkit's hook scripts against synthetic
# tool-event payloads. Each scenario is a real invocation of the hook
# with a hand-crafted JSON input; assertions exit non-zero on failure.
#
# Usage: bash tests/hook-test.sh   (run from repo root)
set -euo pipefail

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
    # $1 = payload JSON. Captures stdout ONLY -- stderr is diverted to a file
    # rather than folded in with 2>&1, so an assertion below can only pass if
    # the hook JSON really is on stdout, where Claude Code parses it.
    set +e
    guard_out="$(printf '%s' "$1" \
        | env CLAUDE_PROJECT_DIR="$proj" PATH="$guard_path" \
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

market="$proj/marketplace.json"

# check-version skips non-fatally when MARKETPLACE_DIR is unset and no
# explicit marketplace path is given.
echo "=== check-version (MARKETPLACE_DIR unset: skip) ==="
set +e
out="$(env -u MARKETPLACE_DIR bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "0" "check-version MARKETPLACE_DIR-unset exit code"
echo "$out" | grep -q "MARKETPLACE_DIR not set" \
    || fail "check-version did not report MARKETPLACE_DIR unset"

# check-version skips non-fatally when the marketplace file doesn't exist.
echo "=== check-version (marketplace.json missing: skip) ==="
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$proj/no-such-marketplace.json" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "0" "check-version missing-marketplace exit code"

# check-version skips non-fatally when the plugin has no marketplace entry
# yet (pre-first-publication), rather than failing.
echo "=== check-version (no entry: skip) ==="
jq -n '{plugins: []}' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "0" "check-version no-entry exit code"
echo "$out" | grep -q "no fixture entry" \
    || fail "check-version did not report the missing entry"

# check-version passes when plugin.json and the marketplace entry agree,
# reading the plugin name from plugin.json rather than a hardcoded name.
echo "=== check-version (in sync: pass) ==="
jq -n '{plugins: [{name: "fixture", version: "1.2.3"}]}' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "0" "check-version in-sync exit code"
echo "$out" | grep -q "in sync (1.2.3)" \
    || fail "check-version did not report in sync"

# check-version fails when plugin.json and the marketplace entry disagree.
echo "=== check-version (drift: fail) ==="
jq -n '{plugins: [{name: "fixture", version: "1.2.2"}]}' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "1" "check-version drift exit code"
echo "$out" | grep -q "version drift" \
    || fail "check-version did not report drift"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall hook scenarios passed\n'

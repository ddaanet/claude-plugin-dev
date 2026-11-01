#!/usr/bin/env bash
# End-to-end test of toolkit/check-version.sh against hand-crafted
# plugin.json / marketplace.json fixtures. Each scenario is a real
# invocation; assertions exit non-zero on failure.
#
# No git anywhere: check-version.sh reads two JSON files and shells out to
# `jq`, nothing more. That is why this file carries none of the leaked-GIT_*
# preamble its sibling suites open with -- there is no git command here for a
# leaked GIT_DIR to redirect.
#
# Usage: bash tests/check-version-test.sh   (run from repo root)
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

# A fake plugin root with a hand-crafted .claude-plugin/plugin.json, so
# assertions are independent of whatever consumer plugin happens to vendor
# this toolkit. The marketplace file is rewritten per scenario.
proj="$(mktemp -d "${TMPDIR:-/tmp}/check-version.XXXXXX")"
trap 'rm -rf "$proj"' EXIT
mkdir -p "$proj/.claude-plugin"
cat > "$proj/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.2.3",
  "license": "MIT"
}
JSON

market="$proj/marketplace.json"

# check-version skips non-fatally when MARKETPLACE_DIR is unset and no
# explicit marketplace path is given.
echo "=== check-version (MARKETPLACE_DIR unset: skip) ==="
set +e
out="$(env -u MARKETPLACE_DIR bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "0" "check-version MARKETPLACE_DIR-unset exit code"
grep -q "MARKETPLACE_DIR not set" <<<"$out" \
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
grep -q "no fixture entry" <<<"$out" \
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
grep -q "in sync (1.2.3)" <<<"$out" \
    || fail "check-version did not report in sync"

# check-version fails when plugin.json and the marketplace entry disagree.
echo "=== check-version (drift: fail) ==="
jq -n '{plugins: [{name: "fixture", version: "1.2.2"}]}' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "1" "check-version drift exit code"
grep -q "version drift" <<<"$out" \
    || fail "check-version did not report drift"

# A marketplace file with no plugins list is malformed, not a plugin with no
# entry: it fails with its own diagnosis rather than jq's raw exit 5, which a
# caller would report as drift.
echo "=== check-version (marketplace has no plugins list: fail) ==="
jq -n '{name: "m"}' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "1" "check-version no-plugins-list exit code"
grep -q "no plugins list" <<<"$out" \
    || fail "check-version did not name the missing plugins list"
if grep -q "version drift" <<<"$out"; then
    fail "check-version reported drift for a malformed marketplace file"
fi

# Unparseable JSON is not "no plugins list": jq's parse error goes to stderr
# beside the script's own line, and the line names the real problem.
echo "=== check-version (marketplace is not JSON: fail) ==="
printf '{"plugins": [\n' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "1" "check-version unparseable-marketplace exit code"
grep -q "not valid JSON" <<<"$out" \
    || fail "check-version did not say the marketplace file is not valid JSON"
if grep -q "no plugins list" <<<"$out"; then
    fail "check-version called an unparseable marketplace file a missing plugins list"
fi

# A plugins list holding a non-object passes a type-is-array test and then
# aborts the entry lookup with a bare jq status.
echo "=== check-version (plugins list holds a non-object: fail) ==="
jq -n '{plugins: ["x"]}' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/.claude-plugin/plugin.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "1" "check-version non-object-entry exit code"
grep -q "entry that is not an object" <<<"$out" \
    || fail "check-version did not name the non-object plugins entry"

# A manifest with no .name makes jq print the literal `null`, which would then
# look up an entry named "null": refuse it instead.
echo "=== check-version (plugin.json has no name: fail) ==="
jq 'del(.name)' "$proj/.claude-plugin/plugin.json" > "$proj/nameless.json"
jq -n '{plugins: []}' > "$market"
set +e
out="$(bash toolkit/check-version.sh "$proj/nameless.json" "$market" 2>&1)"
rc=$?
set -e
assert_eq "$rc" "1" "check-version nameless-manifest exit code"
grep -q "has no .name" <<<"$out" \
    || fail "check-version did not report the missing .name"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall check-version scenarios passed\n'

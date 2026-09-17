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
proj="$(mktemp -d)"
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
printf '\nall check-version scenarios passed\n'

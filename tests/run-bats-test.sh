#!/usr/bin/env bash
# Tests toolkit/run-bats.sh, the quiet bats runner, against a stub `bats` on
# PATH: the stub prints a canned TAP stream and exits with a canned status, so
# each scenario fixes exactly what the runner is handed and checks only what it
# does with it. The runner's job is a summary: a green run is one line, a red
# run is the `not ok` blocks and one line, and the status is bats' own.
#
# Usage: bash tests/run-bats-test.sh   (run from repo root)
set -euo pipefail

unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
runner="$repo_root/toolkit/run-bats.sh"

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
    # $1=haystack $2=needle $3=label : a fixed string, here-string so a
    # SIGPIPE from an early grep match cannot fail the pipeline under pipefail.
    if ! grep -qF -- "$2" <<<"$1"; then
        fail "$3: output did not contain '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}
assert_not_contains() {
    # $1=haystack $2=needle $3=label
    if grep -qF -- "$2" <<<"$1"; then
        fail "$3: output unexpectedly contained '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}

sandbox="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT
stubbin="$sandbox/stubbin"
mkdir -p "$stubbin" "$sandbox/tmp"

# The stub: prints $STUB_BATS_OUT (a file) and exits $STUB_BATS_STATUS, after
# recording its argv one argument per line.
cat > "$stubbin/bats" <<'STUB'
#!/bin/sh
for a in "$@"; do printf '%s\n' "$a"; done > "$STUB_BATS_ARGV"
cat "$STUB_BATS_OUT"
exit "${STUB_BATS_STATUS:-0}"
STUB
chmod +x "$stubbin/bats"

# run_runner <tap-text> <status> [bats args...]: sets $out (stdout and stderr
# together), $rc and $log (the path the summary line names, "" when it names
# none).
run_runner() {
    local tap="$1" status="$2"
    shift 2
    printf '%s' "$tap" > "$sandbox/tap"
    rc=0
    out="$(TMPDIR="$sandbox/tmp" PATH="$stubbin:$PATH" \
        STUB_BATS_OUT="$sandbox/tap" STUB_BATS_STATUS="$status" \
        STUB_BATS_ARGV="$sandbox/argv" bash "$runner" "$@" 2>&1)" || rc=$?
    log="$(sed -n 's/^.* — full log: //p' <<<"$out")"
}

echo "=== a green run of many tests is one line ==="
tap="1..300
"
for i in $(seq 1 300); do tap+="ok $i test number $i
"; done
run_runner "$tap" 0 tests/a.bats
assert_eq "$rc" "0" "green: exit status"
assert_eq "$out" "bats: 300 passed, 0 failed — full log: $log" "green: output is the summary line alone"
base="$(basename "${log:-none}")"
case "$base" in
    plugin-dev-bats.*) ;;
    *) fail "green: log '$log' is not named plugin-dev-bats.*" ;;
esac
assert_eq "$(dirname "${log:-none}")" "$sandbox/tmp" "green: log lives under TMPDIR"
if [[ -f "$log" ]]; then
    assert_eq "$(grep -c '^ok ' "$log")" "300" "green: the log keeps the whole stream"
else
    fail "green: the summary names a log that does not exist: '$log'"
fi

echo "=== a red run shows the not-ok block and not the passing tests ==="
tap="1..3
ok 1 first passes
not ok 2 second fails
# (in test file tests/a.bats, line 9)
#   \`false' failed
ok 3 third passes
"
run_runner "$tap" 1 tests/a.bats
assert_eq "$rc" "1" "red: bats' status is the exit status"
assert_contains "$out" "not ok 2 second fails" "red: failing test shown"
assert_contains "$out" "# (in test file tests/a.bats, line 9)" "red: diagnostic line shown"
assert_not_contains "$out" "ok 1 first passes" "red: a passing test before is hidden"
assert_not_contains "$out" "ok 3 third passes" "red: a passing test after is hidden"
assert_contains "$out" "bats: 2 passed, 1 failed — full log: " "red: summary line"

echo "=== the exit status is bats' own, whatever its value ==="
run_runner "1..1
ok 1 x
" 7 tests/a.bats
assert_eq "$rc" "7" "status 7 passes through even with no failing test"

echo "=== a stream with no TAP line is shown whole ==="
run_runner "bats: error: could not parse the plan
" 2 tests/a.bats
assert_eq "$rc" "2" "no TAP: exit status"
assert_contains "$out" "bats: error: could not parse the plan" "no TAP: raw output shown"
assert_contains "$out" "bats: 0 passed, 0 failed — full log: " "no TAP: summary line"

echo "=== arguments reach bats unchanged ==="
run_runner "1..1
ok 1 x
" 0 --jobs 4 "tests/with space.bats" --filter "a b"
assert_eq "$(cat "$sandbox/argv")" "--jobs
4
tests/with space.bats
--filter
a b" "args"

echo "=== two runs in one TMPDIR do not collide on the log ==="
run_runner "1..1
ok 1 x
" 0 tests/a.bats
first="$log"
run_runner "1..1
ok 1 x
" 0 tests/a.bats
if [[ "$first" == "$log" ]]; then
    fail "second run reused the first run's log $first"
fi
if [[ ! -f "$first" || ! -f "$log" ]]; then
    fail "one of the two logs is missing ($first, $log)"
fi

echo "=== no bats on PATH is a reported failure, not a silent pass ==="
tools="$sandbox/tools"
mkdir -p "$tools"
for t in mktemp grep awk cat dirname rm; do
    ln -s "$(command -v "$t")" "$tools/$t"
done
rc=0
out="$(TMPDIR="$sandbox/tmp" PATH="$tools" "$(command -v bash)" "$runner" tests/a.bats 2>&1)" || rc=$?
if [[ "$rc" == "0" ]]; then
    fail "no bats: exited 0"
fi
assert_contains "$out" "bats: 0 passed, 0 failed" "no bats: summary line still printed"
assert_contains "$out" "bats" "no bats: the shell's complaint is shown"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nrun-bats ok (green, red, status, no-TAP, args, log collision, no bats)\n'

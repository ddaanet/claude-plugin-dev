#!/usr/bin/env bash
# Pins the root guard in tests/release-core-test.sh: its three `chmod 555`
# scenarios cannot mean anything as root, so they must print a SKIP line naming
# each and must not run, and as a non-root user they must run and print none.
#
# The script under test is that suite, run twice from here. `id` and `chmod` are
# stubs first on PATH: `id -u` prints 0 to play root, and the chmod wrapper logs
# each call before running the real one, which is what tells "skipped" from
# "ran and happened to pass" -- a scenario that runs calls `chmod 555`.
#
# Usage: bash tests/release-core-root-skip-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command the suite under test runs targets a fixture repo via `-C`, so it
# is always safe to drop them here.
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
    fi
}

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
stubs="$scratch/bin"
mkdir -p "$stubs"
real_chmod="$(command -v chmod)"

# Unquoted EOF: $real_chmod expands now, \$ stays for run time.
cat > "$stubs/chmod" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "\$CHMOD_LOG"
exec "$real_chmod" "\$@"
EOF
"$real_chmod" 755 "$stubs/chmod"
printf '#!/bin/sh\necho 0\n' > "$stubs/id"
mkdir -p "$scratch/bin-chmod-only"
cp "$stubs/chmod" "$scratch/bin-chmod-only/chmod"
"$real_chmod" 755 "$stubs/id"

run_core() {
    # $1=log file, $2=PATH prefix ("" for none). Sets $out and $rc.
    set +e
    out="$(CHMOD_LOG="$1" PATH="$2$PATH" bash tests/release-core-test.sh 2>&1)"
    rc=$?
    set -e
}

titles=(
    "release: refuses when the marketplace directory isn't writable"
    "resume: succeeds on a no-op marketplace bump even when its directory isn't writable"
    "resume: still refuses when a real marketplace write is needed and the directory isn't writable"
)

echo "=== run as root: each chmod 555 scenario is skipped by name and does not run ==="
: > "$scratch/root.log"
# Only the suite's own `id` is faked: a PATH stub for `id` does not change who
# this shell is, so the real chmod calls below it behave as the real user's.
run_core "$scratch/root.log" "$stubs:"
assert_eq "$rc" "0" "root-run exit code"
for t in "${titles[@]}"; do
    assert_contains "$out" "SKIP: $t -- running as root" "root-run skips '$t'"
done
assert_eq "$(grep -c '^SKIP:' <<<"$out" || true)" "3" "root-run prints exactly three SKIP lines"
assert_eq "$(grep -c '^555 ' "$scratch/root.log" || true)" "0" "root-run never ran a chmod 555 scenario"

echo "=== run as a non-root user: the scenarios run and nothing is skipped ==="
if [ "$(id -u)" -eq 0 ]; then
    # Genuinely root: the suite skips for real, so this half has nothing to
    # observe. Said aloud rather than passed.
    printf 'SKIP: non-root half -- this run is root\n'
else
    : > "$scratch/user.log"
    run_core "$scratch/user.log" "$scratch/bin-chmod-only:"
    assert_eq "$rc" "0" "non-root run exit code"
    assert_eq "$(grep -c '^SKIP:' <<<"$out" || true)" "0" "non-root run prints no SKIP line"
    assert_eq "$(grep -c '^555 ' "$scratch/user.log" || true)" "3" "non-root run ran all three chmod 555 scenarios"
fi

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nroot guard scenarios passed\n'

#!/usr/bin/env bash
# Tests `hash-sentinel` in toolkit/gates.just: the re-hash a gate takes after a
# formatter that runs past its guard, so the pass records the formatted tree.
# A fixture consumer repo imports the file and defines shebang recipes opening
# with the prolog; each scenario runs the real `just` recipe. The formatter and
# the checks each append a line to a log outside the repo, so "the formatter
# ran" and "the checks ran" are counts and never an inference from output.
# Same fixture shape as gates-sentinel-test.sh, which covers the cache itself.
#
# Usage: bash tests/gates-hash-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo, never this repo.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# Keep the host's git identity and config, and any gate switch, out of the
# fixtures.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
unset PLUGIN_DEV_GATE_DIR PLUGIN_DEV_GATE_FORCE PLUGIN_DEV_GATE_TOOLS

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

sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gates-hash.XXXXXX")" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT

# mk_consumer: a fresh repo $repo, whose own path holds a space, importing the
# toolkit's gates.just from plugin-dev/. src/a.txt starts unformatted; the
# formatter rewrites it to its fixpoint, so it edits an input on the first run
# and nothing after. `formatted` re-hashes after formatting; `unformatted` does
# not; `barehash` re-hashes with no guard; `hashfail` re-hashes while the tool
# list fails, then restores it; `peer` re-hashes, then an input moves while the
# checks run. Formatter lines go to $FMT_LOG, check lines to $RUN_LOG, both
# outside the repo so neither is an input.
mk_consumer() {
    n=$((${n:-0} + 1))
    repo="$sandbox/con sumer $n"
    runlog="$sandbox/run-$n.log"
    fmtlog="$sandbox/fmt-$n.log"
    : > "$runlog"
    : > "$fmtlog"
    mkdir -p "$repo/src"
    git -C "$repo" init -q
    printf 'unformatted\n' > "$repo/src/a.txt"
    cat > "$repo/justfile" <<'JUSTFILE'
import 'plugin-dev/gates.just'

formatted:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard formatted src
    echo fmt >> "$FMT_LOG"
    printf 'formatted\n' > src/a.txt
    hash-sentinel
    echo ran >> "$RUN_LOG"
    record-sentinel

unformatted:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard unformatted src
    echo fmt >> "$FMT_LOG"
    printf 'formatted\n' > src/a.txt
    echo ran >> "$RUN_LOG"
    record-sentinel

barehash:
    #!{{ plugin_dev_gate_prolog }}
    hash-sentinel
    echo ran >> "$RUN_LOG"

hashfail:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard hashfail src
    export PLUGIN_DEV_GATE_TOOLS=false
    hash-sentinel
    unset PLUGIN_DEV_GATE_TOOLS
    echo ran >> "$RUN_LOG"
    record-sentinel

peer:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard peer src
    printf 'formatted\n' > src/a.txt
    hash-sentinel
    echo ran >> "$RUN_LOG"
    echo "peer edit" >> src/a.txt
    record-sentinel
JUSTFILE
    mkdir -p "$repo/plugin-dev"
    cp "$repo_root/toolkit/gates.just" "$repo/plugin-dev/gates.just"
}

# run_gate <recipe>: runs the recipe in $repo; sets $out (stdout and stderr
# together) and $rc.
run_gate() {
    rc=0
    out="$(cd "$repo" && env RUN_LOG="$runlog" FMT_LOG="$fmtlog" just "$1" 2>&1)" || rc=$?
}

runs() {
    grep -c '^ran$' "$runlog" || true
}

formats() {
    grep -c '^fmt$' "$fmtlog" || true
}

sentinel_file() {
    printf '%s/.git/plugin-dev/gates/%s' "$repo" "$1"
}

echo "=== a formatter's edit before hash-sentinel is recorded in one run ==="
mk_consumer
run_gate formatted
assert_eq "$rc" "0" "formatting run: exit status"
assert_eq "$(runs)" "1" "formatting run executes the checks"
assert_eq "$(cat "$repo/src/a.txt")" "formatted" "the formatter rewrote the input"
assert_not_contains "$out" "NOT recorded" "the formatted tree's pass is recorded"
if [[ ! -s "$(sentinel_file formatted)" ]]; then
    fail "a run whose formatter edited an input left no sentinel"
fi

echo "=== the next run is a cache hit that skips the formatter ==="
run_gate formatted
assert_eq "$rc" "0" "cached run: exit status"
assert_eq "$out" "formatted: cached (inputs unchanged)" "cached run reports itself"
assert_eq "$(formats)" "1" "a cache hit does not run the formatter"
assert_eq "$(runs)" "1" "a cache hit does not run the checks"

echo "=== without hash-sentinel a formatter's edit is not recorded ==="
mk_consumer
run_gate unformatted
assert_eq "$rc" "0" "unhashed formatting run: exit status"
assert_contains "$out" "inputs changed while the checks ran; the pass was NOT recorded" \
    "the formatter's edit reads as a moved input"
if [[ -e "$(sentinel_file unformatted)" ]]; then
    fail "a pass was recorded against a tree the guard did not hash"
fi
run_gate unformatted
assert_eq "$(runs)" "2" "the second run does the work again"
assert_not_contains "$out" "NOT recorded" "the second run, with nothing to format, records"
run_gate unformatted
assert_eq "$(runs)" "2" "only the third run is cached"

echo "=== hash-sentinel with no guard before it is refused ==="
mk_consumer
run_gate barehash
assert_eq "$rc" "1" "hash-sentinel with no guard: exit status"
assert_contains "$out" "hash-sentinel: no sentinel-guard ran earlier in this recipe body" \
    "hash-sentinel with no guard: message"
assert_eq "$(runs)" "0" "nothing after the refusal runs"

echo "=== a re-hash that fails leaves record-sentinel refusing ==="
mk_consumer
run_gate hashfail
assert_eq "$rc" "0" "failed re-hash: the checks passed, so the recipe does"
assert_eq "$(runs)" "1" "failed re-hash: the checks still run"
assert_contains "$out" "could not hash inputs; the pass was NOT recorded" "failed re-hash: message"
if [[ -e "$(sentinel_file hashfail)" ]]; then
    fail "a pass was recorded though the re-hash failed"
fi

echo "=== an input that moves after hash-sentinel is still not recorded ==="
mk_consumer
run_gate peer
assert_eq "$rc" "0" "moved after re-hash: exit status"
assert_contains "$out" "inputs changed while the checks ran; the pass was NOT recorded" \
    "moved after re-hash: message"
if [[ -e "$(sentinel_file peer)" ]]; then
    fail "a pass was recorded against a tree that moved after the re-hash"
fi

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\ngates hash ok (formatted pass recorded, cache hit skips the formatter, unhashed edit not recorded, no guard refused, failed re-hash, moved after re-hash)\n'

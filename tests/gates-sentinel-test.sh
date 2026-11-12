#!/usr/bin/env bash
# Tests the gate sentinels in toolkit/gates.just end to end: a fixture consumer
# repo imports the file and defines shebang recipes opening with the prolog, and
# each scenario runs the real `just` recipe and reads what it did. A gate's
# checks are a line appended to a run log outside the repo, so "the checks ran"
# is a count and never an inference from output.
#
# Scope: the cache itself -- what moves the input hash and what does not, the
# force switch, where the sentinel lives. Its sibling gates-guards-test.sh covers
# the refusals and the passes that are deliberately not recorded.
#
# Usage: bash tests/gates-sentinel-test.sh   (run from repo root)
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

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/gates-sentinel.XXXXXX")" || exit 1
sandbox="$(cd "$sandbox" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT

# mk_consumer: a fresh repo $repo, whose own path holds a space, importing the
# toolkit's gates.just from plugin-dev/, where a consumer vendors it. `gate`
# guards over src and .gitignore, which shapes it;
# `narrow` subtracts src/b.txt with an exclude pathspec; `other` is a second
# gate in its own recipe; `cded` changes directory between guard and record;
# `failing` fails after its guard. Every recipe appends to $RUN_LOG, which lives
# outside the repo so it is not an input.
mk_consumer() {
    n=$((${n:-0} + 1))
    repo="$sandbox/con sumer $n"
    runlog="$sandbox/run-$n.log"
    : > "$runlog"
    mkdir -p "$repo/src" "$repo/other"
    git -C "$repo" init -q
    printf 'a\n' > "$repo/src/a.txt"
    printf 'b\n' > "$repo/src/b.txt"
    printf 'x\n' > "$repo/other/x.txt"
    printf '*.log\n' > "$repo/.gitignore"
    cat > "$repo/justfile" <<'JUSTFILE'
import 'plugin-dev/gates.just'

gate:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard gate src .gitignore
    echo ran >> "$RUN_LOG"
    record-sentinel

narrow:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard narrow src ':(exclude)src/b.txt'
    echo ran >> "$RUN_LOG"
    record-sentinel

other:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard other src
    echo ran >> "$RUN_LOG"
    record-sentinel

cded:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard cded src
    cd src
    echo ran >> "$RUN_LOG"
    record-sentinel

failing:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard failing src
    echo ran >> "$RUN_LOG"
    echo "the check failed" >&2
    exit 3
    record-sentinel
JUSTFILE
    mkdir -p "$repo/plugin-dev"
    cp "$repo_root/toolkit/gates.just" "$repo/plugin-dev/gates.just"
}

# run_gate <recipe> [VAR=value...]: runs the recipe in $repo; sets $out (stdout
# and stderr together) and $rc.
run_gate() {
    local recipe="$1"
    shift
    rc=0
    out="$(cd "$repo" && env RUN_LOG="$runlog" "$@" just "$recipe" 2>&1)" || rc=$?
}

runs() {
    wc -l < "$runlog" | tr -d ' '
}

sentinel_file() {
    # $1=gate : the default sentinel path
    printf '%s/.git/plugin-dev/gates/%s' "$repo" "$1"
}

echo "=== the first run runs the checks and records a sentinel ==="
mk_consumer
run_gate gate
assert_eq "$rc" "0" "first run exit status"
assert_eq "$(runs)" "1" "first run executes the checks"
assert_not_contains "$out" "cached" "first run is not reported cached"
assert_not_contains "$out" "No such file" "first run reads no sentinel that is not there"
if [[ ! -s "$(sentinel_file gate)" ]]; then
    fail "first run left no sentinel at the gitdir path $(sentinel_file gate)"
fi
status="$(git -C "$repo" status --porcelain --untracked-files=all)"
assert_not_contains "$status" "plugin-dev/gates/" "the sentinel is not in the working tree"

echo "=== an unchanged tree is a cached pass ==="
run_gate gate
assert_eq "$rc" "0" "cached run exit status"
assert_eq "$out" "gate: cached (inputs unchanged)" "cached run reports itself"
assert_eq "$(runs)" "1" "cached run does not execute the checks"

echo "=== editing an input reruns, then caches again ==="
printf 'a2\n' > "$repo/src/a.txt"
run_gate gate
assert_eq "$(runs)" "2" "edited input reruns"
run_gate gate
assert_eq "$(runs)" "2" "the rerun's pass is cached in turn"

echo "=== a new file that is not yet added counts ==="
printf 'new\n' > "$repo/src/new.txt"
run_gate gate
assert_eq "$(runs)" "3" "an untracked input file reruns"

echo "=== an ignored file does not count ==="
printf 'noise\n' > "$repo/src/noise.log"
run_gate gate
assert_eq "$(runs)" "3" "an ignored file leaves the pass cached"

echo "=== a rename with the same content counts ==="
mv "$repo/src/new.txt" "$repo/src/renamed.txt"
run_gate gate
assert_eq "$(runs)" "4" "a rename reruns"

echo "=== a deletion counts ==="
rm "$repo/src/renamed.txt"
run_gate gate
assert_eq "$(runs)" "5" "a deletion reruns"

echo "=== a path outside the declared inputs does not count ==="
printf 'x2\n' > "$repo/other/x.txt"
run_gate gate
assert_eq "$(runs)" "5" "an edit outside the allow-list leaves the pass cached"

echo "=== the justfile counts though no guard lists it ==="
printf '# touched\n' >> "$repo/justfile"
run_gate gate
assert_eq "$(runs)" "6" "editing the justfile, a built-in input, reruns"

echo "=== PLUGIN_DEV_GATE_FORCE reruns a cached gate and still records ==="
run_gate gate PLUGIN_DEV_GATE_FORCE=1
assert_eq "$(runs)" "7" "a forced run executes the checks"
assert_not_contains "$out" "cached" "a forced run is not reported cached"
run_gate gate
assert_eq "$(runs)" "7" "an unforced run after a forced one is cached"

echo "=== PLUGIN_DEV_GATE_DIR moves the sentinel out of the gitdir ==="
mk_consumer
run_gate gate "PLUGIN_DEV_GATE_DIR=$sandbox/elsewhere"
assert_eq "$(runs)" "1" "run with a custom sentinel dir"
if [[ ! -s "$sandbox/elsewhere/gate" ]]; then
    fail "no sentinel at the PLUGIN_DEV_GATE_DIR path"
fi
if [[ -e "$(sentinel_file gate)" ]]; then
    fail "a sentinel was also written under the gitdir"
fi
run_gate gate "PLUGIN_DEV_GATE_DIR=$sandbox/elsewhere"
assert_eq "$(runs)" "1" "the custom dir's sentinel caches"
run_gate gate
assert_eq "$(runs)" "2" "the default dir knows nothing of the custom one's pass"

echo "=== plugin-dev counts though no guard lists it ==="
mk_consumer
mkdir -p "$repo/plugin-dev"
printf 'v1\n' > "$repo/plugin-dev/run-bats.sh"
run_gate other
run_gate other
assert_eq "$(runs)" "1" "plugin-dev present: cached"
printf 'v2\n' > "$repo/plugin-dev/run-bats.sh"
run_gate other
assert_eq "$(runs)" "2" "editing a file under plugin-dev, a built-in input, reruns"

echo "=== the execute bit counts, tracked or not ==="
mk_consumer
run_gate other
chmod +x "$repo/src/a.txt"
run_gate other
assert_eq "$(runs)" "2" "setting the execute bit on an untracked file reruns"
chmod -x "$repo/src/a.txt"
run_gate other
assert_eq "$(runs)" "3" "clearing it reruns"
git -C "$repo" add src/a.txt
run_gate other
assert_eq "$(runs)" "3" "adding the file to the index alone moves nothing"
chmod +x "$repo/src/a.txt"
run_gate other
assert_eq "$(runs)" "4" "setting the execute bit on a tracked file reruns"

echo "=== a name and a content that stream the same bytes are told apart ==="
mk_consumer
printf 'c1\n' > "$repo/src/a.txt"
printf 'c2\n' > "$repo/src/b.txt"
run_gate other
rm "$repo/src/b.txt"
printf 'c1\nsrc/b.txt\nc2\n' > "$repo/src/a.txt"
run_gate other
assert_eq "$(runs)" "2" "one file holding another's name and content is not the same tree"

echo "=== a cd between guard and record does not break the gate ==="
mk_consumer
run_gate cded
assert_eq "$rc" "0" "run with a cd after the guard: exit status"
assert_eq "$(runs)" "1" "run with a cd executes the checks"
if [[ ! -s "$(sentinel_file cded)" ]]; then
    fail "a recipe that cd'd left no sentinel at $(sentinel_file cded)"
fi
run_gate cded
assert_eq "$rc" "0" "second run with a cd: exit status"
assert_eq "$(runs)" "1" "a recipe that cd'd is cached on an untouched tree"

echo "=== gates in separate recipes keep separate sentinels ==="
mk_consumer
run_gate gate
run_gate other
assert_eq "$(runs)" "2" "a second gate is not cached by the first's pass"
run_gate gate
run_gate other
assert_eq "$(runs)" "2" "both are cached after their own passes"
printf 'a3\n' > "$repo/src/a.txt"
run_gate gate
run_gate other
assert_eq "$(runs)" "4" "an edit under both inputs reruns both"

echo "=== an exclude pathspec narrows the hash ==="
mk_consumer
run_gate narrow
printf 'b2\n' > "$repo/src/b.txt"
run_gate narrow
assert_eq "$(runs)" "1" "an excluded file's edit leaves the pass cached"
printf 'a2\n' > "$repo/src/a.txt"
run_gate narrow
assert_eq "$(runs)" "2" "a non-excluded file's edit reruns"

echo "=== a failed check leaves no sentinel and reruns next time ==="
mk_consumer
run_gate failing
assert_eq "$rc" "3" "the check's own exit status is the recipe's"
if [[ -e "$(sentinel_file failing)" ]]; then
    fail "a failed gate left a sentinel"
fi
run_gate failing
assert_eq "$(runs)" "2" "a failed gate runs again on an untouched tree"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\ngates sentinel ok (record, cache, inputs, built-ins, execute bit, name/content boundary, cd, force, dir, separate gates, exclude, failure)\n'

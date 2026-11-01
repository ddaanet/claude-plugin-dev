#!/usr/bin/env bash
# Tests which files toolkit/gates.just hashes, end to end: a fixture consumer
# vendors the file at plugin-dev/ and defines shebang recipes opening with the
# prolog, and each scenario runs the real `just` recipe and reads what it did. A
# gate's checks are a line appended to a run log outside the repo, so "the checks
# ran" is a count and never an inference from output.
#
# Scope: the guard's built-in inputs (the justfile and the vendored tree) wherever
# the justfile is named and run from, an exclude-only pathspec list, a symlink
# standing in for a regular file, and a caller that sets `gate_inputs` alone.
# Its siblings cover the cache (gates-sentinel-test.sh) and the refusals
# (gates-guards-test.sh).
#
# Usage: bash tests/gates-inputs-test.sh   (run from repo root)
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
assert_ne() {
    # $1=actual $2=unwanted $3=label
    if [[ "$1" == "$2" ]]; then
        fail "$3: expected anything but '$2'"
    fi
}

sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/gates-inputs.XXXXXX")" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT

# mk_consumer [justfile-name]: a fresh repo $repo, whose own path holds a space,
# importing the toolkit's gates.just from plugin-dev/, where a consumer vendors
# it. `gate` guards over src; `excl` and `exclvend` guard with excludes alone or
# beside src; `wd` runs in sub/ by `[working-directory]`; the module `m` imports
# the prolog itself and its recipe runs in m/. Every recipe appends to $RUN_LOG,
# which lives outside the repo so it is not an input.
mk_consumer() {
    local name="${1:-justfile}"
    n=$((${n:-0} + 1))
    repo="$sandbox/con sumer $n"
    runlog="$sandbox/run-$n.log"
    : > "$runlog"
    mkdir -p "$repo/src" "$repo/docs" "$repo/sub" "$repo/m" "$repo/plugin-dev"
    git -C "$repo" init -q
    printf 'a\n' > "$repo/src/a.txt"
    printf 'a\n' > "$repo/src/real.txt"
    printf 'd\n' > "$repo/docs/d.txt"
    printf 's\n' > "$repo/sub/s.txt"
    printf 'o\n' > "$repo/other.txt"
    printf 'tool\n' > "$repo/plugin-dev/tool.sh"
    cp "$repo_root/toolkit/gates.just" "$repo/plugin-dev/gates.just"
    cat > "$repo/$name" <<'JUSTFILE'
import 'plugin-dev/gates.just'

mod m

gate:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard gate src
    echo ran >> "$RUN_LOG"
    record-sentinel

excl:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard excl ':!docs'
    echo ran >> "$RUN_LOG"
    record-sentinel

exclvend:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard exclvend src ':!plugin-dev'
    echo ran >> "$RUN_LOG"
    record-sentinel

[working-directory: 'sub']
wd:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard wd .
    echo ran >> "$RUN_LOG"
    record-sentinel
JUSTFILE
    cat > "$repo/m/mod.just" <<'JUSTFILE'
import '../plugin-dev/gates.just'

modgate:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard modgate .
    echo ran >> "$RUN_LOG"
    record-sentinel
JUSTFILE
}

# run_gate <recipe>: runs the recipe in $repo; sets $out (stdout and stderr
# together) and $rc.
run_gate() {
    rc=0
    out="$(cd "$repo" && env RUN_LOG="$runlog" just "$@" 2>&1)" || rc=$?
}

runs() {
    wc -l < "$runlog" | tr -d ' '
}

echo "=== a list of excludes alone subtracts from the whole repo ==="
mk_consumer
run_gate excl
assert_eq "$rc" "0" "exclude-only gate: exit status ($out)"
run_gate excl
assert_eq "$(runs)" "1" "exclude-only gate caches"
printf 'a2\n' > "$repo/src/a.txt"
run_gate excl
assert_eq "$(runs)" "2" "a file the excludes leave in reruns"
printf 'd2\n' > "$repo/docs/d.txt"
run_gate excl
assert_eq "$(runs)" "2" "a file the excludes remove leaves the pass cached"
printf '# touched\n' >> "$repo/justfile"
run_gate excl
assert_eq "$(runs)" "3" "the justfile counts beside an exclude-only list"

echo "=== an exclude in the list does not reach the built-in inputs ==="
mk_consumer
run_gate exclvend
run_gate exclvend
assert_eq "$(runs)" "1" "setup: the gate caches"
printf 'tool2\n' > "$repo/plugin-dev/tool.sh"
run_gate exclvend
assert_eq "$(runs)" "2" "the vendored tree counts though the list excludes it"

echo "=== the justfile counts under any name ==="
mk_consumer Justfile
run_gate gate
assert_eq "$rc" "0" "a Justfile: exit status ($out)"
run_gate gate
assert_eq "$(runs)" "1" "a Justfile gate caches"
printf '# touched\n' >> "$repo/Justfile"
run_gate gate
assert_eq "$(runs)" "2" "editing a Justfile reruns"

echo "=== the built-ins count from a recipe that runs in a subdirectory ==="
mk_consumer
run_gate wd
assert_eq "$rc" "0" "working-directory gate: exit status ($out)"
run_gate wd
assert_eq "$(runs)" "1" "working-directory gate caches"
printf '# touched\n' >> "$repo/justfile"
run_gate wd
assert_eq "$(runs)" "2" "editing the justfile reruns a gate that runs in sub/"
printf 'tool2\n' > "$repo/plugin-dev/tool.sh"
run_gate wd
assert_eq "$(runs)" "3" "editing the vendored tree reruns it"
printf 'o2\n' > "$repo/other.txt"
run_gate wd
assert_eq "$(runs)" "3" "a file outside sub/ and the built-ins leaves it cached"

echo "=== the built-ins count from a recipe in a module ==="
mk_consumer
run_gate m::modgate
assert_eq "$rc" "0" "module gate: exit status ($out)"
run_gate m::modgate
assert_eq "$(runs)" "1" "module gate caches"
printf '# touched\n' >> "$repo/justfile"
run_gate m::modgate
assert_eq "$(runs)" "2" "editing the root justfile reruns a module gate"
printf 'tool2\n' > "$repo/plugin-dev/tool.sh"
run_gate m::modgate
assert_eq "$(runs)" "3" "editing the vendored tree reruns it"

echo "=== a symlink is not the regular file it points at ==="
mk_consumer
run_gate gate
rm "$repo/src/a.txt"
ln -s real.txt "$repo/src/a.txt"
run_gate gate
assert_eq "$(runs)" "2" "swapping a file for a symlink to the same content reruns"
run_gate gate
assert_eq "$(runs)" "2" "the symlink tree caches in turn"

echo "=== a symlink keeps its target's execute bit and its own target path ==="
# The targets sit outside the guarded src/, so only the link itself is listed.
mk_consumer
cp "$repo/other.txt" "$repo/other2.txt"
ln -s ../other.txt "$repo/src/lnk"
ln -s ../docs "$repo/src/dlnk"
run_gate gate
run_gate gate
assert_eq "$(runs)" "1" "setup: a tree with links caches"
chmod +x "$repo/other.txt"
run_gate gate
assert_eq "$(runs)" "2" "the execute bit of a link's target reruns"
run_gate gate
assert_eq "$(runs)" "2" "the new bit caches in turn"
chmod -x "$repo/other.txt"
run_gate gate
assert_eq "$(runs)" "3" "losing the execute bit of a link's target reruns"
run_gate gate
assert_eq "$(runs)" "3" "the lost bit caches in turn"
rm "$repo/src/lnk"
ln -s ../other2.txt "$repo/src/lnk"
run_gate gate
assert_eq "$(runs)" "4" "repointing a file link to an identical file reruns"
rm "$repo/src/lnk"
ln -s ../other.txt "$repo/src/lnk"
run_gate gate
assert_eq "$(runs)" "5" "repointing it back reruns"
rm "$repo/src/dlnk"
ln -s ../sub "$repo/src/dlnk"
run_gate gate
assert_eq "$(runs)" "6" "repointing a directory link reruns"
run_gate gate
assert_eq "$(runs)" "6" "the repointed tree caches in turn"
ln -s ../nowhere "$repo/src/dangling"
run_gate gate
assert_eq "$(runs)" "7" "adding a dangling link reruns"
rm "$repo/src/dangling"
ln -s ../elsewhere "$repo/src/dangling"
run_gate gate
assert_eq "$(runs)" "8" "repointing a dangling link to another missing target reruns"
run_gate gate
assert_eq "$(runs)" "8" "the repointed dangling link caches in turn"

echo "=== a caller that sets only gate_inputs can hash ==="
mk_consumer
prolog="$(cd "$repo" && just --evaluate plugin_dev_gate_prolog)"
# The first line is the interpreter, which the shebang would consume.
body="$(tail -n +2 <<<"$prolog")"
hash_only() {
    rc=0
    out="$(cd "$repo" && bash -c "$body"$'\n''gate_inputs=(src); gate-inputs-hash' 2>&1)" || rc=$?
}
hash_only
assert_eq "$rc" "0" "gate-inputs-hash with gate_inputs alone: exit status ($out)"
before="$out"
printf '# touched\n' >> "$repo/justfile"
hash_only
assert_eq "$rc" "0" "second hash: exit status ($out)"
assert_ne "$out" "$before" "the built-in inputs reach a caller that never set them"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\ngates inputs ok (exclude-only, excludes vs built-ins, Justfile, working-directory, module, symlink, link targets, gate_inputs alone)\n'

#!/usr/bin/env bash
# Tests the guards in toolkit/gates.just that stop a gate from recording a pass
# it cannot vouch for, and the refusals that stop a misused prolog: inputs that
# move during a run, a hash that cannot be computed, the tool-version list, a
# second gate in one recipe body, a record with no guard, and bad arguments
# (including a pathspec that matches nothing).
# Same fixture shape as gates-sentinel-test.sh, which covers the cache itself.
#
# Usage: bash tests/gates-guards-test.sh   (run from repo root)
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
assert_nonzero() {
    # $1=status $2=label
    if [[ "$1" == "0" ]]; then
        fail "$2: expected a non-zero status"
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

# mk_consumer: a fresh repo $repo, whose own path holds a space, importing the
# toolkit's gates.just from plugin-dev/, where a consumer vendors it. Each recipe
# appends to $RUN_LOG, which lives outside the
# repo so it is not an input. `moving` edits an input between guard and record;
# `twice` opens two gates in one body; `bare` records with no guard; `nopaths`,
# `badname`, `typo` and `typoglob` misuse the guard, which `forms` does not; `exported` sets the tool list the
# documented way, as an exported just variable.
mk_consumer() {
    n=$((${n:-0} + 1))
    repo="$sandbox/con sumer $n"
    runlog="$sandbox/run-$n.log"
    : > "$runlog"
    mkdir -p "$repo/src"
    git -C "$repo" init -q
    printf 'a\n' > "$repo/src/a.txt"
    cat > "$repo/justfile" <<'JUSTFILE'
import 'plugin-dev/gates.just'

export PLUGIN_DEV_GATE_TOOLS := "echo tool-a 1\necho tool-b 1"

gate:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard gate src
    echo ran >> "$RUN_LOG"
    record-sentinel

moving:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard moving src
    echo ran >> "$RUN_LOG"
    echo "peer edit" >> src/a.txt
    record-sentinel
    echo "after record" >> "$RUN_LOG"

twice:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard first src
    echo first >> "$RUN_LOG"
    sentinel-guard second src
    echo second >> "$RUN_LOG"
    record-sentinel

bare:
    #!{{ plugin_dev_gate_prolog }}
    echo ran >> "$RUN_LOG"
    record-sentinel

nopaths:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard nopaths
    echo ran >> "$RUN_LOG"

badname:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard ../escape src
    echo ran >> "$RUN_LOG"

typo:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard typo src ':(exclude)src/none' srcs
    echo ran >> "$RUN_LOG"

typoglob:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard typoglob src ':(glob)excluded/**'
    echo ran >> "$RUN_LOG"

forms:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard forms src ':^src/none' ':!src/none' ':(top,exclude)src/none' ':(glob,exclude)src/none/**'
    echo ran >> "$RUN_LOG"

# Run in src/, where an exclude of src itself leaves nothing for the listing to
# find: only the exemption keeps these from being refused as matching no file.
[working-directory: 'src']
topbang:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard topbang . ':/!src'
    echo ran >> "$RUN_LOG"

[working-directory: 'src']
topcaret:
    #!{{ plugin_dev_gate_prolog }}
    sentinel-guard topcaret . ':/^src'
    echo ran >> "$RUN_LOG"
JUSTFILE
    mkdir -p "$repo/plugin-dev"
    cp "$repo_root/toolkit/gates.just" "$repo/plugin-dev/gates.just"
}

# run_gate <recipe> [VAR=value...]: runs the recipe in $repo; sets $out (stdout
# and stderr together) and $rc. The justfile exports a default tool list, so
# each scenario that wants a different one passes PLUGIN_DEV_GATE_TOOLS and a
# scenario that wants none passes it empty -- a just `export` wins over the
# environment, so a scenario overrides with `just --set` instead.
run_gate() {
    local recipe="$1"
    shift
    rc=0
    out="$(cd "$repo" && env RUN_LOG="$runlog" "$@" just "$recipe" 2>&1)" || rc=$?
}

# run_gate_tools <recipe> <tool-list>: the same, with the justfile's exported
# variable set to <tool-list> for the call.
run_gate_tools() {
    local recipe="$1" tools="$2"
    rc=0
    out="$(cd "$repo" && env RUN_LOG="$runlog" \
        just --set PLUGIN_DEV_GATE_TOOLS "$tools" "$recipe" 2>&1)" || rc=$?
}

runs() {
    grep -c '^ran$' "$runlog" || true
}

sentinel_file() {
    printf '%s/.git/plugin-dev/gates/%s' "$repo" "$1"
}

echo "=== inputs that move during the run: the checks' verdict stands, the pass is not recorded ==="
mk_consumer
run_gate moving
assert_eq "$rc" "0" "moving inputs: the checks passed, so the recipe does"
assert_contains "$out" "inputs changed while the checks ran; the pass was NOT recorded" "moving inputs message"
if [[ -e "$(sentinel_file moving)" ]]; then
    fail "a sentinel was recorded against a tree that moved"
fi
assert_contains "$(cat "$runlog")" "after record" "the recipe runs on past the unrecorded pass"
run_gate moving
assert_eq "$(runs)" "2" "the next run executes the checks again"

echo "=== a hash that cannot be computed: the pass is not recorded, loudly ==="
mk_consumer
run_gate_tools gate "no-such-tool-xyz --version"
assert_eq "$rc" "0" "unhashable run still passes the recipe"
assert_eq "$(runs)" "1" "unhashable run executes the checks"
assert_contains "$out" "could not hash inputs; the pass was NOT recorded" "unhashable message"
if [[ -e "$(sentinel_file gate)" ]]; then
    fail "a sentinel was recorded from a hash that failed"
fi
run_gate_tools gate "no-such-tool-xyz --version"
assert_eq "$(runs)" "2" "an unhashable gate never reports cached"
# An earlier pass does not survive a later run that records nothing.
run_gate_tools gate "echo v1"
if [[ ! -s "$(sentinel_file gate)" ]]; then
    fail "setup: a hashable run left no sentinel"
fi
run_gate_tools gate "no-such-tool-xyz --version"
if [[ -e "$(sentinel_file gate)" ]]; then
    fail "an earlier sentinel survived a run whose hash failed"
fi

echo "=== a file that cannot be read fails the hash, whichever its place in the list ==="
mk_consumer
printf 'b\n' > "$repo/src/b.txt"
printf 'c\n' > "$repo/src/c.txt"
chmod 000 "$repo/src/b.txt"
if [[ -r "$repo/src/b.txt" ]]; then
    printf 'skipped: this user reads a mode 000 file (root?), so no read can fail\n'
else
    run_gate gate
    assert_eq "$rc" "0" "unreadable input: the recipe still passes"
    assert_contains "$out" "could not hash inputs; the pass was NOT recorded" "unreadable input message"
    if [[ -e "$(sentinel_file gate)" ]]; then
        fail "a sentinel was recorded from a hash that skipped an unreadable file"
    fi
fi
chmod 644 "$repo/src/b.txt"

echo "=== tool versions are folded into the hash ==="
mk_consumer
run_gate_tools gate "echo v1"
run_gate_tools gate "echo v1"
assert_eq "$(runs)" "1" "same versions: cached"
run_gate_tools gate "echo v2"
assert_eq "$(runs)" "2" "a changed version reruns"
run_gate_tools gate "echo v2"
assert_eq "$(runs)" "2" "the new versions are cached in turn"
run_gate_tools gate $'echo v2\necho second-tool 1'
assert_eq "$(runs)" "3" "a second listed tool reruns"
run_gate_tools gate $'echo v2\necho second-tool 2'
assert_eq "$(runs)" "4" "a change in the second listed tool reruns"
run_gate_tools gate ""
assert_eq "$(runs)" "5" "dropping the list reruns"
run_gate_tools gate ""
assert_eq "$(runs)" "5" "an empty list is a valid, cached configuration"

echo "=== the list is read as one command per line, run through a shell ==="
mk_consumer
run_gate gate
assert_eq "$(runs)" "1" "the exported default list (two commands) hashes"
run_gate gate
assert_eq "$(runs)" "1" "the exported default list caches"
run_gate_tools gate "printf '%s\n' two words"
assert_eq "$(runs)" "2" "a command with quoting and arguments hashes"

echo "=== a second gate in one recipe body is refused ==="
mk_consumer
run_gate twice
assert_nonzero "$rc" "second gate in one body"
assert_contains "$out" "each gate needs its own recipe" "second gate message"
assert_contains "$(cat "$runlog")" "first" "the first gate's checks ran"
assert_not_contains "$(cat "$runlog")" "second" "the second gate's checks did not"

echo "=== a record with no guard is refused ==="
mk_consumer
run_gate bare
assert_nonzero "$rc" "record without a guard"
assert_contains "$out" "record-sentinel" "record without a guard names the function"
assert_contains "$out" "sentinel-guard" "record without a guard names the missing guard"

echo "=== a guard with no pathspec is refused ==="
mk_consumer
run_gate nopaths
assert_nonzero "$rc" "guard with no pathspec"
assert_contains "$out" "at least one pathspec" "no-pathspec message"
assert_eq "$(runs)" "0" "no checks ran"

echo "=== a pathspec that matches nothing is refused, and named ==="
mk_consumer
run_gate typo
assert_nonzero "$rc" "pathspec matching nothing"
assert_contains "$out" "'srcs'" "the message names the pathspec"
assert_not_contains "$out" "'src/none'" "an exclude pathspec is not held to matching a file"
assert_eq "$(runs)" "0" "no checks ran"

echo "=== only an exclude pathspec is exempt from matching a file ==="
mk_consumer
run_gate typoglob
assert_nonzero "$rc" "a positive pathspec whose text says exclude"
assert_contains "$out" "':(glob)excluded/**'" "the message names the pathspec"
assert_eq "$(runs)" "0" "no checks ran"
mk_consumer
run_gate forms
assert_eq "$rc" "0" "every exclude spelling is exempt ($out)"
assert_eq "$(runs)" "1" "the exclude spellings run the checks"
for form in topbang topcaret; do
    mk_consumer
    run_gate "$form"
    assert_eq "$rc" "0" "the short top-anchored exclude spelling $form is exempt ($out)"
    assert_eq "$(runs)" "1" "$form runs the checks"
done

echo "=== the match check stops at the first file ==="
# A shim `git` logs how each `ls-files` exited. A listing longer than the pipe
# buffer is cut short by a reader that stops at the first file, and git then
# dies of SIGPIPE: 141.
mk_consumer
mkdir -p "$repo/src/big" "$sandbox/shim"
for i in $(seq 1 3000); do : > "$repo/src/big/a-file-with-a-longish-name-$i.txt"; done
cat > "$sandbox/shim/git" <<'SHIM'
#!/bin/bash
rc=0
"$REAL_GIT" "$@" || rc=$?
[ "$1" != ls-files ] || echo "ls-files $rc" >> "$GIT_LOG"
exit "$rc"
SHIM
chmod +x "$sandbox/shim/git"
: > "$sandbox/git.log"
run_gate gate "PATH=$sandbox/shim:$PATH" "REAL_GIT=$(command -v git)" "GIT_LOG=$sandbox/git.log"
assert_eq "$rc" "0" "a gate over a large tree: exit status ($out)"
assert_contains "$(cat "$sandbox/git.log")" "ls-files 141" "the match check closed its listing at the first file"

echo "=== a gate name that is a path is refused ==="
mk_consumer
run_gate badname
assert_nonzero "$rc" "gate name with a slash"
assert_contains "$out" "gate name" "bad-name message"
assert_eq "$(runs)" "0" "no checks ran"
if [[ -e "$repo/.git/plugin-dev/escape" ]]; then
    fail "a sentinel escaped the gate directory"
fi

echo "=== outside a git repository the guard refuses and writes nothing ==="
mk_consumer
mkdir "$sandbox/nogit"
cp "$repo/justfile" "$sandbox/nogit/justfile"
cp -R "$repo/plugin-dev" "$sandbox/nogit/plugin-dev"
rc=0
out="$(cd "$sandbox/nogit" && env RUN_LOG="$runlog" GIT_CEILING_DIRECTORIES="$sandbox" just gate 2>&1)" || rc=$?
assert_nonzero "$rc" "guard outside a repository"
assert_eq "$(runs)" "0" "no checks ran outside a repository"
if [[ -e "/gate" ]]; then
    fail "a sentinel was written at the filesystem root"
fi

echo "=== the prolog passes shellcheck ==="
mk_consumer
prolog="$(cd "$repo" && just --evaluate plugin_dev_gate_prolog)"
# The first line is the interpreter, which the shebang would consume.
body="$(printf '#!/usr/bin/env bash\n%s\n' "$(tail -n +2 <<<"$prolog")")"
sc_out="$(shellcheck -s bash - <<<"$body" 2>&1)" || fail "shellcheck found problems in the prolog:
$sc_out"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\ngates guards ok (moved inputs, unhashable, tool versions, one gate per body, misuse, unmatched pathspec, exclude spellings, first-file match, unreadable input, shellcheck)\n'

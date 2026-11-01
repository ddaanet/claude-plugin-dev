#!/usr/bin/env bash
# End-to-end tests of install.sh, the initial `git subtree add` call site,
# against real git repos in a temp dir: vendoring, ref refusal, no-ref
# resolution, and the settings.json / justfile wiring. No network: the toolkit
# and its "memory" submodule are local bare repos. The update-side call site
# lives in update-plugin-dev-test.sh.
#
# Scope: vendoring -- into a consumer that mounts its own memory submodule, the
# refusal of a ref outside the dist lineage, no-ref resolution, and the settings
# a fresh install writes. Its siblings install-settings-test.sh and
# install-legacy-test.sh cover wiring into an existing settings.json and the
# legacy-entry migration.
#
# Usage: bash tests/install-vendor-test.sh   (run from repo root)
set -euo pipefail

# See release-core-test.sh's identical comment: an enclosing `git commit` leaks
# GIT_DIR/GIT_INDEX_FILE/etc. into this process. Every git command below
# targets a synthetic fixture repo via `-C`, never this repo, so it's always
# safe to drop them here.
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
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}

sandboxes=()
cleanup() {
    local s
    for s in "${sandboxes[@]:-}"; do
        [ -n "$s" ] && rm -rf "$s"
    done
}
trap cleanup EXIT

# Recursive submodule transports (add/subtree's on-demand submodule fetch)
# default protocol.file.allow to "user", which local bare-repo fixtures still
# trip on. Every git call below targets local paths only, so allow it broadly
# instead of threading `-c` through each call site.
allow_file() {
    env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always "$@"
}

git_id() {
    git -C "$1" config user.email test@example.com
    git -C "$1" config user.name "Toolkit Test"
    git -C "$1" config commit.gpgsign false
}

# out/rc from the last run_in call.
out=""
rc=0
run_in() {
    # $1=dir, rest=command. Captures stdout+stderr in $out, status in $rc.
    local dir="$1"
    shift
    set +e
    out="$(cd "$dir" && "$@" 2>&1)"
    rc=$?
    set -e
}

# The consumer-visible half of the leak: an unregistered gitlink under
# plugin-dev/ fatals a bare `git submodule status` for the WHOLE repo, even
# though every submodule the consumer itself registered is fine. Asserted on
# both call sites, since either can be the one that vendors.
assert_clean_vendor() {
    # $1=consumer dir, $2=label
    # Captured, then searched: piped into grep -q under pipefail, git can take
    # SIGPIPE on an early match and a present gitlink would read as absent.
    local vendor_index
    vendor_index="$(git -C "$1" ls-files -s plugin-dev/)"
    if grep -q '^160000' <<<"$vendor_index"; then
        fail "$2: vendored tree carries a gitlink"
    fi
    run_in "$1" git submodule status
    assert_eq "$rc" "0" "$2: consumer's bare git submodule status stays clean"
}

# Advances the fixture toolkit repo (shaped like this repo: a `memory`
# submodule mounted at top level, consumer-facing files under toolkit/) by one
# commit and cuts both tags a real toolkit release cuts.
make_toolkit_release() {
    local toolkit="$1" tag="$2" version="$3" dist_sha
    mkdir -p "$toolkit/toolkit"
    printf '%s\n' "$version" > "$toolkit/toolkit/VERSION"
    git -C "$toolkit" add -A
    git -C "$toolkit" commit -qm "toolkit: $version"
    git -C "$toolkit" tag "$tag"
    # The dist tag is what consumers vendor: `git subtree split --prefix=toolkit`
    # yields a ref whose ROOT is toolkit/, so it carries neither the `memory`
    # gitlink nor anything else from the toolkit's working environment.
    dist_sha="$(git -C "$toolkit" subtree split -q --prefix=toolkit | tail -1)"
    git -C "$toolkit" tag "dist-$tag" "$dist_sha"
}

new_sandbox() {
    # Sets $sandbox, $toolkit, $consumer.
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/install-vendor.XXXXXX")"
    sandboxes+=("$sandbox")
    toolkit="$sandbox/toolkit"
    consumer="$sandbox/consumer"

    # The two memory remotes are kept distinct (different seed messages, so
    # different shas) to keep the toolkit's gitlink and the consumer's
    # unrelated: assert_clean_vendor has to tell "the toolkit's memory was
    # dropped" apart from "the consumer's memory survived", which it cannot do
    # if both name the same object.

    # Toolkit-side memory remote, standing in for claude-plugin-dev-memory.git.
    git init -q --bare -b main "$sandbox/toolkit-memory-origin.git"
    local seed
    seed="$(mktemp -d "${TMPDIR:-/tmp}/install-vendor.XXXXXX")"
    git init -q -b main "$seed"
    git_id "$seed"
    git -C "$seed" commit --allow-empty -qm "seed: toolkit memory"
    git -C "$seed" remote add origin "$sandbox/toolkit-memory-origin.git"
    git -C "$seed" push -q -u origin main
    rm -rf "$seed"

    git init -q -b main "$toolkit"
    git_id "$toolkit"
    git -C "$toolkit" commit --allow-empty -qm init
    allow_file git -C "$toolkit" submodule add -q "$sandbox/toolkit-memory-origin.git" memory
    git -C "$toolkit" commit -qm "toolkit: mount memory"
    make_toolkit_release "$toolkit" v1 1.0.0

    # Consumer-side memory remote: unrelated to the toolkit's, same path.
    git init -q --bare -b main "$sandbox/consumer-memory-origin.git"
    seed="$(mktemp -d "${TMPDIR:-/tmp}/install-vendor.XXXXXX")"
    git init -q -b main "$seed"
    git_id "$seed"
    git -C "$seed" commit --allow-empty -qm "seed: consumer memory"
    git -C "$seed" remote add origin "$sandbox/consumer-memory-origin.git"
    git -C "$seed" push -q -u origin main
    rm -rf "$seed"

    git init -q -b main "$consumer"
    git_id "$consumer"
    git -C "$consumer" commit --allow-empty -qm init
}

echo "=== install.sh: vendors into a consumer that already mounts a memory submodule ==="
new_sandbox

# The reverse ordering: an existing plugin repo that mounted its gitlore
# memory submodule before adopting the toolkit. install.sh's `subtree add`
# performs the same raw, unprefixed fetch of the toolkit's history as
# `subtree pull`, so it hits the same on-demand recursion collision unless
# scoped the same way.
run_in "$consumer" allow_file git submodule add -q "$sandbox/consumer-memory-origin.git" memory
assert_eq "$rc" "0" "consumer memory submodule mount exit code"
git -C "$consumer" commit -qm "consumer: mount memory"

# install.sh's run-in-target guard needs a plugin manifest in the cwd.
mkdir -p "$consumer/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
git -C "$consumer" add .claude-plugin/plugin.json
git -C "$consumer" commit -qm "consumer: plugin manifest"

run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh" dist-v1
assert_eq "$rc" "0" "install.sh exit code"
# Only `just dogfood` creates the copy, and a launch without one starts without
# the plugin, so the next steps name it.
assert_contains "$out" "just dogfood" "install.sh's next steps create the copy"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.0" "install.sh vendored VERSION"
assert_eq "$(git -C "$consumer" config --get submodule.memory.url)" \
    "$sandbox/consumer-memory-origin.git" "consumer's own memory submodule registration untouched"
assert_clean_vendor "$consumer" "install.sh"

echo "=== install.sh refuses any ref outside the dist lineage ==="
new_sandbox

# install.sh's run-in-target guard needs a plugin manifest in the cwd.
mkdir -p "$consumer/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
git -C "$consumer" add .claude-plugin/plugin.json
git -C "$consumer" commit -qm "consumer: plugin manifest"

# A source tag resolves to the toolkit's ROOT tree -- its memory gitlink,
# .claude/, CLAUDE.md, its own justfile. Vendoring one is the leak this whole
# design exists to stop, and it is silent, so the call site must refuse it
# rather than warn. This is what makes the fetch-recursion collision
# unreachable, so it is asserted rather than assumed.
run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh" v1
if [ "$rc" -eq 0 ]; then fail "install.sh accepted a source tag"; fi
assert_contains "$out" "dist-v1" "install.sh refusal names the dist tag to use"
if [ -d "$consumer/plugin-dev" ]; then fail "install.sh vendored despite refusing the ref"; fi

echo "=== install.sh: no ref resolves the newest dist tag ==="
new_sandbox
make_toolkit_release "$toolkit" v2 1.0.1

mkdir -p "$consumer/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
git -C "$consumer" add .claude-plugin/plugin.json
git -C "$consumer" commit -qm "consumer: plugin manifest"

if [ -e "$consumer/.claude/settings.json" ]; then fail "anchor: the no-ref fixture already has a settings.json"; fi
run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh"
assert_eq "$rc" "0" "no-ref install exit code"

# The three commands, shared with the existing-settings scenario below.
# Claude Code expands ${CLAUDE_PROJECT_DIR} at hook-fire time, so the commands
# must land in settings.json with the variable literal, all three inside double
# quotes so a project path with a space survives the hook shell. vg_cmd's
# earlier unquoted spelling, legacy_cmd, is migrated by the installer, never
# preserved: the scenarios on it come after the existing-settings one.
# shellcheck disable=SC2016  # the ${...} is meant literal
vg_cmd='bash "${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh"'
# shellcheck disable=SC2016
legacy_cmd='bash ${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh'
# shellcheck disable=SC2016
pretool_cmd='bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" pre-tool'
# shellcheck disable=SC2016
session_cmd='bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" session-start'
# One matcher=command line per hook, sorted: the order entries land in is not
# part of the contract, a missing, extra or mis-scoped hook is.
fresh_json="$consumer/.claude/settings.json"
assert_eq "$(jq -r '[.hooks.PreToolUse[]? | .matcher as $m | .hooks[]? | "\($m)=\(.command)"] | sort | join("\n")' "$fresh_json")" \
    "Write|Edit=$vg_cmd
Write|Edit|NotebookEdit=$pretool_cmd" "a fresh settings.json carries version-guard and the pre-tool hook under PreToolUse"
assert_eq "$(jq -r '[.hooks.SessionStart[]? | (if has("matcher") then "matcher" else "none" end) + "=" + (.hooks[]? | .command)] | join("\n")' "$fresh_json")" \
    "none=$session_cmd" "a fresh settings.json carries the session-start hook with no matcher"
assert_contains "$out" "dist-v2" "no-ref install names the resolved tag"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.1" "no-ref install vendored the newest VERSION"

# Same failure path on the install side, from a fresh consumer (install.sh
# only resolves when plugin-dev/ is absent).
consumer2="$sandbox/consumer2"
git init -q -b main "$consumer2"
git_id "$consumer2"
git -C "$consumer2" commit --allow-empty -qm init
mkdir -p "$consumer2/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer2/.claude-plugin/plugin.json"
git -C "$consumer2" add .claude-plugin/plugin.json
git -C "$consumer2" commit -qm "consumer: plugin manifest"
git init -q --bare -b main "$sandbox/tagless.git"
run_in "$consumer2" allow_file env TOOLKIT_URL="$sandbox/tagless.git" bash "$repo_root/toolkit/install.sh"
if [ "$rc" -eq 0 ]; then fail "no-ref install succeeded against a tagless remote"; fi
assert_contains "$out" "dist-vX.Y.Z" "install tagless-remote refusal names the explicit-ref fallback"

# A freshly `git init`-ed plugin has no HEAD, which makes `git diff HEAD` fail
# and used to read as "uncommitted changes". The refusal is right; the reason
# has to be the true one.
echo "=== install.sh: a repo with no commits is refused for that reason ==="
new_sandbox
unborn="$sandbox/unborn"
git init -q -b main "$unborn"
git_id "$unborn"
mkdir -p "$unborn/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$unborn/.claude-plugin/plugin.json"
run_in "$unborn" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh" dist-v1
if [ "$rc" -eq 0 ]; then fail "install.sh vendored into a repo with no commits"; fi
assert_contains "$out" "no commits" "unborn-HEAD refusal names the missing commit"
if grep -q "uncommitted changes" <<<"$out"; then fail "unborn-HEAD refusal is reported as dirty"; fi
if [ -d "$unborn/plugin-dev" ]; then fail "install.sh vendored despite refusing the unborn HEAD"; fi

# The repository-state refusals are local facts, so they come before the
# network read that resolves a missing ref: with an unreachable toolkit URL and
# no ref, the answer is still the true one.
echo "=== install.sh: repository-state refusals come before tag resolution ==="
gone="$sandbox/no-such-toolkit.git"
run_in "$unborn" allow_file env TOOLKIT_URL="$gone" bash "$repo_root/toolkit/install.sh"
assert_contains "$out" "no commits" "no-ref install in an unborn repo is refused for that reason"
if grep -q "could not resolve" <<<"$out"; then fail "no-ref install in an unborn repo went to the network first"; fi
dirty="$sandbox/dirty"
git init -q -b main "$dirty"
git_id "$dirty"
mkdir -p "$dirty/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$dirty/.claude-plugin/plugin.json"
git -C "$dirty" add .claude-plugin/plugin.json
git -C "$dirty" commit -qm "dirty fixture: manifest"
printf '{"name": "stub-plugin", "version": "0.2.0"}\n' > "$dirty/.claude-plugin/plugin.json"
run_in "$dirty" allow_file env TOOLKIT_URL="$gone" bash "$repo_root/toolkit/install.sh"
assert_contains "$out" "uncommitted changes" "no-ref install in a dirty repo is refused for that reason"
if grep -q "could not resolve" <<<"$out"; then fail "no-ref install in a dirty repo went to the network first"; fi

# Outside any repository the HEAD probe fails too, which used to read as
# "no commits yet".
echo "=== install.sh: a directory that is not a git repository says so ==="
norepo="$sandbox/norepo"
mkdir -p "$norepo/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$norepo/.claude-plugin/plugin.json"
run_in "$norepo" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh" dist-v1
if [ "$rc" -eq 0 ]; then fail "install.sh vendored outside a git repository"; fi
assert_contains "$out" "error: not a git repository" "non-repo refusal names the real problem in the installer's own words"
if grep -q "no commits" <<<"$out"; then fail "non-repo refusal is reported as an unborn HEAD"; fi

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\ninstall.sh vendoring scenarios passed\n'

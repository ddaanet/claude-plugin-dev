#!/usr/bin/env bash
# Tests install.sh's clean-tree guard against a moved gitlore memory pointer,
# the one dirt it lets through, as update.sh does: the submodule named
# gitlore-memory, at the path .gitmodules gives it (one holding a space here).
# An unstaged pointer installs and stays pending; a staged one installs, stays
# staged and is not in the vendoring commit; any other dirty tracked path still
# refuses. No network: the toolkit and both memory stores are local bare repos.
# The fixture is install-vendor-test.sh's.
#
# Usage: bash tests/install-memory-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/install-memory.XXXXXX")"
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
    seed="$(mktemp -d "${TMPDIR:-/tmp}/install-memory.XXXXXX")"
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
    seed="$(mktemp -d "${TMPDIR:-/tmp}/install-memory.XXXXXX")"
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

mem="the memory"

# new_consumer: a sandbox whose consumer mounts its store as gitlore names it,
# carries a plugin manifest and a tracked README, and then moves the store one
# commit ahead of the recorded gitlink. Sets $recorded and $moved, the two shas.
new_consumer() {
    new_sandbox
    run_in "$consumer" allow_file git submodule add -q --name gitlore-memory \
        "$sandbox/consumer-memory-origin.git" "$mem"
    assert_eq "$rc" "0" "mount the store ($out)"
    mkdir -p "$consumer/.claude-plugin"
    printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
    printf 'readme\n' > "$consumer/README.md"
    git -C "$consumer" add .claude-plugin/plugin.json README.md
    git -C "$consumer" commit -qm "consumer: mount memory, manifest"
    recorded="$(git -C "$consumer" rev-parse "HEAD:$mem")"
    git_id "$consumer/$mem"
    git -C "$consumer/$mem" commit --allow-empty -qm "a fact"
    moved="$(git -C "$consumer/$mem" rev-parse HEAD)"
}

install() {
    run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh" dist-v1
}

echo "=== an unstaged moved pointer installs and stays pending ==="
new_consumer
install
assert_eq "$rc" "0" "unstaged pointer: install exit code ($out)"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.0" "unstaged pointer: vendored"
assert_eq "$(git -C "$consumer" rev-parse "HEAD:$mem")" "$recorded" "unstaged pointer: HEAD keeps the recorded gitlink"
assert_eq "$(git -C "$consumer" diff --name-only)" "$mem" "unstaged pointer: still pending in the worktree"
assert_eq "$(git -C "$consumer" diff --cached --name-only)" "" "unstaged pointer: nothing staged"

echo "=== a staged pointer installs, stays staged, and is not in the vendoring commit ==="
new_consumer
git -C "$consumer" add "$mem"
install
assert_eq "$rc" "0" "staged pointer: install exit code ($out)"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.0" "staged pointer: vendored"
assert_eq "$(git -C "$consumer" rev-parse "HEAD:$mem")" "$recorded" "staged pointer: HEAD keeps the recorded gitlink"
assert_eq "$(git -C "$consumer" rev-parse ":$mem")" "$moved" "staged pointer: the index holds the moved sha"
assert_eq "$(git -C "$consumer" diff --cached --name-only)" "$mem" "staged pointer: nothing else staged"

echo "=== another dirty tracked path still refuses ==="
new_consumer
printf 'edited\n' >> "$consumer/README.md"
install
if [ "$rc" -eq 0 ]; then fail "dirty README: install succeeded"; fi
assert_contains "$out" "uncommitted changes" "dirty README: the refusal says why"
if [ -d "$consumer/plugin-dev" ]; then fail "dirty README: vendored despite refusing"; fi

echo "=== a tracked path staged and then reverted still refuses ==="
new_consumer
printf 'edited\n' >> "$consumer/README.md"
git -C "$consumer" add README.md
git -C "$consumer" show HEAD:README.md > "$consumer/README.md"
install
if [ "$rc" -eq 0 ]; then fail "staged README: install succeeded"; fi
assert_contains "$out" "uncommitted changes" "staged README: the refusal says why"
if [ -d "$consumer/plugin-dev" ]; then fail "staged README: vendored despite refusing"; fi

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\ninstall memory ok (unstaged pointer, staged pointer, dirty path, staged-then-reverted path)\n'

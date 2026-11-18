#!/usr/bin/env bash
# End-to-end tests of update.sh, through release.just's `update-plugin-dev`
# recipe, when the consumer's `memory` gitlink has moved past HEAD: the pointer
# is taken out of the way rather than refused, into an unpushed HEAD by amend,
# or past a pushed one by a commit folded into the subtree merge. Any other
# dirt still refuses, before anything is committed. The rest of the recipe is
# covered by update-plugin-dev-test.sh.
#
# Usage: bash tests/update-plugin-dev-memory-test.sh   (run from repo root)
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

# Submodule add from a local bare repo trips protocol.file.allow's "user"
# default. Every git call below targets local paths only.
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

# Advances the fixture toolkit by one commit and cuts its source and dist tags,
# shipping the real update.sh under test, since the vendored copy is the one a
# consumer's update executes.
make_toolkit_release() {
    local toolkit="$1" tag="$2" version="$3" dist_sha
    mkdir -p "$toolkit/toolkit"
    printf '%s\n' "$version" > "$toolkit/toolkit/VERSION"
    cp "$repo_root/toolkit/update.sh" "$toolkit/toolkit/"
    git -C "$toolkit" add -A
    git -C "$toolkit" commit -qm "toolkit: $version"
    git -C "$toolkit" tag "$tag"
    dist_sha="$(git -C "$toolkit" subtree split -q --prefix=toolkit | tail -1)"
    git -C "$toolkit" tag "dist-$tag" "$dist_sha"
}

new_sandbox() {
    # $1=submodule name, default gitlore-memory, the name gitlore mounts its
    # store under. Sets $sandbox, $toolkit, $consumer. The consumer has
    # vendored dist-v1, mounted its own memory submodule at `memory`, committed both with NOTES.md and a justfile
    # importing this repo's real release.just, and pushed main to a bare
    # origin; dist-v2 is cut and not yet pulled. Nothing is dirty yet.
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/update-plugin-dev-memory.XXXXXX")"
    sandboxes+=("$sandbox")
    toolkit="$sandbox/toolkit"
    consumer="$sandbox/consumer"

    git init -q -b main "$toolkit"
    git_id "$toolkit"
    git -C "$toolkit" commit --allow-empty -qm init
    make_toolkit_release "$toolkit" v1 1.0.0

    git init -q --bare -b main "$sandbox/memory-origin.git"
    local seed="$sandbox/seed"
    git init -q -b main "$seed"
    git_id "$seed"
    git -C "$seed" commit --allow-empty -qm "seed: consumer memory"
    git -C "$seed" push -q "$sandbox/memory-origin.git" main

    git init -q --bare -b main "$sandbox/consumer-origin.git"
    git init -q -b main "$consumer"
    git_id "$consumer"
    git -C "$consumer" commit --allow-empty -qm init
    allow_file git -C "$consumer" subtree add -q --prefix=plugin-dev "$toolkit" dist-v1 --squash
    allow_file git -C "$consumer" submodule add -q --name "${1:-gitlore-memory}" "$sandbox/memory-origin.git" memory
    git_id "$consumer/memory"
    printf "import '%s/toolkit/release.just'\n\nprecommit:\n    @echo stub-precommit\n\nprerelease: precommit\n" \
        "$repo_root" > "$consumer/justfile"
    printf 'notes\n' > "$consumer/NOTES.md"
    git -C "$consumer" add -A
    git -C "$consumer" commit -qm "consumer: memory + justfile"
    git -C "$consumer" remote add origin "$sandbox/consumer-origin.git"
    git -C "$consumer" push -q -u origin main

    make_toolkit_release "$toolkit" v2 1.0.1
}

move_memory_pointer() {
    # Commits inside the consumer's memory submodule, so the gitlink differs
    # from HEAD's and nothing else is dirty. Prints the new memory sha.
    git -C "$consumer/memory" commit --allow-empty -qm "memory: new fact"
    git -C "$consumer/memory" rev-parse HEAD
}

update() {
    run_in "$consumer" allow_file just --set toolkit_url "$toolkit" update-plugin-dev "$@"
}

assert_tree_clean() {
    # $1=label. Both of git subtree's own checks: worktree and index.
    if ! git -C "$consumer" diff-index --quiet HEAD; then fail "$1: worktree dirty after update"; fi
    if ! git -C "$consumer" diff-index --quiet --cached HEAD; then fail "$1: index dirty after update"; fi
}

echo "=== update-plugin-dev: a moved memory pointer is amended into an unpushed HEAD ==="
new_sandbox
git -C "$consumer" commit --allow-empty -qm "consumer: local work"
local_parent="$(git -C "$consumer" rev-parse HEAD^)"
new_memory="$(move_memory_pointer)"

update dist-v2
assert_eq "$rc" "0" "unpushed: update exit code"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.1" "unpushed: VERSION pulled"
assert_eq "$(git -C "$consumer" log -1 --format=%s HEAD^1 2>/dev/null)" "consumer: local work" \
    "unpushed: the merge's first parent is the amended local commit"
assert_eq "$(git -C "$consumer" rev-parse HEAD^1^ 2>/dev/null)" "$local_parent" \
    "unpushed: the amend kept the local commit's parent"
assert_eq "$(git -C "$consumer" rev-parse HEAD^1:memory 2>/dev/null)" "$new_memory" \
    "unpushed: the amended commit records the new memory pointer"
assert_tree_clean "unpushed"

echo "=== update-plugin-dev: a moved memory pointer is folded into the merge past a pushed HEAD ==="
new_sandbox
base="$(git -C "$consumer" rev-parse HEAD)"
new_memory="$(move_memory_pointer)"

update dist-v2
assert_eq "$rc" "0" "pushed: update exit code"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.1" "pushed: VERSION pulled"
assert_eq "$(git -C "$consumer" rev-list --parents -n1 HEAD | wc -w | tr -d ' ')" "3" \
    "pushed: HEAD is a two-parent merge"
assert_eq "$(git -C "$consumer" rev-parse HEAD^1)" "$base" \
    "pushed: the merge's first parent is the pushed HEAD, no pointer commit between"
assert_contains "$(git -C "$consumer" log -1 --format=%s HEAD^2 2>/dev/null)" "^Squashed 'plugin-dev/' changes from" \
    "pushed: the merge's second parent is the squash commit"
assert_contains "$(git -C "$consumer" log -1 --format=%s HEAD)" "^Merge commit '" \
    "pushed: the merge keeps git subtree's message"
assert_eq "$(git -C "$consumer" rev-parse HEAD:memory)" "$new_memory" \
    "pushed: the merge records the new memory pointer"
assert_tree_clean "pushed"

echo "=== update-plugin-dev: an already-current pull past a pushed HEAD leaves the pointer as it was ==="
new_sandbox
update dist-v2
assert_eq "$rc" "0" "no-op: first update exit code"
before="$(git -C "$consumer" rev-parse HEAD)"
git -C "$consumer" push -q origin main
new_memory="$(move_memory_pointer)"

update dist-v2
assert_eq "$rc" "0" "no-op: second update exit code"
assert_eq "$(git -C "$consumer" rev-parse HEAD)" "$before" "no-op: HEAD unmoved, no pointer commit left behind"
if git -C "$consumer" diff --quiet HEAD -- memory; then
    fail "no-op: the moved memory pointer is no longer pending"
fi

echo "=== update-plugin-dev: a ref missing from the remote refuses before the pointer is committed ==="
new_sandbox
git -C "$consumer" commit --allow-empty -qm "consumer: local work"
before="$(git -C "$consumer" rev-parse HEAD)"
move_memory_pointer > /dev/null

update dist-v9
if [ "$rc" -eq 0 ]; then fail "missing ref: update succeeded"; fi
assert_contains "$out" "not found" "missing ref: refusal names the cause"
assert_eq "$(git -C "$consumer" rev-parse HEAD)" "$before" "missing ref: HEAD untouched"
if git -C "$consumer" diff --quiet HEAD -- memory; then
    fail "missing ref: the moved memory pointer is no longer pending"
fi

echo "=== update-plugin-dev: a local tag on the unpushed HEAD is not stranded by the pointer ==="
new_sandbox
git -C "$consumer" commit --allow-empty -qm "consumer: tagged work"
tagged="$(git -C "$consumer" rev-parse HEAD)"
git -C "$consumer" tag t
move_memory_pointer > /dev/null

update dist-v2
assert_eq "$rc" "0" "tagged: update exit code"
assert_eq "$(git -C "$consumer" rev-parse t)" "$tagged" "tagged: the tag still names its commit"
if ! git -C "$consumer" merge-base --is-ancestor t HEAD; then
    fail "tagged: the tag is not an ancestor of HEAD"
fi
assert_eq "$(git -C "$consumer" rev-parse HEAD^1 2>/dev/null)" "$tagged" \
    "tagged: the merge's first parent is the tagged commit, not an amend of it"
assert_tree_clean "tagged"

echo "=== update-plugin-dev: a moved memory pointer beside other dirt refuses before committing ==="
new_sandbox
before="$(git -C "$consumer" rev-parse HEAD)"
move_memory_pointer > /dev/null
printf 'edited\n' >> "$consumer/NOTES.md"

update dist-v2
if [ "$rc" -eq 0 ]; then fail "other dirt: update succeeded"; fi
assert_contains "$out" "uncommitted changes" "other dirt: refusal names the cause"
assert_eq "$(git -C "$consumer" rev-parse HEAD)" "$before" "other dirt: HEAD untouched"

echo "=== update-plugin-dev: a memory submodule with uncommitted content refuses before committing ==="
new_sandbox
before="$(git -C "$consumer" rev-parse HEAD)"
move_memory_pointer > /dev/null
printf 'fact\n' > "$consumer/memory/fact.md"
git -C "$consumer/memory" add fact.md

update dist-v2
if [ "$rc" -eq 0 ]; then fail "dirty memory: update succeeded"; fi
assert_contains "$out" "uncommitted changes" "dirty memory: refusal names the cause"
assert_eq "$(git -C "$consumer" rev-parse HEAD)" "$before" "dirty memory: HEAD untouched"

echo "=== update-plugin-dev: a moved submodule at memory under another name refuses ==="
# The store is found by gitlore's submodule name, not by the path it is
# usually mounted at: any other submodule's moved gitlink is unfinished work.
new_sandbox notes
before="$(git -C "$consumer" rev-parse HEAD)"
move_memory_pointer > /dev/null

update dist-v2
if [ "$rc" -eq 0 ]; then fail "other submodule: update succeeded"; fi
assert_contains "$out" "uncommitted changes" "other submodule: refusal names the cause"
assert_eq "$(git -C "$consumer" rev-parse HEAD)" "$before" "other submodule: HEAD untouched"

echo "=== update-plugin-dev: a memory checkout behind HEAD's pointer is moved up to it, nothing committed ==="
# A parent pull that does not update the submodule leaves the checkout behind
# the commit HEAD records. Committing that pointer would rewind the store.
new_sandbox
recorded="$(move_memory_pointer)"
git -C "$consumer" add memory
git -C "$consumer" commit -qm "consumer: memory moved"
before="$(git -C "$consumer" rev-parse HEAD)"
git -C "$consumer/memory" checkout -q HEAD^

update dist-v2
assert_eq "$rc" "0" "behind: update exit code"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.1" "behind: VERSION pulled"
assert_eq "$(git -C "$consumer/memory" rev-parse HEAD)" "$recorded" "behind: checkout moved up to the recorded commit"
assert_eq "$(git -C "$consumer" rev-parse HEAD^1)" "$before" "behind: no commit rewritten or added before the merge"
assert_tree_clean "behind"

echo "=== update-plugin-dev: a memory checkout diverged from HEAD's pointer refuses ==="
new_sandbox
move_memory_pointer > /dev/null
git -C "$consumer" add memory
git -C "$consumer" commit -qm "consumer: memory moved"
before="$(git -C "$consumer" rev-parse HEAD)"
git -C "$consumer/memory" checkout -q HEAD^
git -C "$consumer/memory" commit --allow-empty -qm "memory: side fact"
side="$(git -C "$consumer/memory" rev-parse HEAD)"

update dist-v2
if [ "$rc" -eq 0 ]; then fail "diverged: update succeeded"; fi
assert_contains "$out" "diverged" "diverged: refusal names the cause"
assert_eq "$(git -C "$consumer" rev-parse HEAD)" "$before" "diverged: HEAD untouched"
assert_eq "$(git -C "$consumer/memory" rev-parse HEAD)" "$side" "diverged: memory checkout untouched"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nupdate-plugin-dev memory-pointer scenarios passed\n'

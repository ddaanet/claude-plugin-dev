#!/usr/bin/env bash
# End-to-end tests of update.sh, through release.just's `update-plugin-dev`
# recipe, when the consumer's gitlore memory gitlink differs from HEAD's: the
# update commits nothing of it and leaves the checkout and the pointer, staged
# or not, as they were. Any other tracked change, staged or not, refuses. The
# rest of the recipe is covered by update-plugin-dev-test.sh.
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

# The fixture toolkit is only ever read from, so every scenario shares one,
# with dist-v1 and dist-v2 both cut: its subtree splits are the slowest setup.
toolkit_dir="$(mktemp -d "${TMPDIR:-/tmp}/update-plugin-dev-memory-toolkit.XXXXXX")"
sandboxes+=("$toolkit_dir")
toolkit="$toolkit_dir/toolkit"
git init -q -b main "$toolkit"
git_id "$toolkit"
git -C "$toolkit" commit --allow-empty -qm init
make_toolkit_release "$toolkit" v1 1.0.0
make_toolkit_release "$toolkit" v2 1.0.1

new_sandbox() {
    # $1=submodule name, default gitlore-memory, the name gitlore mounts its
    # store under; $2=its path, default memory. Sets $sandbox, $consumer and
    # $mem. The consumer has vendored dist-v1, mounted its own memory submodule
    # at $mem, committed both with NOTES.md and a justfile
    # importing this repo's real release.just, and pushed main to a bare
    # origin; dist-v2 is not yet pulled. Nothing is dirty yet.
    mem="${2:-memory}"
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/update-plugin-dev-memory.XXXXXX")"
    sandboxes+=("$sandbox")
    consumer="$sandbox/consumer"

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
    allow_file git -C "$consumer" submodule add -q --name "${1:-gitlore-memory}" "$sandbox/memory-origin.git" "$mem"
    git_id "$consumer/$mem"
    printf "import '%s/toolkit/release.just'\n\nprecommit:\n    @echo stub-precommit\n\nprerelease: precommit\n" \
        "$repo_root" > "$consumer/justfile"
    printf 'notes\n' > "$consumer/NOTES.md"
    git -C "$consumer" add -A
    git -C "$consumer" commit -qm "consumer: memory + justfile"
    git -C "$consumer" remote add origin "$sandbox/consumer-origin.git"
    git -C "$consumer" push -q -u origin main
}

move_memory_pointer() {
    # Commits inside the consumer's memory submodule, so the gitlink differs
    # from HEAD's and nothing else is dirty. Prints the new memory sha.
    git -C "$consumer/$mem" commit --allow-empty -qm "memory: new fact"
    git -C "$consumer/$mem" rev-parse HEAD
}

update() {
    run_in "$consumer" allow_file just --set toolkit_url "$toolkit" update-plugin-dev "$@"
}

snapshot() {
    # HEAD, status and the index's tree: what a refused update must not move.
    printf '%s\n%s\n%s\n' "$(git -C "$consumer" rev-parse HEAD)" \
        "$(git -C "$consumer" status --porcelain)" "$(git -C "$consumer" write-tree)"
}

assert_pointer_left() {
    # $1=label, $2=HEAD:memory before, $3=status before, $4=checkout sha before.
    # The update succeeded, committed no pointer, and moved nothing of the store.
    assert_eq "$rc" "0" "$1: update exit code"
    assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.1" "$1: VERSION pulled"
    assert_eq "$(git -C "$consumer" rev-parse "HEAD:$mem")" "$2" "$1: the merge records HEAD's old pointer"
    assert_eq "$(git -C "$consumer" status --porcelain -- "$mem")" "$3" "$1: the pointer's status is unchanged"
    assert_eq "$(git -C "$consumer/$mem" rev-parse HEAD)" "$4" "$1: the memory checkout is unmoved"
}

pointer_case() {
    # $1=label; a sandbox is ready and the store is arranged. Runs the update
    # and checks the pointer was left as it was.
    local old status checkout
    old="$(git -C "$consumer" rev-parse "HEAD:$mem")"
    status="$(git -C "$consumer" status --porcelain -- "$mem")"
    checkout="$(git -C "$consumer/$mem" rev-parse HEAD)"
    update dist-v2
    assert_pointer_left "$1" "$old" "$status" "$checkout"
}

echo "=== update-plugin-dev: a pointer ahead of HEAD stays pending, uncommitted ==="
new_sandbox
move_memory_pointer > /dev/null
pointer_case "ahead"

echo "=== update-plugin-dev: a staged pointer stays staged and out of the merge ==="
new_sandbox
new_memory="$(move_memory_pointer)"
git -C "$consumer" add "$mem"
pointer_case "staged"
assert_eq "$(git -C "$consumer" rev-parse ":$mem")" "$new_memory" "staged: the same sha is staged afterwards"

echo "=== update-plugin-dev: a staged sha behind the checkout's is the one restored ==="
new_sandbox
staged_memory="$(move_memory_pointer)"
git -C "$consumer" add "$mem"
move_memory_pointer > /dev/null
pointer_case "staged-differs"
assert_eq "$(git -C "$consumer" rev-parse ":$mem")" "$staged_memory" "staged-differs: the staged sha survives, not the checkout's"

echo "=== update-plugin-dev: a failed pull leaves a staged pointer staged ==="
new_sandbox
new_memory="$(move_memory_pointer)"
git -C "$consumer" add "$mem"
before="$(snapshot)"
update dist-v9
if [ "$rc" -eq 0 ]; then fail "failed pull: update succeeded"; fi
assert_eq "$(snapshot)" "$before" "failed pull: HEAD, status and index unchanged"
assert_eq "$(git -C "$consumer" rev-parse ":$mem")" "$new_memory" "failed pull: the pointer is still staged"

echo "=== update-plugin-dev: a memory checkout behind HEAD's pointer is left behind ==="
new_sandbox
move_memory_pointer > /dev/null
git -C "$consumer" add "$mem"
git -C "$consumer" commit -qm "consumer: memory moved"
git -C "$consumer/$mem" checkout -q HEAD^
pointer_case "behind"

echo "=== update-plugin-dev: a memory checkout diverged from HEAD's pointer is left alone ==="
new_sandbox
move_memory_pointer > /dev/null
git -C "$consumer" add "$mem"
git -C "$consumer" commit -qm "consumer: memory moved"
git -C "$consumer/$mem" checkout -q HEAD^
git -C "$consumer/$mem" commit --allow-empty -qm "memory: side fact"
pointer_case "diverged"

echo "=== update-plugin-dev: uncommitted content inside the store is left alone ==="
new_sandbox
move_memory_pointer > /dev/null
printf 'fact\n' > "$consumer/$mem/fact.md"
git -C "$consumer/$mem" add fact.md
printf 'loose\n' > "$consumer/$mem/loose.md"
pointer_case "store dirt"
assert_eq "$(git -C "$consumer/$mem" status --porcelain)" "$(printf 'A  fact.md\n?? loose.md')" "store dirt: the store's own dirt is as it was"

echo "=== update-plugin-dev: a pointer at a path with a space, unstaged and staged ==="
new_sandbox gitlore-memory "my mem"
move_memory_pointer > /dev/null
pointer_case "space"
new_sandbox gitlore-memory "my mem"
new_memory="$(move_memory_pointer)"
git -C "$consumer" add "$mem"
pointer_case "space staged"
assert_eq "$(git -C "$consumer" rev-parse ":$mem")" "$new_memory" "space staged: the same sha is staged afterwards"

echo "=== update-plugin-dev: a staged pointer is found under a consumer config that ignores submodules ==="
new_sandbox
git -C "$consumer" config submodule.gitlore-memory.ignore all
git -C "$consumer" config diff.ignoreSubmodules all
new_memory="$(move_memory_pointer)"
git -C "$consumer" add "$mem"
old="$(git -C "$consumer" rev-parse "HEAD:$mem")"
update dist-v2
assert_eq "$rc" "0" "ignore config: update exit code"
assert_eq "$(git -C "$consumer" rev-parse "HEAD:$mem")" "$old" "ignore config: the merge records HEAD's old pointer"
assert_eq "$(git -C "$consumer" rev-parse ":$mem")" "$new_memory" "ignore config: the same sha is staged afterwards"

echo "=== update-plugin-dev: a merge stopped on a conflict does not stage the pointer ==="
new_sandbox gitlore-memory "my mem"
printf '9.9.9\n' > "$consumer/plugin-dev/VERSION"
git -C "$consumer" commit -qam "consumer: local VERSION edit"
old="$(git -C "$consumer" rev-parse "HEAD:$mem")"
new_memory="$(move_memory_pointer)"
git -C "$consumer" add "$mem"
update dist-v2
if [ "$rc" -eq 0 ]; then fail "conflict: update succeeded"; fi
git -C "$consumer" rev-parse -q --verify MERGE_HEAD > /dev/null || fail "conflict: no merge in progress"
assert_eq "$(git -C "$consumer" rev-parse ":$mem")" "$old" "conflict: the pointer is not staged during the merge"
assert_contains "$out" "cacheinfo 160000,$new_memory," "conflict: the restoring command is printed"
printf '1.0.1\n' > "$consumer/plugin-dev/VERSION"
git -C "$consumer" add plugin-dev/VERSION
git -C "$consumer" commit -qm "consumer: merge resolved"
assert_eq "$(git -C "$consumer" rev-parse "HEAD:$mem")" "$old" "conflict: the finished merge records HEAD's old pointer"
restore="$(sed -n 's/^  \(git -C .* update-index .*\)$/\1/p' <<<"$out")"
mkdir -p "$consumer/plugin-dev/sub"
(cd "$consumer/plugin-dev/sub" && eval "$restore")
assert_eq "$(git -C "$consumer" rev-parse ":$mem")" "$new_memory" "conflict: the printed command stages the pointer again"

echo "=== update-plugin-dev: another submodule's staged gitlink refuses under a consumer config that ignores submodules ==="
new_sandbox notes
git -C "$consumer" config diff.ignoreSubmodules all
move_memory_pointer > /dev/null
git -C "$consumer" add "$mem"
before="$(snapshot)"
update dist-v2
if [ "$rc" -eq 0 ]; then fail "ignore config, other submodule: update succeeded"; fi
assert_contains "$out" "uncommitted changes" "ignore config, other submodule: refusal names the cause"
assert_eq "$(snapshot)" "$before" "ignore config, other submodule: HEAD, status and index unchanged"

echo "=== update-plugin-dev: another submodule's unstaged move refuses under a submodule ignore setting ==="
new_sandbox notes
git -C "$consumer" config submodule.notes.ignore all
move_memory_pointer > /dev/null
before="$(snapshot)"
update dist-v2
if [ "$rc" -eq 0 ]; then fail "ignore setting, unstaged: update succeeded"; fi
assert_contains "$out" "uncommitted changes" "ignore setting, unstaged: refusal names the cause"
assert_eq "$(snapshot)" "$before" "ignore setting, unstaged: HEAD, status and index unchanged"

echo "=== update-plugin-dev: untracked content inside another submodule does not refuse ==="
new_sandbox notes
printf 'loose\n' > "$consumer/$mem/loose.md"
update dist-v2
assert_eq "$rc" "0" "submodule content: update exit code"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.1" "submodule content: VERSION pulled"

echo "=== update-plugin-dev: an edited tracked file inside another submodule refuses ==="
new_sandbox notes
printf 'fact\n' > "$consumer/$mem/fact.md"
git -C "$consumer/$mem" add fact.md
git -C "$consumer/$mem" commit -qm "memory: fact"
git -C "$consumer" add "$mem"
git -C "$consumer" commit -qm "consumer: memory moved"
printf 'edited\n' >> "$consumer/$mem/fact.md"
before="$(snapshot)"
update dist-v2
if [ "$rc" -eq 0 ]; then fail "submodule edit: update succeeded"; fi
assert_contains "$out" "uncommitted changes" "submodule edit: update.sh's own refusal"
assert_eq "$(snapshot)" "$before" "submodule edit: HEAD, status and index unchanged"

echo "=== update-plugin-dev: an already-current pull with the pointer moved changes nothing ==="
new_sandbox
update dist-v2
assert_eq "$rc" "0" "no-op: first update exit code"
move_memory_pointer > /dev/null
git -C "$consumer" add "$mem"
before="$(snapshot)"
update dist-v2
assert_eq "$rc" "0" "no-op: second update exit code"
assert_eq "$(snapshot)" "$before" "no-op: HEAD, status and index unchanged"

echo "=== update-plugin-dev: a pointer beside other tracked dirt refuses, nothing moved ==="
new_sandbox
move_memory_pointer > /dev/null
printf 'edited\n' >> "$consumer/NOTES.md"
before="$(snapshot)"
update dist-v2
if [ "$rc" -eq 0 ]; then fail "other dirt: update succeeded"; fi
assert_contains "$out" "uncommitted changes" "other dirt: refusal names the cause"
assert_eq "$(snapshot)" "$before" "other dirt: HEAD, status and index unchanged"

echo "=== update-plugin-dev: a change staged then reverted in the tree refuses ==="
# The merge would commit the index, so a clean worktree is not enough.
new_sandbox
move_memory_pointer > /dev/null
printf 'edited\n' >> "$consumer/NOTES.md"
git -C "$consumer" add NOTES.md
printf 'notes\n' > "$consumer/NOTES.md"
before="$(snapshot)"
update dist-v2
if [ "$rc" -eq 0 ]; then fail "staged-reverted: update succeeded"; fi
assert_contains "$out" "uncommitted changes" "staged-reverted: refusal names the cause"
assert_eq "$(snapshot)" "$before" "staged-reverted: HEAD, status and index unchanged"

echo "=== update-plugin-dev: a moved submodule at memory under another name refuses ==="
# The store is found by gitlore's submodule name, not by the path it is
# usually mounted at: any other submodule's moved gitlink is unfinished work.
new_sandbox notes
move_memory_pointer > /dev/null
before="$(snapshot)"
update dist-v2
if [ "$rc" -eq 0 ]; then fail "other submodule: update succeeded"; fi
assert_contains "$out" "uncommitted changes" "other submodule: refusal names the cause"
assert_eq "$(snapshot)" "$before" "other submodule: HEAD, status and index unchanged"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nupdate-plugin-dev memory-pointer scenarios passed\n'

#!/usr/bin/env bash
# End-to-end tests of the two subtree call sites — release.just's
# `update-plugin-dev` recipe and install.sh's initial `subtree add` — against
# real git repos in a temp dir. No network: the toolkit and its "memory"
# submodule are local bare repos.
#
# Usage: bash tests/update-plugin-dev-test.sh   (run from repo root)
set -euo pipefail

# See release-test.sh's identical comment: an enclosing `git commit` leaks
# GIT_DIR/GIT_INDEX_FILE/etc. into this process. Every git command below
# targets a synthetic fixture repo via `-C`, never this repo, so it's always
# safe to drop them here.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

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
    if ! printf '%s' "$1" | grep -q -- "$2"; then
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
    if git -C "$1" ls-files -s plugin-dev/ | grep -q '^160000'; then
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
    sandbox="$(mktemp -d)"
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
    seed="$(mktemp -d)"
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
    seed="$(mktemp -d)"
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

echo "=== update-plugin-dev: survives a consumer's unrelated memory submodule at the same path ==="
new_sandbox

# Vendor the toolkit first, before the consumer mounts its own memory
# submodule -- the ordering where the initial add has no collision to hit,
# since the consumer has no submodule registered at "memory" yet. The other
# ordering (memory mounted first, then install) is the install.sh scenario
# below.
run_in "$consumer" allow_file git subtree add --prefix=plugin-dev "$toolkit" dist-v1 --squash
assert_eq "$rc" "0" "initial vendor exit code"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.0" "initial vendor VERSION"

# Consumer mounts its own gitlore memory submodule at the same top-level path
# the toolkit uses internally for its own memory -- the shape where the pull
# has both a toolkit-side gitlink to drop and a consumer-side one to leave
# alone. assert_clean_vendor below checks both halves.
run_in "$consumer" allow_file git submodule add -q "$sandbox/consumer-memory-origin.git" memory
assert_eq "$rc" "0" "consumer memory submodule mount exit code"
git -C "$consumer" commit -qm "consumer: mount memory"

# The toolkit releases a new version.
make_toolkit_release "$toolkit" v2 1.0.1

# A consumer justfile importing THIS repo's real release.just, so the recipe
# under test is the one about to ship, not a copy.
printf "import '%s/toolkit/release.just'\n\nprecommit:\n    @echo stub-precommit\n\nprerelease: precommit\n" \
    "$repo_root" > "$consumer/justfile"

run_in "$consumer" allow_file just --set toolkit_url "$toolkit" update-plugin-dev dist-v2
assert_eq "$rc" "0" "update-plugin-dev exit code"
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.1" "update-plugin-dev pulled the new VERSION"
assert_eq "$(git -C "$consumer" config --get submodule.memory.url)" \
    "$sandbox/consumer-memory-origin.git" "consumer's own memory submodule registration untouched"
assert_clean_vendor "$consumer" "update-plugin-dev"

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
assert_eq "$(cat "$consumer/plugin-dev/VERSION" 2>/dev/null)" "1.0.0" "install.sh vendored VERSION"
assert_eq "$(git -C "$consumer" config --get submodule.memory.url)" \
    "$sandbox/consumer-memory-origin.git" "consumer's own memory submodule registration untouched"
assert_clean_vendor "$consumer" "install.sh"

echo "=== both call sites refuse any ref outside the dist lineage ==="
new_sandbox

# install.sh's run-in-target guard needs a plugin manifest in the cwd.
mkdir -p "$consumer/.claude-plugin"
printf '{"name": "stub-plugin", "version": "0.1.0"}\n' > "$consumer/.claude-plugin/plugin.json"
git -C "$consumer" add .claude-plugin/plugin.json
git -C "$consumer" commit -qm "consumer: plugin manifest"

# A source tag resolves to the toolkit's ROOT tree -- its memory gitlink,
# .claude/, CLAUDE.md, its own justfile. Vendoring one is the leak this whole
# design exists to stop, and it is silent, so both call sites must refuse it
# rather than warn. This is what makes the fetch-recursion collision
# unreachable, so it is asserted rather than assumed.
run_in "$consumer" allow_file env TOOLKIT_URL="$toolkit" bash "$repo_root/toolkit/install.sh" v1
if [ "$rc" -eq 0 ]; then fail "install.sh accepted a source tag"; fi
assert_contains "$out" "dist-v1" "install.sh refusal names the dist tag to use"
if [ -d "$consumer/plugin-dev" ]; then fail "install.sh vendored despite refusing the ref"; fi

run_in "$consumer" allow_file git subtree add --prefix=plugin-dev "$toolkit" dist-v1 --squash
assert_eq "$rc" "0" "vendor for the update-side refusal checks"
printf "import '%s/toolkit/release.just'\n\nprecommit:\n    @echo stub-precommit\n\nprerelease: precommit\n" \
    "$repo_root" > "$consumer/justfile"
git -C "$consumer" add -A
git -C "$consumer" commit -qm "consumer: vendor + justfile"

run_in "$consumer" allow_file just --set toolkit_url "$toolkit" update-plugin-dev v1
if [ "$rc" -eq 0 ]; then fail "update-plugin-dev accepted a source tag"; fi
assert_contains "$out" "dist-v1" "update-plugin-dev refusal names the dist tag to use"

# A branch ref resolves to the same root tree as a source tag, so it leaks
# identically. It used to be permitted with a warning; nothing about a branch
# makes its tree safe to vendor.
run_in "$consumer" allow_file just --set toolkit_url "$toolkit" update-plugin-dev main
if [ "$rc" -eq 0 ]; then fail "update-plugin-dev accepted a branch ref"; fi
assert_contains "$out" "not a dist tag" "branch ref refusal explains why"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nupdate-plugin-dev scenarios passed\n'

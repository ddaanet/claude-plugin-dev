#!/usr/bin/env bash
# End-to-end test of toolkit/check-refs.sh against real git repos in a temp dir.
#
# Scope: shipped stays shipped -- with a dist.include, a reference from a
# shipped file must reach a shipped file that exists, exemptions aside; no
# dist.include skips the check; --shipped replaces the set; --tree checks a
# built tree, where everything is shipped. Its siblings
# check-refs-syntax-test.sh and check-refs-scan-test.sh cover what a reference
# is, which files are read and the exemptions.
#
# Usage: bash tests/check-refs-shipped-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo, never this repo.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
check="$repo_root/toolkit/check-refs.sh"

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

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
    # $1=haystack $2=needle $3=label : a fixed string. A here-string, never a
    # pipe: under pipefail grep -q can SIGPIPE the writer.
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

sandboxes=()
cleanup() {
    local s
    for s in "${sandboxes[@]:-}"; do
        [ -n "$s" ] && rm -rf "$s"
    done
}
trap cleanup EXIT

# mk_repo: a fresh git repo $repo whose own path holds a space, with one
# existing target file, docs/guide.md, and no commit.
mk_repo() {
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/check-refs-shipped.XXXXXX")" || exit 1
    sandbox="$(cd "$sandbox" && pwd -P)"
    sandboxes+=("$sandbox")
    repo="$sandbox/plug in"
    mkdir -p "$repo/docs"
    git -C "$repo" init -q
    printf '# guide\n' > "$repo/docs/guide.md"
}

# put <path> <line...>: write a file under $repo, one argument per line.
put() {
    local f="$repo/$1"
    shift
    mkdir -p "$(dirname "$f")"
    printf '%s\n' "$@" > "$f"
}

# run_check <args...>: run the script with cwd at $repo. Sets $rc, $out, $err.
# A missing script is rc 127, a failed assertion and not an abort.
run_check() {
    rc=0
    (cd "$repo" && bash "$check" "$@" >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
    out="$(cat "$sandbox/stdout")"
    err="$(cat "$sandbox/stderr")"
}

# expect_pass <label>: exit 0, nothing on stderr, the pass line on stdout.
expect_pass() {
    assert_eq "$rc" "0" "$1: exit code"
    assert_eq "$err" "" "$1: stderr"
    assert_contains "$out" "resolves" "$1: the pass line names the resolve check"
}

# expect_broken <label> <file:line: target> : exit 1, the offender on stderr
# with the "does not exist" reason, nothing on stdout.
expect_broken() {
    assert_eq "$rc" "1" "$1: exit code"
    assert_eq "$out" "" "$1: stdout"
    assert_contains "$err" "$2 — does not exist" "$1: stderr names the offender"
}

# mk_plugin: mk_repo plus a plugin layout, a dist.include shipping
# .claude-plugin, skills and README.md, and unshipped docs/design.md and
# plans/p.md.
mk_plugin() {
    mk_repo
    put .claude-plugin/plugin.json '{"name":"fixture","version":"1.0.0"}'
    put skills/demo/SKILL.md '# demo' '' '[readme](../../README.md)'
    put README.md '# fixture' '' '[skill](skills/demo/SKILL.md) [dir](skills/)'
    put docs/design.md '# design' '' '[plan](../plans/p.md) [readme](../README.md)'
    put plans/p.md '# plan'
    put dist.include .claude-plugin skills README.md
}

echo "=== shipped to shipped, and unshipped to anything, pass ==="
mk_plugin
run_check
assert_eq "$rc" "0" "shipped to shipped: exit code"
assert_eq "$err" "" "shipped to shipped: stderr"
assert_contains "$out" "shipped stays shipped" "the pass line names the shipped check"
assert_contains "$out" "3 references from 2 shipped files" "the pass line counts the shipped references"

echo "=== shipped to an unshipped file is refused ==="
mk_plugin
put README.md '# fixture' '' 'Design: [hub](docs/design.md#top).'
run_check
assert_eq "$rc" "1" "shipped to unshipped: exit code"
assert_eq "$out" "" "shipped to unshipped: stdout"
assert_contains "$err" "README.md:3: docs/design.md#top — is not shipped" "shipped to unshipped: named"

echo "=== shipped to a missing file is refused once ==="
mk_plugin
put skills/demo/SKILL.md '[gone](references/gone.md)'
run_check
assert_eq "$rc" "1" "shipped to missing: exit code"
assert_contains "$err" "skills/demo/SKILL.md:1: references/gone.md — does not exist" "shipped to missing: named"
assert_eq "$(grep -c 'references/gone.md' <<<"$err")" "1" "shipped to missing: one line, not one per check"

echo "=== exemptions do not apply to shipped files ==="
mk_plugin
put dist.include .claude-plugin skills README.md docs
put docs/changelog/2020-01-01-x.md '[plan](../../plans/p.md) [gone](../../plans/deleted.md)'
put docs/design.md '# design'
run_check
assert_eq "$rc" "1" "exempt and shipped: exit code"
assert_contains "$err" "docs/changelog/2020-01-01-x.md:1: ../../plans/p.md — is not shipped" \
    "exempt and shipped: unshipped target refused"
assert_contains "$err" "docs/changelog/2020-01-01-x.md:1: ../../plans/deleted.md — does not exist" \
    "exempt and shipped: missing target refused"

echo "=== no dist.include: the shipped check is skipped ==="
mk_plugin
rm "$repo/dist.include"
put README.md '[hub](docs/design.md)'
run_check
assert_eq "$rc" "0" "no dist.include: exit code"
assert_contains "$out" "resolves" "no dist.include: the resolve check ran"
assert_contains "$out" "skipped" "no dist.include: the shipped check says it was skipped"

echo "=== a malformed dist.include is refused, with dist.sh's own line ==="
mk_plugin
put dist.include .claude-plugin '../outside'
run_check
assert_eq "$rc" "1" "malformed dist.include: exit code"
assert_contains "$err" "has a .. component" "malformed dist.include: dist.sh's refusal passes through"

echo "=== --shipped replaces dist.include ==="
mk_plugin
put toolkit/README.md '[man](manual/a.md) [repo](../docs/design.md)'
put toolkit/manual/a.md '[back](../README.md)'
put README.md '[hub](docs/design.md) [kit](toolkit/README.md)'
run_check --shipped toolkit
assert_eq "$rc" "1" "--shipped: exit code"
assert_contains "$err" "toolkit/README.md:1: ../docs/design.md — is not shipped" "--shipped: the listed tree is checked"
assert_not_contains "$err" "README.md:1: docs/design.md" "--shipped: dist.include's README.md is no longer shipped"
put toolkit/README.md '[man](manual/a.md)'
run_check --shipped toolkit/ .claude-plugin
assert_eq "$rc" "0" "--shipped, two paths: exit code"
assert_contains "$out" "shipped stays shipped" "--shipped, two paths: the check ran"

echo "=== --shipped refuses a path that does not exist ==="
mk_plugin
run_check --shipped toolkt
assert_eq "$rc" "1" "--shipped typo: exit code"
assert_contains "$err" "toolkt" "--shipped typo: named"

echo "=== --tree: a reference must resolve inside the tree ==="
mk_plugin
put README.md '# fixture' '' '[skill](skills/demo/SKILL.md)' '[hub](docs/design.md)'
git -C "$repo" add -A
tree="$(git -C "$repo" write-tree)"
git -C "$repo" rm -q --cached -r docs
partial="$(git -C "$repo" write-tree)"
run_check --tree "$tree"
assert_eq "$rc" "0" "--tree, whole tree: exit code"
run_check --tree "$partial"
assert_eq "$rc" "1" "--tree, docs left out: exit code"
assert_eq "$out" "" "--tree, docs left out: stdout"
assert_contains "$err" "README.md:4: docs/design.md — is not in the tree" "--tree, docs left out: named"
put README.md '# fixture' '' '[hub](docs/gone.md)'
run_check --tree "$partial"
assert_eq "$rc" "1" "--tree reads the tree, not the disk: exit code"
assert_contains "$err" "README.md:4: docs/design.md" "--tree reads the tree, not the disk: the tree's README"

echo "=== shipped: an ignored target refused, an untracked one and the root accepted ==="
mk_plugin
put dist.include .claude-plugin skills README.md docs
put .gitignore 'docs/api.md'
put docs/api.md '# generated'
put docs/draft.md '# draft'
put skills/demo/SKILL.md '[api](../../docs/api.md) [draft](../../docs/draft.md) [root](../../)'
run_check
assert_eq "$rc" "1" "shipped, ignored: exit code"
assert_contains "$err" "skills/demo/SKILL.md:1: ../../docs/api.md — is ignored by git" "shipped, ignored: refused"
assert_not_contains "$err" "draft.md" "shipped, untracked: accepted"
assert_not_contains "$err" "../../ —" "shipped, the root: shipped"

echo "=== --tree: a target above the tree's root leaves the repository ==="
mk_plugin
put README.md '[out](../elsewhere.md)'
git -C "$repo" add -A
tree="$(git -C "$repo" write-tree)"
run_check --tree "$tree"
assert_eq "$rc" "1" "--tree, above the root: exit code"
assert_contains "$err" "README.md:1: ../elsewhere.md — leaves the repository" "--tree, above the root: named"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall check-refs shipped scenarios passed\n'

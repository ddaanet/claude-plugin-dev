#!/usr/bin/env bash
# End-to-end test of toolkit/check-refs.sh against real git repos in a temp dir.
#
# Scope: which files are read and which are exempt -- every Markdown file on
# disk git does not ignore, tracked or not, read from disk and never from the
# index; never an ignored file, the vendored plugin-dev/ tree, a submodule or a
# tracked file deleted from disk; the default exemption (docs/changelog/), a
# refs.exempt that replaces it, and plans/, which is always skipped. Its siblings
# check-refs-syntax-test.sh and check-refs-shipped-test.sh cover what a
# reference is and the shipped-stays-shipped check.
#
# Usage: bash tests/check-refs-scan-test.sh   (run from repo root)
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
    sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/check-refs-scan.XXXXXX")" && pwd -P)"
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

# run_check: run the script with cwd at $repo. Sets $rc, $out, $err. A
# missing script is rc 127, a failed assertion and not an abort.
run_check() {
    rc=0
    (cd "$repo" && bash "$check" >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
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

# commit_all: commit what is in $repo, ignores respected.
commit_all() {
    git -C "$repo" add -A
    git -C "$repo" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false \
        commit -q -m fixture
}

echo "=== a tracked file is read from disk, not from the index ==="
mk_repo
put README.md '[g](docs/guide.md)'
commit_all
run_check
expect_pass "committed, resolving"
put README.md '[g](docs/gone.md)'
run_check
expect_broken "edited on disk after the commit" "README.md:1: docs/gone.md"

echo "=== an untracked file on disk is read ==="
mk_repo
put README.md '# r'
commit_all
put notes/new.md '[n](missing.md)'
run_check
expect_broken "untracked" "notes/new.md:1: missing.md"

echo "=== an ignored file is not read ==="
mk_repo
put .gitignore 'scratch/' 'private.md'
put scratch/draft.md '[d](missing.md)'
put private.md '[p](missing.md)'
run_check
expect_pass "ignored"

echo "=== a file name with a space is read and named whole ==="
mk_repo
put "docs/my notes.md" '[n](<../no such.md>)'
run_check
expect_broken "spaced name" "docs/my notes.md:1: ../no such.md"

echo "=== a tracked file deleted from disk is skipped ==="
mk_repo
put README.md '# r'
put docs/old.md '[o](gone.md)'
commit_all
rm "$repo/docs/old.md"
run_check
expect_pass "deleted from disk"

echo "=== plugin-dev/ is skipped, and can still be a target ==="
mk_repo
put plugin-dev/README.md '[v](nothing-here.md)'
put README.md '[t](plugin-dev/README.md)'
run_check
expect_pass "vendored tree"

echo "=== a submodule is not entered ==="
mk_repo
mkdir -p "$repo/memory"
git -C "$repo/memory" init -q
printf '[m](missing.md)\n' > "$repo/memory/MEMORY.md"
git -C "$repo/memory" add -A
git -C "$repo/memory" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false \
    commit -q -m inner
put README.md '[m](memory/MEMORY.md)'
commit_all
assert_eq "$(git -C "$repo" ls-files -s memory | cut -d' ' -f1)" "160000" "fixture: memory is a gitlink"
run_check
expect_pass "submodule"

echo "=== default exemption docs/changelog/, and plans/ always skipped ==="
mk_repo
put docs/changelog/2020-01-01-x.md '[old](../../plans/gone.md)'
put plans/p.md '[later](deleted.md)'
put docs/changelogs.md '[no](deleted.md)'
run_check
expect_broken "outside the exempt prefixes" "docs/changelogs.md:1: deleted.md"
assert_not_contains "$err" "2020-01-01-x.md" "docs/changelog/ is exempt"
assert_not_contains "$err" "plans/p.md" "plans/ is exempt"
rm "$repo/docs/changelogs.md"
run_check
expect_pass "exempt only"
assert_contains "$out" "1 exempt files skipped" "the pass line counts the exempt files, not plans/"

echo "=== refs.exempt replaces docs/changelog, never plans/ ==="
mk_repo
put plans/p.md '[later](deleted.md)'
put docs/changelog/2020-01-01-x.md '[old](deleted.md)'
put notes/n.md '[n](deleted.md)'
put archive.md '[a](deleted.md)'
put refs.exempt '# frozen records' '' 'notes/' 'archive.md'
run_check
expect_broken "docs/changelog no longer exempt" "docs/changelog/2020-01-01-x.md:1: deleted.md"
assert_not_contains "$err" "plans/p.md" "plans/ stays skipped beside a refs.exempt"
assert_not_contains "$err" "notes/n.md" "a listed directory is exempt"
assert_not_contains "$err" "archive.md" "a listed file is exempt"

echo "=== refs.exempt: blanks trimmed, a trailing note is a comment ==="
mk_repo
put notes/n.md '[n](deleted.md)'
put archive.md '[a](deleted.md)'
printf '%s\r\n' '  notes/  # frozen' 'archive.md # kept' > "$repo/refs.exempt"
run_check
expect_pass "trimmed refs.exempt"
assert_contains "$out" "2 exempt files skipped" "both listed paths matched"

echo "=== an empty refs.exempt exempts nothing ==="
mk_repo
put docs/changelog/2020-01-01-x.md '[old](deleted.md)'
: > "$repo/refs.exempt"
run_check
expect_broken "empty refs.exempt" "docs/changelog/2020-01-01-x.md:1: deleted.md"

echo "=== run from a subdirectory: paths are from the repo root ==="
mk_repo
put docs/a.md '[x](nowhere.md)'
rc=0
(cd "$repo/docs" && bash "$check" >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
err="$(cat "$sandbox/stderr")"
assert_eq "$rc" "1" "subdirectory: exit code"
assert_contains "$err" "docs/a.md:1: nowhere.md — does not exist" "subdirectory: root-relative name"

echo "=== a target is a file git lists: ignored refused, untracked accepted ==="
mk_repo
put .gitignore 'docs/api.md'
put docs/api.md '# generated'
put docs/draft.md '# untracked draft'
put README.md '[api](docs/api.md) [draft](docs/draft.md) [dir](docs/) [root](./)'
run_check
assert_eq "$rc" "1" "ignored target: exit code"
assert_contains "$err" "README.md:1: docs/api.md — is ignored by git" "ignored target: refused"
assert_not_contains "$err" "draft.md" "untracked target: accepted"
assert_not_contains "$err" "docs/ —" "directory holding a listed file: accepted"
assert_not_contains "$err" "./ —" "root: accepted"

echo "=== a tracked target deleted from disk does not exist ==="
mk_repo
put README.md '[g](docs/guide.md)'
commit_all
rm "$repo/docs/guide.md"
run_check
expect_broken "deleted target" "README.md:1: docs/guide.md"

echo "=== a target is matched with its exact case ==="
mk_repo
put README.md '[g](docs/Guide.md)'
run_check
assert_eq "$rc" "1" "case: exit code"
assert_contains "$err" "README.md:1: docs/Guide.md" "case: a case-folded target is refused"

echo "=== a directory with only ignored files is not a target ==="
mk_repo
put .gitignore 'build/'
put build/out.md '# out'
put README.md '[b](build/)'
run_check
assert_eq "$rc" "1" "ignored directory: exit code"
assert_contains "$err" "README.md:1: build/ — is ignored by git" "ignored directory: refused"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall check-refs scan scenarios passed\n'

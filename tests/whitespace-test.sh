#!/usr/bin/env bash
# Tests this repo's `whitespace` recipe against a fixture repo: it runs the real
# recipe from the real justfile with the fixture as its working directory. The
# recipe picks its files from disk, as the precommit checks after it do: every
# non-ignored file, tracked or not, so a file the next `git add` stages was
# fixed before the gate hashed it. A tracked file it fixes is staged; an
# untracked one is fixed in place and left untracked, since adding a file is
# the committer's call.
#
# Usage: bash tests/whitespace-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo, never this repo.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture
repo_root="$(cd "$(dirname "$0")/.." && pwd)"

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

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/whitespace.XXXXXX")" || exit 1
sandbox="$(cd "$sandbox" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT

# A fixture whose own path holds a space. Each file carries a trailing blank
# line, which `git stripspace` removes.
repo="$sandbox/fix ture"
mkdir -p "$repo/docs"
git -C "$repo" init -q
printf 'tracked\n\n' > "$repo/docs/tracked.md"
printf 'untracked\n\n' > "$repo/docs/new file.md"
printf 'ignored\n\n' > "$repo/docs/ignored.md"
printf 'other\n\n' > "$repo/data.txt"
printf 'docs/ignored.md\n' > "$repo/.gitignore"
git -C "$repo" add docs/tracked.md .gitignore data.txt

rc=0
out="$(just --justfile "$repo_root/justfile" --working-directory "$repo" whitespace 2>&1)" || rc=$?

echo "=== a tracked file is fixed and staged ==="
assert_eq "$rc" "0" "the recipe exits 0"
assert_eq "$(cat "$repo/docs/tracked.md"; echo .)" "tracked
." "tracked file: trailing blank line removed"
assert_eq "$(git -C "$repo" show :docs/tracked.md; echo .)" "tracked
." "tracked file: the fix is staged"

echo "=== an untracked file is fixed but not staged ==="
assert_eq "$(cat "$repo/docs/new file.md"; echo .)" "untracked
." "untracked file: trailing blank line removed"
assert_eq "$(git -C "$repo" ls-files -- 'docs/new file.md')" "" "untracked file: still untracked"
if ! grep -qF 'whitespace: docs/new file.md (untracked, not staged)' <<<"$out"; then
    fail "untracked file: the fix is reported as unstaged; output: $out"
fi

echo "=== an ignored file and a file of another type are left alone ==="
assert_eq "$(cat "$repo/docs/ignored.md"; echo .)" "ignored

." "ignored file: untouched"
assert_eq "$(cat "$repo/data.txt"; echo .)" "other

." "a .txt file: untouched"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nwhitespace ok (tracked fixed and staged, untracked fixed and left unstaged, ignored and other types untouched)\n'

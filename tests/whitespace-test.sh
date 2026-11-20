#!/usr/bin/env bash
# Tests this repo's `whitespace` recipe against a fixture repo: it runs the real
# recipe from the real justfile with the fixture as its working directory. The
# recipe picks its files from disk, as the precommit checks after it do: every
# non-ignored file, tracked or not, so a file the next `git add` stages was
# fixed before the gate hashed it. A tracked file whose worktree matches its
# index is fixed and staged; one with unstaged edits takes the fix of its
# staged blob in the index, mode kept, and is fixed in place, edits and all,
# without being staged. An untracked or intent-to-add file is fixed in place
# and left as it was in the index, since adding a file is the committer's
# call. An unmerged path is skipped, index and worktree alike, and fails the
# recipe once the rest is fixed, even when its worktree file is gone. A
# symlink is never touched, and a mode-only unstaged change is never staged.
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
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.invalid
printf 'docs/ignored.md\n' > "$repo/.gitignore"
# A real conflicted merge, made before anything else is staged: both sides
# rewrite the file, each leaving a trailing blank line.
printf 'base\n' > "$repo/docs/conflicted.md"
printf 'base\n' > "$repo/docs/gone.md"
git -C "$repo" add .gitignore docs/conflicted.md docs/gone.md
git -C "$repo" commit -qm base
base_branch="$(git -C "$repo" symbolic-ref --short HEAD)"
git -C "$repo" checkout -qb side
printf 'side\n\n' > "$repo/docs/conflicted.md"
printf 'side\n\n' > "$repo/docs/gone.md"
git -C "$repo" commit -qam side
git -C "$repo" checkout -q "$base_branch"
printf 'main\n\n' > "$repo/docs/conflicted.md"
printf 'main\n\n' > "$repo/docs/gone.md"
git -C "$repo" commit -qam main
if git -C "$repo" merge -q side >/dev/null 2>&1; then
    fail "fixture: the merge was expected to conflict"
fi
unmerged_index="$(git -C "$repo" ls-files -s -- docs/conflicted.md)"
unmerged_wt="$(cat "$repo/docs/conflicted.md"; echo .)"
# A second conflicted path, its worktree file removed while unresolved.
gone_index="$(git -C "$repo" ls-files -s -- docs/gone.md)"
rm "$repo/docs/gone.md"
printf 'tracked\n\n' > "$repo/docs/tracked.md"
printf 'clean\n' > "$repo/docs/clean.md"
printf 'staged\n\n' > "$repo/docs/split file.md"
printf '#!/bin/sh\nstaged\n\n' > "$repo/run.sh"
chmod 755 "$repo/run.sh"
printf 'untracked\n\n' > "$repo/docs/new file.md"
printf 'intent\n\n' > "$repo/docs/intent.md"
printf 'ignored\n\n' > "$repo/docs/ignored.md"
printf 'other\n\n' > "$repo/data.txt"
# A tracked symlink whose name passes the filter: its blob is the target path.
ln -s tracked.md "$repo/docs/link.md"
# A file whose only unstaged change is its mode.
printf 'mode\n\n' > "$repo/mode.sh"
git -C "$repo" add docs/tracked.md docs/clean.md 'docs/split file.md' run.sh data.txt \
    docs/link.md mode.sh
link_index="$(git -C "$repo" ls-files -s -- docs/link.md)"
chmod 755 "$repo/mode.sh"
git -C "$repo" add -N docs/intent.md
printf 'staged\n\nunstaged edit\n\n' > "$repo/docs/split file.md"
printf '#!/bin/sh\nstaged\nunstaged edit\n\n' > "$repo/run.sh"
clean_index="$(git -C "$repo" ls-files -s -- docs/clean.md)"

rc=0
out="$(just --justfile "$repo_root/justfile" --working-directory "$repo" whitespace 2>"$sandbox/err")" || rc=$?
err="$(cat "$sandbox/err")"

echo "=== a tracked file is fixed and staged ==="
assert_eq "$(cat "$repo/docs/tracked.md"; echo .)" "tracked
." "tracked file: trailing blank line removed"
assert_eq "$(git -C "$repo" show :docs/tracked.md; echo .)" "tracked
." "tracked file: the fix is staged"

assert_eq "$(git -C "$repo" ls-files -s -- docs/clean.md)" "$clean_index" "clean file: index entry untouched"
if grep -qF 'whitespace: docs/clean.md' <<<"$out"; then
    fail "clean file: reported though nothing changed; output: $out"
fi

echo "=== a tracked file with unstaged edits: staged blob fixed, edits left unstaged ==="
assert_eq "$(git -C "$repo" show ':docs/split file.md'; echo .)" "staged
." "split file: the index holds the fixed staged content without the edit"
assert_eq "$(cat "$repo/docs/split file.md"; echo .)" "staged

unstaged edit
." "split file: the worktree is fixed in place, edit kept"
assert_eq "$(git -C "$repo" show ':run.sh'; echo .)" "#!/bin/sh
staged
." "split script: the index holds the fixed staged content without the edit"
assert_eq "$(git -C "$repo" ls-files -s -- run.sh | awk '{ print $1 }')" "100755" "split script: the index mode is kept"
assert_eq "$(cat "$repo/run.sh"; echo .)" "#!/bin/sh
staged
unstaged edit
." "split script: the worktree is fixed in place, edit kept"
if ! grep -qF 'whitespace: docs/split file.md (unstaged edits, not staged)' <<<"$out"; then
    fail "split file: the worktree fix is reported as unstaged; output: $out"
fi
if ! grep -qF 'whitespace: docs/split file.md (staged content)' <<<"$out"; then
    fail "split file: the index fix is reported; output: $out"
fi

echo "=== a tracked symlink is left alone ==="
assert_eq "$(git -C "$repo" ls-files -s -- docs/link.md)" "$link_index" "symlink: the index entry is untouched"
assert_eq "$(readlink "$repo/docs/link.md")" "tracked.md" "symlink: the worktree link is untouched"
if grep -qF 'whitespace: docs/link.md' <<<"$out"; then
    fail "symlink: reported though it must be skipped; output: $out"
fi

echo "=== a mode-only unstaged change is not staged ==="
assert_eq "$(git -C "$repo" ls-files -s -- mode.sh | awk '{ print $1 }')" "100644" "mode only: the index mode is kept"
assert_eq "$(git -C "$repo" show :mode.sh; echo .)" "mode
." "mode only: the staged blob is fixed"
assert_eq "$(cat "$repo/mode.sh"; echo .)" "mode
." "mode only: the worktree is fixed"
[ -x "$repo/mode.sh" ] || fail "mode only: the worktree lost its execute bit"

echo "=== an unmerged path is skipped, and fails the recipe ==="
assert_eq "$rc" "1" "unmerged: the recipe exits 1 after fixing the rest"
assert_eq "$(git -C "$repo" ls-files -s -- docs/conflicted.md)" "$unmerged_index" "unmerged: the index stages are unchanged"
assert_eq "$(cat "$repo/docs/conflicted.md"; echo .)" "$unmerged_wt" "unmerged: the worktree is unchanged"
assert_eq "$(grep -cF 'whitespace: docs/conflicted.md skipped (unmerged)' <<<"$out" || true)" "1" \
    "unmerged: the path is reported skipped exactly once"
assert_eq "$(grep -cF 'whitespace: unmerged paths left unfixed' <<<"$err" || true)" "1" \
    "unmerged: stderr names the unmerged failure; stderr: $err"
assert_eq "$(git -C "$repo" ls-files -s -- docs/gone.md)" "$gone_index" "unmerged, worktree gone: the index stages are unchanged"
assert_eq "$(grep -cF 'whitespace: docs/gone.md skipped (unmerged)' <<<"$out" || true)" "1" \
    "unmerged, worktree gone: the path is still reported skipped"

echo "=== an intent-to-add file is fixed and stays intent-to-add ==="
assert_eq "$(cat "$repo/docs/intent.md"; echo .)" "intent
." "intent-to-add: fixed in place"
assert_eq "$(git -C "$repo" ls-files -s -- docs/intent.md | awk '{ print $2 }')" \
    "$(git -C "$repo" hash-object --stdin </dev/null)" "intent-to-add: the index entry is still the empty blob"
if ! grep -qF 'whitespace: docs/intent.md (intent-to-add, not staged)' <<<"$out"; then
    fail "intent-to-add: the fix is reported as unstaged; output: $out"
fi

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

echo "=== once the conflict is resolved, the recipe passes ==="
git -C "$repo" add docs/conflicted.md
git -C "$repo" rm -q docs/gone.md
rc=0
out="$(just --justfile "$repo_root/justfile" --working-directory "$repo" whitespace 2>&1)" || rc=$?
assert_eq "$rc" "0" "resolved: the recipe exits 0; output: $out"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nwhitespace ok (tracked fixed and staged, clean not restaged, unstaged edits fixed unstaged with the staged blob fixed and its mode kept, symlink and mode-only change untouched in the index, unmerged skipped and failing even with its file gone, resolved passing, intent-to-add kept, untracked left unstaged, ignored and other types untouched)\n'

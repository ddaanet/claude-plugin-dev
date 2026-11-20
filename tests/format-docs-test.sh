#!/usr/bin/env bash
# Tests this repo's `format-docs` recipe against a fixture repo, with a stub
# standing in for rumdl (`just rumdl=<stub> format-docs`): it runs the real
# recipe from the real justfile with the fixture as its working directory. A
# tracked file the formatter rewrites is staged with the rewrite, so a commit
# from the pre-commit hook carries the formatted text; an untracked one is
# rewritten in place and left untracked; a file the formatter leaves alone
# keeps its index entry, unstaged edit and all. A tracked file with unstaged
# edits takes the reflow of its staged blob in the index, and is formatted in
# place, edits and all, without being staged. An unmerged path is skipped,
# index and worktree alike, and fails the recipe once the rest is formatted,
# so the gate records no sentinel over an unformatted file; an intent-to-add
# file is formatted in place and left intent-to-add.
#
# Usage: bash tests/format-docs-test.sh   (run from repo root)
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

sandbox="$(mktemp -d "${TMPDIR:-/tmp}/format-docs.XXXXXX")" || exit 1
sandbox="$(cd "$sandbox" && pwd -P)"
trap 'rm -rf "$sandbox"' EXIT

# The stub answers the pin check, then formats deterministically: a line
# `LONG a b` becomes the two lines `a` and `b`, any other line is kept. It
# serves `fmt --no-cache -- files...` (in place) and
# `fmt --no-cache --stdin --stdin-filename NAME --silent` (stdin to stdout).
stub="$sandbox/rumdl-stub"
cat > "$stub" <<'STUB'
#!/usr/bin/env bash
wrap() { awk '$1 == "LONG" && NF == 3 { print $2; print $3; next } { print }'; }
if [ "${1:-}" = "--version" ]; then echo "rumdl 1.2.3"; exit 0; fi
[ "$1" = fmt ] && [ "$2" = --no-cache ] || exit 2
shift 2
if [ "$1" = --stdin ]; then wrap; exit 0; fi
[ "$1" = -- ] || exit 2
shift
for f in "$@"; do
    wrap < "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm "$f.tmp"
done
STUB
chmod +x "$stub"

# A fixture whose own path holds a space.
repo="$sandbox/fix ture"
mkdir -p "$repo/docs"
git -C "$repo" init -q
git -C "$repo" config user.name t
git -C "$repo" config user.email t@example.invalid
printf '"rumdl==1.2.3"\n' > "$repo/pyproject.toml"
printf 'docs/ignored.md\n' > "$repo/.gitignore"
# A real conflicted merge, made before anything else is staged: both sides
# rewrite the last line of docs/conflicted.md, far enough from its long first
# line that a reflow of the ancestor would merge cleanly into the markers.
printf 'LONG a b\n1\n2\n3\n4\nx\n' > "$repo/docs/conflicted.md"
git -C "$repo" add pyproject.toml .gitignore docs/conflicted.md
git -C "$repo" commit -qm base
base_branch="$(git -C "$repo" symbolic-ref --short HEAD)"
git -C "$repo" checkout -qb side
printf 'LONG a b\n1\n2\n3\n4\ny\n' > "$repo/docs/conflicted.md"
git -C "$repo" commit -qam side
git -C "$repo" checkout -q "$base_branch"
printf 'LONG a b\n1\n2\n3\n4\nz\n' > "$repo/docs/conflicted.md"
git -C "$repo" commit -qam main
if git -C "$repo" merge -q side >/dev/null 2>&1; then
    fail "fixture: the merge was expected to conflict"
fi
unmerged_index="$(git -C "$repo" ls-files -s -- docs/conflicted.md)"
unmerged_wt="$(cat "$repo/docs/conflicted.md")"
printf 'LONG x y\n' > "$repo/docs/tracked.md"
printf 'LONG s p\n' > "$repo/docs/a b.md"
printf 'plain\n' > "$repo/docs/kept.md"
printf 'LONG a b\nmid\nend\n' > "$repo/docs/split file.md"
printf 'LONG u v\n' > "$repo/docs/new file.md"
printf 'LONG k l\n' > "$repo/docs/intent.md"
printf 'LONG i j\n' > "$repo/docs/ignored.md"
printf 'LONG o p\n' > "$repo/data.txt"
git -C "$repo" add docs/tracked.md docs/a\ b.md docs/kept.md \
    'docs/split file.md' data.txt
git -C "$repo" add -N docs/intent.md
printf 'plain\nunstaged edit\n' > "$repo/docs/kept.md"
printf 'LONG a b\nmid\nLONG c d\n' > "$repo/docs/split file.md"

rc=0
out="$(just --justfile "$repo_root/justfile" --working-directory "$repo" "rumdl=$stub" format-docs 2>"$sandbox/err")" || rc=$?
err="$(cat "$sandbox/err")"

echo "=== a tracked file is reformatted and staged ==="
assert_eq "$(git -C "$repo" show :docs/tracked.md)" "x
y" "tracked file: the rewrite is staged"
assert_eq "$(git -C "$repo" show ':docs/a b.md')" "s
p" "tracked file with a space: the rewrite is staged"
assert_eq "$(git -C "$repo" diff --name-only -- docs/tracked.md 'docs/a b.md')" "" "tracked files: no unstaged remainder"

echo "=== a staged reflow with an unstaged long-line edit ==="
assert_eq "$(git -C "$repo" show ':docs/split file.md')" "a
b
mid
end" "split file: the index holds the formatted staged content without the edit"
assert_eq "$(cat "$repo/docs/split file.md")" "a
b
mid
c
d" "split file: the worktree holds both, formatted"

echo "=== an unmerged path is skipped, and fails the recipe ==="
assert_eq "$rc" "1" "unmerged: the recipe exits 1 after formatting the rest"
assert_eq "$(git -C "$repo" ls-files -s -- docs/conflicted.md)" "$unmerged_index" "unmerged: the index stages are unchanged"
assert_eq "$(cat "$repo/docs/conflicted.md")" "$unmerged_wt" "unmerged: the worktree is unchanged"
assert_eq "$(grep -cF 'format-docs: docs/conflicted.md skipped (unmerged)' <<<"$out" || true)" "1" \
    "unmerged: the path is reported skipped exactly once"
assert_eq "$(grep -cF 'format-docs: unmerged paths left unformatted' <<<"$err" || true)" "1" \
    "unmerged: stderr names the unmerged failure; stderr: $err"

echo "=== an intent-to-add file is formatted and stays intent-to-add ==="
assert_eq "$(cat "$repo/docs/intent.md")" "k
l" "intent-to-add: rewritten in place"
assert_eq "$(git -C "$repo" ls-files -s -- docs/intent.md | awk '{ print $2 }')" \
    "$(git -C "$repo" hash-object --stdin </dev/null)" "intent-to-add: the index entry is still the empty blob"
assert_eq "$(git -C "$repo" diff --cached --name-only -- docs/intent.md)" "" "intent-to-add: nothing staged"

echo "=== an untracked file is reformatted but not staged ==="
assert_eq "$(cat "$repo/docs/new file.md")" "u
v" "untracked file: rewritten in place"
assert_eq "$(git -C "$repo" ls-files -- 'docs/new file.md')" "" "untracked file: still untracked"
if ! grep -qF 'format-docs: docs/new file.md (untracked, not staged)' <<<"$out"; then
    fail "untracked file: the rewrite is reported as unstaged; output: $out"
fi

echo "=== a file the formatter leaves alone keeps its index entry ==="
assert_eq "$(git -C "$repo" show :docs/kept.md)" "plain" "unchanged file: index untouched"
assert_eq "$(cat "$repo/docs/kept.md")" "plain
unstaged edit" "unchanged file: unstaged edit kept"

echo "=== an ignored file and a file of another type are left alone ==="
assert_eq "$(cat "$repo/docs/ignored.md")" "LONG i j" "ignored file: untouched"
assert_eq "$(cat "$repo/data.txt")" "LONG o p" "a .txt file: untouched"

echo "=== once the conflict is resolved, the recipe passes ==="
git -C "$repo" add docs/conflicted.md
rc=0
out="$(just --justfile "$repo_root/justfile" --working-directory "$repo" "rumdl=$stub" format-docs 2>&1)" || rc=$?
assert_eq "$rc" "0" "resolved: the recipe exits 0; output: $out"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nformat-docs ok (tracked rewrite staged, unstaged edits formatted unstaged, unmerged skipped and failing, resolved passing, intent-to-add kept, untracked left unstaged, unchanged file not restaged, spaced paths, ignored and other types untouched)\n'

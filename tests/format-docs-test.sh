#!/usr/bin/env bash
# Tests this repo's `format-docs` recipe against a fixture repo, with a stub
# standing in for rumdl (`just rumdl=<stub> format-docs`): it runs the real
# recipe from the real justfile with the fixture as its working directory. A
# tracked file the formatter rewrites is staged with the rewrite, so a commit
# from the pre-commit hook carries the formatted text; an untracked one is
# rewritten in place and left untracked; a file the formatter leaves alone
# keeps its index entry, unstaged edit and all. A tracked file with unstaged
# edits takes the reflow in the index only, the worktree a three-way merge of
# its edits over it, and a conflict leaves both as they were.
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
printf '"rumdl==1.2.3"\n' > "$repo/pyproject.toml"
printf 'LONG x y\n' > "$repo/docs/tracked.md"
printf 'LONG s p\n' > "$repo/docs/a b.md"
printf 'plain\n' > "$repo/docs/kept.md"
printf 'LONG a b\nmid\nend\n' > "$repo/docs/split file.md"
printf 'LONG a b\nend\n' > "$repo/docs/conflict.md"
printf 'LONG u v\n' > "$repo/docs/new file.md"
printf 'LONG i j\n' > "$repo/docs/ignored.md"
printf 'LONG o p\n' > "$repo/data.txt"
printf 'docs/ignored.md\n' > "$repo/.gitignore"
git -C "$repo" add pyproject.toml docs/tracked.md docs/a\ b.md docs/kept.md \
    'docs/split file.md' docs/conflict.md .gitignore data.txt
printf 'plain\nunstaged edit\n' > "$repo/docs/kept.md"
printf 'LONG a b\nmid\nend edited\n' > "$repo/docs/split file.md"
printf 'LONG a c\nend\n' > "$repo/docs/conflict.md"
conflict_wt="$(cat "$repo/docs/conflict.md")"

rc=0
out="$(just --justfile "$repo_root/justfile" --working-directory "$repo" "rumdl=$stub" format-docs 2>&1)" || rc=$?

echo "=== a tracked file is reformatted and staged ==="
assert_eq "$rc" "0" "the recipe exits 0"
assert_eq "$(git -C "$repo" show :docs/tracked.md)" "x
y" "tracked file: the rewrite is staged"
assert_eq "$(git -C "$repo" show ':docs/a b.md')" "s
p" "tracked file with a space: the rewrite is staged"
assert_eq "$(git -C "$repo" diff --name-only -- docs/tracked.md 'docs/a b.md')" "" "tracked files: no unstaged remainder"

echo "=== a staged reflow with an unstaged edit elsewhere is merged piecewise ==="
assert_eq "$(git -C "$repo" show ':docs/split file.md')" "a
b
mid
end" "split file: the index holds the reflow without the edit"
assert_eq "$(cat "$repo/docs/split file.md")" "a
b
mid
end edited" "split file: the worktree holds the reflow and the edit"

echo "=== a conflicting edit leaves index and worktree as they were ==="
assert_eq "$(git -C "$repo" show :docs/conflict.md)" "LONG a b
end" "conflict: the index is untouched"
assert_eq "$(cat "$repo/docs/conflict.md")" "$conflict_wt" "conflict: the worktree is untouched"
if ! grep -qF 'format-docs: docs/conflict.md unformatted' <<<"$out"; then
    fail "conflict: the path is reported unformatted; output: $out"
fi

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

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nformat-docs ok (tracked rewrite staged, unstaged edits merged piecewise or left on conflict, untracked left unstaged, unchanged file not restaged, spaced paths, ignored and other types untouched)\n'

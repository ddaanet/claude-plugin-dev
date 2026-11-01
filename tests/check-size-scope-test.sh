#!/usr/bin/env bash
# End-to-end test of toolkit/check-size.sh against real git repos in a temp dir.
#
# Scope: which listed paths are counted at all. Each skip of the scope list --
# symlinks; anything not a regular file (a deleted tracked file, a gitlink, a
# nested repo, a FIFO standing in for a file); unreadable files with their
# stderr notice and sign-off count; binaries, tracked or not; the built-ins
# plugin-dev/, root plans/, uv.lock and package-lock.json at any depth; files
# marked linguist-generated, and a failed attribute lookup failing the run -- and
# the files that DO count: untracked ones, and paths holding a space or a
# newline. Every exclusion fixture is over the cap exactly where only its own
# exclusion keeps it out. Siblings: check-size-exempt-test.sh (size.exempt) and
# check-size-report-test.sh (formats, counts, sign-off).
#
# The cap is read from the script's own `cap=<n>` line.
#
# Usage: bash tests/check-size-scope-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo, never this repo.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
check="$repo_root/toolkit/check-size.sh"

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

# The cap, read from the script. Absent script: a failure, and a stand-in value
# so the scenarios below still run and fail on their own account.
cap="$(sed -n 's/^cap=\([0-9][0-9]*\)$/\1/p' "$check" 2>/dev/null || true)"
if ! [[ "$cap" =~ ^[0-9]+$ ]]; then
    fail "toolkit/check-size.sh has no line 'cap=<digits>'"
    cap=20000
fi
over=$((cap + 1))

# xs <n>: n bytes of x, no newline.
xs() { head -c "$1" /dev/zero | tr '\0' x; }

# mk_repo: a fresh git repo $repo whose own path holds a space, no commit.
mk_repo() {
    sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/check-size-scope.XXXXXX")" && pwd -P)"
    sandboxes+=("$sandbox")
    repo="$sandbox/plug in"
    mkdir -p "$repo"
    git -C "$repo" init -q
}

# put_big <path> [n]: a file under $repo with n (default: over the cap)
# bytes. put_small <path>: a file well within the cap.
put_big() {
    mkdir -p "$(dirname "$repo/$1")"
    xs "${2:-$over}" > "$repo/$1"
}
put_small() {
    mkdir -p "$(dirname "$repo/$1")"
    printf 'small\n' > "$repo/$1"
}

# commit_in <dir>: commit everything in a repo, ignores respected.
commit_in() {
    git -C "$1" add -A
    git -C "$1" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false \
        commit -q -m fixture
}

# run_check: run the script with cwd at $repo and a UTF-8 locale it must
# override. Sets $rc, $out, $err. A missing script is rc 127.
run_check() {
    rc=0
    (cd "$repo" && env -u LC_ALL LANG=en_US.UTF-8 bash "$check" \
        >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
    out="$(cat "$sandbox/stdout")"
    err="$(cat "$sandbox/stderr")"
}

# expect_pass <label>: exit 0 and nothing on stderr.
expect_pass() {
    assert_eq "$rc" "0" "$1: exit code"
    assert_eq "$err" "" "$1: stderr"
}

echo "=== symlinks are skipped, a dangling one too ==="
mk_repo
put_small keep.txt
xs "$over" > "$sandbox/outside.txt"
ln -s "$sandbox/outside.txt" "$repo/link-to-big.txt"
ln -s "$sandbox/nowhere" "$repo/dangling.txt"
commit_in "$repo"
run_check
expect_pass "symlinks"
assert_contains "$out" ", 2 symlinks, " "symlinks: sign-off count"

echo "=== a tracked file deleted from disk is skipped ==="
mk_repo
put_small keep.txt
put_big gone.txt
commit_in "$repo"
rm "$repo/gone.txt"
run_check
expect_pass "deleted tracked file"

echo "=== a nested repo, untracked and as a tracked gitlink, is skipped ==="
mk_repo
put_small keep.txt
git -C "$repo" init -q nested-untracked
put_big nested-untracked/big.txt
commit_in "$repo/nested-untracked"
git -C "$repo" init -q nested-tracked
put_big nested-tracked/big.txt
commit_in "$repo/nested-tracked"
git -C "$repo" add keep.txt nested-tracked
run_check
expect_pass "nested repos"

echo "=== a FIFO standing where a tracked file was is skipped ==="
# A char-device mask needs root to create; a FIFO is the non-regular stand-in
# any user can make. git lists it only because the index still names it. The
# background writer lets an unskipped read finish and report instead of hang.
mk_repo
put_small keep.txt
put_big pipe.txt
commit_in "$repo"
rm "$repo/pipe.txt"
mkfifo "$repo/pipe.txt"
{ xs "$over" > "$repo/pipe.txt"; } &
writer=$!
run_check
kill "$writer" 2>/dev/null || true
wait "$writer" 2>/dev/null || true
expect_pass "fifo"

echo "=== an unreadable file is skipped with a notice and counted ==="
if [ "$(id -u)" -eq 0 ]; then
    # Root reads through mode 000, so the fixture cannot exist.
    printf 'SKIP: unreadable file -- running as root, which ignores chmod 000\n'
else
    mk_repo
    put_small keep.txt
    put_big locked.txt
    chmod 000 "$repo/locked.txt"
    run_check
    assert_eq "$rc" "0" "unreadable: exit code"
    assert_contains "$err" "locked.txt" "unreadable: notice names the file"
    assert_contains "$err" "unreadable" "unreadable: notice says so"
    assert_not_contains "$err" "oversized-file" "unreadable: not an overage"
    assert_contains "$out" ", 1 unreadable" "unreadable: sign-off count"
fi

echo "=== binaries are skipped, tracked or untracked ==="
mk_repo
put_small keep.txt
{ printf 'a\0'; xs "$over"; } > "$repo/tracked.bin"
git -C "$repo" add keep.txt tracked.bin
{ printf 'a\0'; xs "$over"; } > "$repo/untracked.bin"
run_check
expect_pass "binaries"
assert_contains "$out" ", 2 binary, " "binaries: sign-off count"
echo "=== the same bytes without the NUL are text and count ==="
mk_repo
{ printf 'a'; xs "$over"; } > "$repo/text.dat"
run_check
assert_eq "$rc" "1" "text twin: exit code"
assert_contains "$err" "oversized-file: text.dat: " "text twin: counted"

echo "=== built-ins: plugin-dev/, root plans/, lock files at any depth ==="
mk_repo
put_small keep.txt
put_big plugin-dev/vendored.sh
put_big plans/plan.md
put_big uv.lock
put_big sub/deep/uv.lock
put_big package-lock.json
put_big web/package-lock.json
commit_in "$repo"
run_check
expect_pass "built-ins"
assert_contains "$out" "skipped: 6 plans/plugin-dev/lockfiles/generated, " "built-ins: sign-off count"

echo "=== the skips run in order: type and readability before built-ins ==="
mk_repo
put_small keep.txt
mkdir -p "$repo/sub"
ln -s ../keep.txt "$repo/sub/uv.lock"
mkdir -p "$repo/plans"
{ printf 'a\0'; xs "$over"; } > "$repo/plans/blob.bin"
unreadable=0
if [ "$(id -u)" -ne 0 ]; then   # root reads through mode 000
    put_big plugin-dev/locked.sh
    chmod 000 "$repo/plugin-dev/locked.sh"
    unreadable=1
fi
run_check
assert_eq "$rc" "0" "skip order: exit code"
assert_contains "$out" "skipped: 0 plans/plugin-dev/lockfiles/generated, 1 binary, 1 symlinks, $unreadable unreadable" \
    "skip order: each file counted by its first skip"
if (( unreadable )); then
    assert_contains "$err" "plugin-dev/locked.sh" "skip order: the notice comes before the built-in"
fi

echo "=== a nested x/plans/, plansx/ and a lookalike lock file count ==="
mk_repo
put_big x/plans/plan.md
put_big plansx/plan.md
put_big uv.lock.bak
put_big notuv.lock
run_check
assert_eq "$rc" "1" "lookalikes: exit code"
for p in x/plans/plan.md plansx/plan.md uv.lock.bak notuv.lock; do
    assert_contains "$err" "oversized-file: $p: " "lookalikes: $p counts"
done

echo "=== an untracked file counts ==="
mk_repo
put_small keep.txt
commit_in "$repo"
put_big drafts/new.md
run_check
assert_eq "$rc" "1" "untracked: exit code"
assert_contains "$err" "oversized-file: drafts/new.md: " "untracked: counted"

echo "=== an ignored file does not count, nor appear in a skip count ==="
mk_repo
printf 'scratch/\nignored.txt\n' > "$repo/.gitignore"
put_big scratch/draft.md
put_big ignored.txt
put_small keep.txt
run_check
expect_pass "ignored"
assert_contains "$out" "skipped: 0 plans/plugin-dev/lockfiles/generated, 0 binary, 0 symlinks, 0 unreadable" \
    "ignored: no skip count moves"

echo "=== linguist-generated files are skipped and counted, others count ==="
mk_repo
printf '%s\n' '*.gen linguist-generated' 'b/** linguist-generated=true' \
    'keep.gen -linguist-generated' 'off.gen linguist-generated=false' \
    'plans/** linguist-generated' > "$repo/.gitattributes"
put_big a.gen
put_big b/deep/x.txt
put_big plans/p.gen
put_big keep.gen
put_big off.gen
put_big plain.txt
run_check
assert_eq "$rc" "1" "generated: exit code"
assert_not_contains "$err" "a.gen" "generated: set is skipped"
assert_not_contains "$err" "b/deep/x.txt" "generated: =true is skipped"
assert_contains "$err" "oversized-file: keep.gen: " "generated: -linguist-generated counts"
assert_contains "$err" "oversized-file: off.gen: " "generated: =false counts"
assert_contains "$err" "oversized-file: plain.txt: " "generated: unmarked counts"
rm "$repo/keep.gen" "$repo/off.gen" "$repo/plain.txt"
run_check
expect_pass "generated only"
assert_contains "$out" "bytes: 1 files;" "generated: only .gitattributes is counted"
assert_contains "$out" "skipped: 3 plans/plugin-dev/lockfiles/generated, " \
    "generated: three skipped, each counted once"

echo "=== a generated file is not a size.exempt entry ==="
mk_repo
printf '%s\n' 'out.gen linguist-generated' > "$repo/.gitattributes"
put_big out.gen
printf '%s\n' 'out.gen # regenerated' > "$repo/size.exempt"
run_check
assert_eq "$rc" "1" "generated entry: exit code"
assert_contains "$err" "size.exempt:1: out.gen — a generated file is always skipped" \
    "generated entry: refused as always skipped"
assert_not_contains "$err" "matches no listed file" "generated entry: not a missing file"

echo "=== a failed attribute lookup fails the run, never a pass ==="
# A `git` wrapper fails only check-attr, after draining its stdin; every other
# git call reaches the real one. Read with its status ignored, the empty output
# would leave no file counted and the oversized one would pass unseen.
mk_repo
put_big big.txt
attr_fail_dir="$sandbox/git-wrapper"
mkdir -p "$attr_fail_dir"
real_git="$(command -v git)"
cat > "$attr_fail_dir/git" <<STUB
#!/bin/sh
if [ "\$1" = "check-attr" ]; then
    cat >/dev/null
    echo "fatal: stub git failing check-attr" >&2
    exit 128
fi
exec "$real_git" "\$@"
STUB
chmod +x "$attr_fail_dir/git"
PATH="$attr_fail_dir:$PATH" run_check
assert_eq "$rc" "1" "attribute lookup failure: exit code"
assert_eq "$out" "" "attribute lookup failure: no sign-off"
assert_contains "$err" "check-size: attribute lookup failed" \
    "attribute lookup failure: reported on stderr"

echo "=== a newline in a name cannot forge a line ==="
mk_repo
put_small a-small.txt
forged=$'forged\noversized-file: lie.txt: 99999 bytes > '"$cap"
printf 'ok\n' > "$repo/$forged"
put_big z-big.txt
run_check
assert_eq "$rc" "1" "forged name: exit code"
assert_contains "$err" "oversized-file: z-big.txt: $over bytes > $cap" \
    "forged name: counts stay aligned with paths"
assert_not_contains "$err" "99999" "forged name: no forged count"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall check-size scope scenarios passed\n'

#!/usr/bin/env bash
# End-to-end test of toolkit/check-size.sh against real git repos in a temp dir.
#
# Scope: what the run says. The exact `oversized-file:` lines for both caps
# (SKILL.md hubs at any depth), LC_ALL=C path order, counts equal to
# `LC_ALL=C tr -d ' \t\n\r\f\v' < FILE | wc -c` with NBSP and multi-byte text
# counted, the one hint line, exit codes, an empty listing as a failure, the
# exact sign-off line and empty files. Siblings: check-size-scope-test.sh
# (scope list) and check-size-exempt-test.sh (size.exempt).
#
# Unlike its siblings this suite pins the caps as literals, 20000 and 10000.
#
# Usage: bash tests/check-size-report-test.sh   (run from repo root)
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

cap=20000
over=$((cap + 1))

# nonws <n>: n non-whitespace bytes, no newline.
nonws() { head -c "$1" /dev/zero | tr '\0' x; }

# mk_repo: a fresh git repo $repo whose own path holds a space, no commit.
mk_repo() {
    sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/check-size-report.XXXXXX")" && pwd -P)"
    sandboxes+=("$sandbox")
    repo="$sandbox/plug in"
    mkdir -p "$repo"
    git -C "$repo" init -q
}

# put_big <path> [n]: a file under $repo with n (default: over the cap)
# non-whitespace bytes. put_small <path>: a file well within the cap.
put_big() {
    mkdir -p "$(dirname "$repo/$1")"
    nonws "${2:-$over}" > "$repo/$1"
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

# run_check: run the script with cwd at ${run_dir:-$repo} and a UTF-8 locale it must
# override, with ${run_path} first on PATH when set. Sets $rc, $out, $err. A
# missing script is rc 127.
run_check() {
    rc=0
    (cd "${run_dir:-$repo}" && env -u LC_ALL LANG=en_US.UTF-8 \
        PATH="${run_path:+$run_path:}$PATH" bash "$check" \
        >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
    out="$(cat "$sandbox/stdout")"
    err="$(cat "$sandbox/stderr")"
}

# expect_pass <label>: exit 0 and nothing on stderr.
expect_pass() {
    assert_eq "$rc" "0" "$1: exit code"
    assert_eq "$err" "" "$1: stderr"
}

# ref_count <file>: the reference count, as a bare number.
ref_count() { echo $(( $(LC_ALL=C tr -d ' \t\n\r\f\v' < "$1" | wc -c) )); }

# rep <string> <times>: the string repeated, no newline.
rep() {
    local chunk="" i
    for ((i = 0; i < 100; i++)); do chunk+="$1"; done
    for ((i = 0; i < $2 / 100; i++)); do printf '%s' "$chunk"; done
}

# overage_lines: the oversized-file: lines of $err, in order.
overage_lines() { grep '^oversized-file: ' <<<"$err" || true; }

echo "=== the line format, one hint line, nothing on stdout ==="
mk_repo
put_big big.txt
run_check
assert_eq "$rc" "1" "format: exit code"
assert_eq "$out" "" "format: stdout"
assert_eq "$(overage_lines)" "oversized-file: big.txt: 20001 non-whitespace bytes > 20000" "format: line"
assert_eq "$(wc -l <<<"$err" | tr -d ' ')" "2" "format: overage line plus one hint line"
hint="$(grep -v '^oversized-file: ' <<<"$err")"
[ -n "$hint" ] || fail "format: no hint line"
if grep -qi 'exempt' <<<"$hint"; then fail "format: the hint advertises an exemption: $hint"; fi

echo "=== the hint comes once, after every overage ==="
mk_repo
put_big a.txt
put_big b.txt
put_big c.txt
run_check
assert_eq "$(wc -l <<<"$err" | tr -d ' ')" "4" "several: three overages and one hint"
assert_eq "$(sed -n 4p <<<"$err" | cut -c1-15)" "$(printf '%s' "$hint" | cut -c1-15)" "several: the hint is last"
assert_eq "$(grep -c '^oversized-file: ' <<<"$err")" "3" "several: three overage lines"

echo "=== exactly the cap passes; whitespace never counts ==="
# padded <n> <file>: n non-whitespace bytes buried in spaces, tabs and CRLF
# line ends (no lone CR: git would call the file binary and it would be skipped).
padded() {
    awk -v n="$1" 'BEGIN { for (i = 0; i < 5000; i++) printf " \t \r\n"
        for (i = 0; i < n; i++) { printf "x"; if (i % 50 == 49) printf " \r\n" } }' > "$2"
}
mk_repo
{ nonws "$cap"; printf '\n'; } > "$repo/at-cap.txt"
padded "$cap" "$repo/padded.txt"
run_check
expect_pass "at the cap"
assert_eq "$(ref_count "$repo/padded.txt")" "20000" "fixture: padded.txt is 20000 non-whitespace"
padded "$over" "$repo/padded-over.txt"
run_check
assert_eq "$(overage_lines)" "oversized-file: padded-over.txt: 20001 non-whitespace bytes > 20000" "one over the cap"

echo "=== SKILL.md has the hub cap at any depth; look-alike names do not ==="
mk_repo
put_big SKILL.md 10001
put_big skills/deep/er/SKILL.md 10001
run_check
assert_eq "$(overage_lines)" "oversized-file: SKILL.md: 10001 non-whitespace bytes > 10000 (SKILL.md hub)
oversized-file: skills/deep/er/SKILL.md: 10001 non-whitespace bytes > 10000 (SKILL.md hub)" "hub: lines"
mk_repo
put_big SKILL.md 10000
for n in skill.md SKILL.md.bak MY-SKILL.md SKILL.mdx; do put_big "lookalike/$n" 15000; done
run_check
expect_pass "hub at its cap, look-alikes under the plain cap"
mk_repo
put_big skills/SKILL.md 20001
run_check
assert_eq "$(overage_lines)" "oversized-file: skills/SKILL.md: 20001 non-whitespace bytes > 10000 (SKILL.md hub)" "hub far over: hub line only"

echo "=== report order is LC_ALL=C byte order, not the listing's ==="
# git lists untracked paths before cached ones, each group sorted, so tracking
# the early names makes the listing out of order: only a sort restores it. No
# two names differ by case alone, which a case-insensitive filesystem merges.
mk_repo
put_big Z.txt
put_big a-b.txt
commit_in "$repo"
for n in b.txt a/b.txt a.txt é.txt; do put_big "$n"; done
run_check
expected=""
for n in Z.txt a-b.txt a.txt a/b.txt b.txt é.txt; do
    expected+="oversized-file: $n: 20001 non-whitespace bytes > 20000"$'\n'
done
assert_eq "$(overage_lines)" "${expected%$'\n'}" "order"

echo "=== counts equal the tr | wc reference ==="
mk_repo
# CRLF lines, a tab, and rare form feed and vertical tab (a lone CR or dense
# control characters would make git call the file binary), no final newline.
awk 'BEGIN { for (i = 1; i <= 1500; i++) {
    printf "abcdefghij klmnopqrst\t uvwxyz\r\n"
    if (i % 100 == 0) printf "x\f\vy\r\n" } printf "tail" }' > "$repo/mixed.txt"
want="$(ref_count "$repo/mixed.txt")"
(( want > cap )) || fail "fixture: mixed.txt reference $want is not over the cap"
run_check
assert_eq "$(overage_lines)" "oversized-file: mixed.txt: $want non-whitespace bytes > 20000" "reference count"

echo "=== NBSP and other multi-byte whitespace-looking text count as bytes ==="
mk_repo
rep $'\302\240' 10100 > "$repo/nbsp.txt"
rep $'\342\200\203' 7000 > "$repo/emspace.txt"
rep 'é ' 10100 > "$repo/accents.txt"
run_check
for n in nbsp emspace accents; do
    assert_eq "$(grep "^oversized-file: $n.txt: " <<<"$err")" \
        "oversized-file: $n.txt: $(ref_count "$repo/$n.txt") non-whitespace bytes > 20000" "multi-byte: $n"
done
assert_eq "$(ref_count "$repo/nbsp.txt")" "20200" "fixture: 10100 NBSP are 20200 bytes"

echo "=== an awk whose length counts characters fails the run, never a pass ==="
mk_repo
put_small a.txt
mkdir -p "$sandbox/fakebin"
# A stand-in for an awk that decodes UTF-8: it answers 1 to every question,
# which is the length such an awk gives a two-byte character.
printf '#!/bin/sh\necho 1\n' > "$sandbox/fakebin/awk"
chmod +x "$sandbox/fakebin/awk"
run_path="$sandbox/fakebin"
run_check
run_path=""
assert_eq "$rc" "1" "character awk: exit code"
assert_eq "$out" "" "character awk: stdout"
assert_contains "$err" "check-size: awk counts characters, not bytes: $sandbox/fakebin/awk" "character awk: reason names the awk"

echo "=== a pass writes nothing to stderr and exits 0 ==="
mk_repo
put_small a.txt
run_check
expect_pass "small repo"

echo "=== an empty listing is a failure, never a pass ==="
mk_repo
run_check
assert_eq "$rc" "1" "no files: exit code"
assert_eq "$out" "" "no files: stdout"
assert_contains "$err" "check-size: " "no files: reason"
mk_repo
printf '*\n' > "$repo/.gitignore"
put_small hidden.txt
run_check
assert_eq "$rc" "1" "all ignored: exit code"
assert_contains "$err" "check-size: " "all ignored: reason"
mk_repo
run_dir="$sandbox"
run_check
assert_eq "$rc" "1" "not a repo: exit code"
assert_contains "$err" "check-size: " "not a repo: reason"
run_dir=""

echo "=== run from a subdirectory: the root listing, root-relative paths ==="
mk_repo
put_small keep.txt
put_big sub/dir/big.txt
put_big top-big.txt
run_dir="$repo/sub/dir"
run_check
run_dir=""
assert_eq "$(overage_lines)" "oversized-file: sub/dir/big.txt: 20001 non-whitespace bytes > 20000
oversized-file: top-big.txt: 20001 non-whitespace bytes > 20000" "subdirectory"

echo "=== empty files are no failure ==="
mk_repo
put_small keep.txt
: > "$repo/empty.txt"
mkdir -p "$repo/skills/x"
: > "$repo/skills/x/SKILL.md"
run_check
expect_pass "empty files"
echo "=== empty files ahead of overages leave every count on its own path ==="
mk_repo
mkdir -p "$repo/a"
: > "$repo/a/SKILL.md"
put_big b/SKILL.md 10001
: > "$repo/empty.txt"
put_big m-big.txt
put_small z-small.txt
run_check
assert_eq "$(overage_lines)" "oversized-file: b/SKILL.md: 10001 non-whitespace bytes > 10000 (SKILL.md hub)
oversized-file: m-big.txt: 20001 non-whitespace bytes > 20000" "empties: counts aligned"

echo "=== the sign-off names every check and its count ==="
mk_repo
put_small a.txt
mkdir -p "$repo/b"
printf 'hub-doc\n' > "$repo/b/SKILL.md"
put_big plans/p.md
put_big plugin-dev/x.sh
put_big uv.lock
put_big sub/package-lock.json
printf 'a\0b\n' > "$repo/blob.bin"
ln -s a.txt "$repo/link.txt"
commit_in "$repo"
run_check
expect_pass "sign-off"
assert_eq "$out" "check-size: cap 20000 non-whitespace bytes: 2 files; hub cap 10000: 1 SKILL.md; size.exempt: 0 entries, each with a reason and still needed; skipped: 4 plans/plugin-dev/lockfiles, 1 binary, 1 symlinks, 0 unreadable" "sign-off line"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall check-size report scenarios passed\n'

#!/usr/bin/env bash
# End-to-end test of toolkit/check-size.sh against real git repos in a temp dir.
#
# Scope: the root size.exempt file. Each refusal (an entry with no reason, one
# matching no listed file, a file entry within its cap, a repeat of a built-in,
# a repeat of another entry) is one `size.exempt:<n>: <path> -- <why>` line and
# a failed run; a file entry over its cap passes; a directory entry matches
# whole components only; entries add to the built-ins; comment, blank and CR
# lines are skipped. Siblings: check-size-scope-test.sh (scope list) and
# check-size-report-test.sh (formats, counts, sign-off).
#
# The caps are read from the script's own `cap=<n>` and `hub_cap=<n>` lines.
#
# Usage: bash tests/check-size-exempt-test.sh   (run from repo root)
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
hub_cap="$(sed -n 's/^hub_cap=\([0-9][0-9]*\)$/\1/p' "$check" 2>/dev/null || true)"
if ! [[ "$hub_cap" =~ ^[0-9]+$ ]]; then
    fail "toolkit/check-size.sh has no line 'hub_cap=<digits>'"
    hub_cap=10000
fi
over=$((cap + 1))

# xs <n>: n bytes of x, no newline.
xs() { head -c "$1" /dev/zero | tr '\0' x; }
# blanks <n>: n bytes of nothing but spaces and newlines.
blanks() { head -c "$1" < <(yes ' '); }

# mk_repo: a fresh git repo $repo whose own path holds a space, no commit.
mk_repo() {
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/check-size-exempt.XXXXXX")" || exit 1
    sandbox="$(cd "$sandbox" && pwd -P)"
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

# exempt <line...>: write the root size.exempt, one argument per line.
exempt() { printf '%s\n' "$@" > "$repo/size.exempt"; }

# expect_refused <label> <n> <path>: failed run, no sign-off, and the one
# `size.exempt:<n>: <path> — <why>` line on stderr.
expect_refused() {
    assert_eq "$rc" "1" "$1: exit code"
    assert_eq "$out" "" "$1: stdout"
    assert_contains "$err" "size.exempt:$2: $3 — " "$1: refusal line"
}

echo "=== control: the file is over the cap with no size.exempt ==="
mk_repo
put_big big.txt
run_check
assert_eq "$rc" "1" "control: exit code"
assert_contains "$err" "oversized-file: big.txt: " "control: reported"

echo "=== a file entry over its cap passes, and is counted in the sign-off ==="
mk_repo
put_big big.txt
put_small keep.txt
exempt 'big.txt # long table, no seam'
run_check
expect_pass "file entry"
assert_contains "$out" "size.exempt: 1 entries, each with a reason and still needed" "file entry: sign-off"

echo "=== a spaced path, extra blanks before the hash, two entries ==="
mk_repo
put_big "my dir/big file.txt"
put_big big.txt
exempt 'my dir/big file.txt    # why' 'big.txt # why'
run_check
expect_pass "spaced entry"
assert_contains "$out" "size.exempt: 2 entries," "spaced entry: both counted"

echo "=== a file entry at exactly the cap, and a hub over its own cap ==="
mk_repo
put_big at-cap.txt "$cap"
exempt 'at-cap.txt # why'
run_check
expect_refused "entry at the cap" 1 "at-cap.txt"
mk_repo
put_big skills/a/SKILL.md "$((hub_cap + 1))"
exempt 'skills/a/SKILL.md # hub that outgrew its cap'
run_check
expect_pass "hub entry over the hub cap, under the cap"
mk_repo
put_big skills/a/SKILL.md "$((hub_cap - 1))"
exempt 'skills/a/SKILL.md # why'
run_check
expect_refused "hub entry within the hub cap" 1 "skills/a/SKILL.md"

echo "=== whitespace counts toward the cap an entry forgives ==="
mk_repo
blanks "$over" > "$repo/blank.txt"
mkdir -p "$repo/skills/a"
blanks "$((hub_cap + 1))" > "$repo/skills/a/SKILL.md"
exempt 'blank.txt # all blanks' 'skills/a/SKILL.md # all blanks'
run_check
expect_pass "whitespace-only files over their caps"
mk_repo
{ xs "$((cap - 1))"; printf '\n'; } > "$repo/at-cap.txt"
exempt 'at-cap.txt # why'
run_check
expect_refused "newline-ended file at exactly the cap" 1 "at-cap.txt"

echo "=== refused: an entry with no reason ==="
for e in 'big.txt' 'big.txt #' 'big.txt #    '; do
    mk_repo
    put_big big.txt
    exempt "$e"
    run_check
    expect_refused "no reason ($e)" 1 "big.txt"
done

echo "=== refused: an entry matching no listed file ==="
mk_repo
put_small keep.txt
put_big big.txt
exempt 'ghost.txt # why' 'ghostdir # why' 'big.tx # why'
run_check
expect_refused "no match" 1 "ghost.txt"
assert_contains "$err" "size.exempt:2: ghostdir — " "no match: directory entry"
assert_contains "$err" "size.exempt:3: big.tx — " "no match: a prefix of a name is not a match"
# A directory on disk whose files are all ignored: only the no-match clause
# refuses it, since no file under it is listed to be within its cap.
mk_repo
put_small keep.txt
printf 'gen/\n' > "$repo/.gitignore"
put_big gen/x.txt
exempt 'gen # generated'
run_check
expect_refused "ignored directory" 1 "gen"

echo "=== each kind of refusal gives its own reason ==="
mk_repo
put_big big.txt
put_big big2.txt
put_small small.txt
put_small plugin-dev/x.sh
exempt 'big.txt' 'ghost.txt # why' 'small.txt # why' 'big2.txt # a' 'big2.txt # b' 'plugin-dev # why'
run_check
# why <n>: the text after the dash on the refusal line for size.exempt line n.
why() { local l; l="$(grep "^size\.exempt:$1: " <<<"$err" || true)"; printf '%s' "${l#*— }"; }
w_reason="$(why 1)" w_match="$(why 2)" w_cap="$(why 3)" w_repeat="$(why 5)" w_builtin="$(why 6)"
for w in "$w_reason" "$w_match" "$w_cap" "$w_repeat" "$w_builtin"; do
    [ -n "$w" ] || fail "reasons: a refusal line is missing or has no reason: $err"
done
kinds=("$w_reason" "$w_match" "$w_cap" "$w_repeat")
for ((i = 0; i < 4; i++)); do
    for ((j = i + 1; j < 4; j++)); do
        [[ "${kinds[i]}" != "${kinds[j]}" ]] || fail "reasons: kinds $i and $j share '${kinds[i]}'"
    done
done
[[ "$w_builtin" != "$w_match" && "$w_builtin" != "$w_cap" ]] \
    || fail "reasons: a built-in repeat is refused as '$w_builtin', not as a repeat"

echo "=== refused: a file entry within its cap ==="
mk_repo
put_small small.txt
exempt 'small.txt # why'
run_check
expect_refused "within cap" 1 "small.txt"

echo "=== refused: a repeat of a built-in ==="
mk_repo
put_small keep.txt
put_small plugin-dev/x.sh
put_small plans/p.md
put_small uv.lock
put_small package-lock.json
put_small sub/uv.lock
exempt 'plugin-dev # why' 'plans # why' 'uv.lock # why' 'package-lock.json # why' 'sub/uv.lock # why'
run_check
expect_refused "built-in repeat" 1 "plugin-dev"
for pair in 2:plans 3:uv.lock 4:package-lock.json 5:sub/uv.lock; do
    assert_contains "$err" "size.exempt:${pair%%:*}: ${pair#*:} — " "built-in repeat: ${pair#*:}"
done

echo "=== refused: a repeat of another entry, named at its later line ==="
mk_repo
put_big big.txt
exempt 'big.txt # first' '# between' 'big.txt # second'
run_check
expect_refused "entry repeat" 3 "big.txt"
assert_not_contains "$err" "size.exempt:1:" "entry repeat: the first stays valid"

echo "=== comment, blank and CR lines are skipped and still numbered ==="
mk_repo
put_small keep.txt
printf '# comment\n\n\r\nghost.txt # why\r\nnoreason.txt\n' > "$repo/size.exempt"
run_check
expect_refused "numbering" 4 "ghost.txt"
assert_contains "$err" "size.exempt:5: noreason.txt — " "numbering: second refusal in the same run"
assert_eq "$(grep -c $'\r' <<<"$err" || true)" "0" "numbering: no CR echoed"

echo "=== a CRLF entry is read whole ==="
mk_repo
put_big big.txt
printf '# comment\r\nbig.txt # why\r\n' > "$repo/size.exempt"
run_check
expect_pass "crlf entry"

echo "=== a directory entry exempts everything below, over cap or not ==="
mk_repo
put_big docs/big.txt
put_big docs/deep/er/big.txt
put_small docs/small.md
exempt 'docs # frozen records'
run_check
expect_pass "directory entry"
mk_repo
put_small docs/a.md
exempt 'docs # a tree it does not govern'
run_check
expect_pass "directory entry, nothing over"

echo "=== a directory entry matches whole components only ==="
mk_repo
put_small docs/a.md
put_big docsx/big.txt
exempt 'docs # why'
run_check
assert_eq "$rc" "1" "docsx: exit code"
assert_contains "$err" "oversized-file: docsx/big.txt: " "docsx: still counted"
assert_not_contains "$err" "size.exempt:" "docsx: the entry itself is fine"
mk_repo
put_small keep.txt
put_big docsx/big.txt
exempt 'docs # why'
run_check
expect_refused "docs matches nothing" 1 "docs"

echo "=== a directory entry's trailing slash is stripped, as in dist.include ==="
mk_repo
put_big docs/x.txt
exempt 'docs/ # frozen records'
run_check
expect_pass "trailing slash"

echo "=== entries add to the built-ins, they do not replace them ==="
mk_repo
put_small keep.txt
put_big big.txt
put_big plugin-dev/x.sh
put_big plans/p.md
put_big uv.lock
put_big web/package-lock.json
exempt 'big.txt # why'
run_check
expect_pass "additive"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall check-size exempt scenarios passed\n'

#!/usr/bin/env bash
# End-to-end test of toolkit/check-modes.sh against real git repos in a temp dir.
#
# The script checks the directory it lives in, so every scenario copies it into
# a fixture repo's plugin-dev/ and runs it as a consumer would. Scenarios: a
# clean vendored dir signs off with its count; a `#!` file at mode 644 is
# refused with `mode-lost: <path from the repo root>` and a hint whose chmod,
# run verbatim, clears it; a file not starting `#!` passes at 644; an untracked
# `#!` file is checked and an ignored one is not; a path with a space; files
# outside the script's directory are not checked; a run from a subdirectory; a
# run outside a work tree; a nested, differently named vendored directory; a
# run with GIT_DIR exported, as a linked worktree's pre-commit hook has it.
# Scripts are invoked by the relative path a consumer's recipe uses.
#
# Hint format the scenarios pin: stderr carries one `mode-lost: <path>` line
# per file, the path from the repo root, then the `chmod +x` command standing
# alone on its own line, every path absolute and single-quoted, runnable
# verbatim with bash from the repo root or any subdirectory (so no `hint:`
# prefix on that line), and the commit advice on a separate line.
#
# Usage: bash tests/check-modes-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo, never this repo.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
check="$repo_root/toolkit/check-modes.sh"

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

# Scenario bookkeeping: a scenario is recapped as passed only if no assertion
# failed between its start and the next one.
passed=()
scenario=""
scenario_failures=0
begin() {
    end_scenario
    scenario="$1"
    scenario_failures=$failures
    echo "=== $1 ==="
}
end_scenario() {
    if [ -n "$scenario" ] && [ "$failures" -eq "$scenario_failures" ]; then
        passed+=("$scenario")
    fi
    scenario=""
}

# mk_repo [dir]: a fresh git repo $repo whose own path holds a space, with the
# script copied into $vdir (default plugin-dev) and made executable. An absent script leaves
# plugin-dev/ without it: the run then fails on its assertions, not here.
mk_repo() {
    sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/check-modes.XXXXXX")" && pwd -P)"
    sandboxes+=("$sandbox")
    repo="$sandbox/plug in"
    vdir="${1:-plugin-dev}"
    mkdir -p "$repo/$vdir"
    git -C "$repo" init -q
    cp "$check" "$repo/$vdir/check-modes.sh" 2>/dev/null || true
    chmod 755 "$repo/$vdir/check-modes.sh" 2>/dev/null || true
}

# put <mode> <path> <first-line>: a file under $repo holding that line.
put() {
    mkdir -p "$(dirname "$repo/$2")"
    printf '%s\n' "$3" > "$repo/$2"
    chmod "$1" "$repo/$2"
}

# run_check [dir [script]]: run the vendored copy with cwd at $repo/<dir>
# (default the repo root), invoked as `bash <script>` with the script path
# relative to that cwd, as a consumer's recipe does (default $vdir/check-modes.sh,
# valid from the root). Sets $rc, $out, $err. A missing script
# is rc 127.
run_check() {
    rc=0
    (cd "$repo/${1:-.}" && env -u LC_ALL LANG=en_US.UTF-8 \
        bash "${2:-$vdir/check-modes.sh}" \
        >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
    out="$(cat "$sandbox/stdout")"
    err="$(cat "$sandbox/stderr")"
}

# expect_pass <label>: exit 0, one sign-off line on stdout, nothing on stderr.
expect_pass() {
    assert_eq "$rc" "0" "$1: exit code"
    assert_eq "$err" "" "$1: stderr"
    assert_eq "$(printf '%s' "$out" | grep -c '')" "1" "$1: one sign-off line"
}

# mode_lost_lines: the stderr lines starting with the refusal tag.
mode_lost_lines() { grep '^mode-lost: ' <<<"$err" || true; }

# run_hint: extract the chmod line printed on stderr and run it verbatim, first
# from a subdirectory the user's shell may sit in, then from the repo root. A
# missing or doubled line is a failure, not a skipped step.
run_hint() {
    local hint n hint_rc
    hint="$(grep 'chmod +x' <<<"$err" || true)"
    n="$(printf '%s' "$hint" | grep -c '' || true)"
    assert_eq "$n" "1" "$1: exactly one chmod hint line"
    if [ -n "$hint" ]; then
        mkdir -p "$repo/sub dir"
        hint_rc=0
        (cd "$repo/sub dir" && bash -c "$hint") >/dev/null 2>&1 || hint_rc=$?
        assert_eq "$hint_rc" "0" "$1: the hint command runs verbatim from a subdirectory"
        hint_rc=0
        (cd "$repo" && bash -c "$hint") >/dev/null 2>&1 || hint_rc=$?
        assert_eq "$hint_rc" "0" "$1: the hint command runs verbatim from the root"
    fi
}

begin "a clean vendored dir signs off with its count"
mk_repo
put 755 plugin-dev/a.sh '#!/usr/bin/env bash'
put 755 plugin-dev/bin/claude '#!/bin/sh'
put 644 plugin-dev/README.md '# not a script'
put 755 plugin-dev/data.bin 'plain'
put 755 elsewhere/tool.sh '#!/bin/sh'
git -C "$repo" add -A
run_check
expect_pass "clean"
run_check . "$repo/plugin-dev/check-modes.sh"
expect_pass "clean, absolute script path"
run_check
# Three #! files in plugin-dev/: check-modes.sh itself, a.sh and bin/claude.
# The non-#! files at 644 and 755 and the file outside differ the totals.
if ! grep -qw 3 <<<"$out"; then
    fail "clean: sign-off does not name the count 3: '$out'"
fi

begin "a #! file at 644 is refused, and the hint's chmod clears it"
mk_repo
put 755 plugin-dev/ok.sh '#!/bin/sh'
put 644 plugin-dev/lost.sh '#!/bin/sh'
put 644 plugin-dev/bin/claude '#!/usr/bin/env bash'
git -C "$repo" add -A
run_check
assert_eq "$rc" "1" "lost: exit code"
assert_eq "$out" "" "lost: no sign-off on stdout"
assert_contains "$err" "mode-lost: plugin-dev/lost.sh" "lost: names the file"
assert_contains "$err" "mode-lost: plugin-dev/bin/claude" "lost: names the nested file"
assert_not_contains "$err" "ok.sh" "lost: the executable file is not named"
assert_eq "$(mode_lost_lines | grep -c '')" "2" "lost: one line per file"
assert_contains "$err" "commit" "lost: hint says to commit"
assert_contains "$err" "lost.sh" "lost: hint reaches the path"
run_hint "lost"
run_check
expect_pass "lost: rerun after the hint"

begin "a file not starting with #! passes at 644"
mk_repo
put 644 plugin-dev/README.md '# not a script'
put 644 plugin-dev/data.txt 'plain'
put 644 plugin-dev/spaced.sh ' #!/bin/sh'
put 644 plugin-dev/late.sh 'x#!/bin/sh'
: > "$repo/plugin-dev/empty.sh"
chmod 644 "$repo/plugin-dev/empty.sh"
printf '#' > "$repo/plugin-dev/one-byte"
chmod 644 "$repo/plugin-dev/one-byte"
git -C "$repo" add -A
run_check
expect_pass "non-shebang"

begin "an untracked #! file is checked, an ignored one is not"
mk_repo
printf 'plugin-dev/ignored.sh\n' > "$repo/.gitignore"
put 755 plugin-dev/tracked.sh '#!/bin/sh'
git -C "$repo" add .gitignore plugin-dev/tracked.sh
put 644 plugin-dev/untracked.sh '#!/bin/sh'
put 644 plugin-dev/ignored.sh '#!/bin/sh'
run_check
assert_eq "$rc" "1" "untracked: exit code"
assert_contains "$err" "mode-lost: plugin-dev/untracked.sh" "untracked: checked"
assert_not_contains "$err" "ignored.sh" "untracked: ignored file is not"

begin "a path with a space is named and the hint's quoting survives it"
mk_repo
put 644 "plugin-dev/my dir/two words.sh" '#!/bin/sh'
put 644 "plugin-dev/caf"$'\303\251'".sh" '#!/bin/sh'
git -C "$repo" add -A
run_check
assert_eq "$rc" "1" "space: exit code"
assert_contains "$err" "mode-lost: plugin-dev/caf"$'\303\251'".sh" "space: non-ASCII name, raw not C-quoted"
assert_contains "$err" "mode-lost: plugin-dev/my dir/two words.sh" "space: names the whole path"
run_hint "space"
run_check
expect_pass "space: rerun after the hint"

begin "a file outside the script's directory is not checked"
mk_repo
put 644 top.sh '#!/bin/sh'
put 644 other/tool.sh '#!/bin/sh'
put 644 plugin-dev-extra/tool.sh '#!/bin/sh'
git -C "$repo" add -A
run_check
expect_pass "outside"

begin "a run from a subdirectory still checks the script's directory"
mk_repo
put 644 plugin-dev/bin/lost.sh '#!/bin/sh'
put 644 other/tool.sh '#!/bin/sh'
mkdir -p "$repo/docs"
git -C "$repo" add -A
run_check docs ../plugin-dev/check-modes.sh
assert_eq "$rc" "1" "subdir: exit code"
assert_contains "$err" "mode-lost: plugin-dev/bin/lost.sh" "subdir: path from the repo root"
assert_not_contains "$err" "other/tool.sh" "subdir: still only its own directory"
run_check plugin-dev/bin ../check-modes.sh
assert_eq "$rc" "1" "inside the checked dir: exit code"
assert_contains "$err" "mode-lost: plugin-dev/bin/lost.sh" "inside the checked dir: path from the repo root"
run_hint "subdir"
run_check docs ../plugin-dev/check-modes.sh
expect_pass "subdir: clean"

begin "a nested, differently named vendored dir is the one checked"
mk_repo "vendor/plug dev"
put 644 "vendor/plug dev/lost.sh" '#!/bin/sh'
put 644 plugin-dev/decoy.sh '#!/bin/sh'
git -C "$repo" add -A
run_check
assert_eq "$rc" "1" "nested prefix: exit code"
assert_contains "$err" "mode-lost: vendor/plug dev/lost.sh" "nested prefix: path from the repo root"
assert_not_contains "$err" "decoy.sh" "nested prefix: a plugin-dev/ beside it is not read"
run_hint "nested prefix"
run_check
expect_pass "nested prefix: rerun after the hint"

# A linked worktree's pre-commit hook exports GIT_DIR, and with no
# GIT_WORK_TREE git takes the cwd as the top of the work tree. GIT_DIR alone,
# pointing at a plain fixture's .git, reproduces that, with the cwd at the root
# as a hook has it.
begin "GIT_DIR exported as a hook has it: paths from the repo root"
mk_repo
printf 'plugin-dev/ignored.sh\n' > "$repo/.gitignore"
put 644 plugin-dev/lost.sh '#!/bin/sh'
put 644 plugin-dev/ignored.sh '#!/bin/sh'
git -C "$repo" add .gitignore plugin-dev/check-modes.sh plugin-dev/lost.sh
export GIT_DIR="$repo/.git"
run_check
assert_eq "$rc" "1" "git-dir: exit code"
assert_contains "$err" "mode-lost: plugin-dev/lost.sh" "git-dir: path from the repo root"
assert_not_contains "$err" "ignored.sh" "git-dir: the root .gitignore still applies"
run_hint "git-dir"
run_check
expect_pass "git-dir: rerun after the hint"
unset GIT_DIR

begin "outside a work tree: one stderr line, exit 1"
sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/check-modes.XXXXXX")" && pwd -P)"
sandboxes+=("$sandbox")
repo="$sandbox/not a repo"
vdir=plugin-dev
mkdir -p "$repo/$vdir"
cp "$check" "$repo/$vdir/check-modes.sh" 2>/dev/null || true
chmod 755 "$repo/$vdir/check-modes.sh" 2>/dev/null || true
export GIT_CEILING_DIRECTORIES="$sandbox"
run_check
unset GIT_CEILING_DIRECTORIES
assert_eq "$rc" "1" "no work tree: exit code"
assert_eq "$out" "" "no work tree: no stdout"
assert_eq "$(printf '%s' "$err" | grep -c '')" "1" "no work tree: one stderr line"
assert_not_contains "$err" "No such file" "no work tree: the script ran"
assert_not_contains "$err" "mode-lost" "no work tree: not a mode refusal"

end_scenario
if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall check-modes scenarios passed: %s\n' "$(printf '%s; ' "${passed[@]}" | sed 's/; $//')"

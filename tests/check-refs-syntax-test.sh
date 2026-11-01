#!/usr/bin/env bash
# End-to-end test of toolkit/check-refs.sh against real git repos in a temp dir.
#
# Scope: what counts as a reference -- inline links, images and reference
# definitions with a relative target; and what does not -- fenced code, inline
# code spans, a scheme, a pure #anchor, a footnote. Target forms: a #fragment,
# an <angle bracket> target, a trailing title, a %20 escape, a space, a ../
# climb. Its siblings check-refs-scan-test.sh (which files are read, and the
# exemptions) and check-refs-shipped-test.sh (shipped stays shipped) cover the
# rest.
#
# Usage: bash tests/check-refs-syntax-test.sh   (run from repo root)
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
    sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/check-refs-syntax.XXXXXX")" && pwd -P)"
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

echo "=== inline link: a resolving one passes, a broken one is refused ==="
mk_repo
put README.md '# r' '' 'See [the guide](docs/guide.md).'
run_check
expect_pass "resolving inline link"
assert_contains "$out" "1 reference" "resolving inline link: counted"
put README.md '# r' '' 'See [the guide](docs/guide.md).' 'And [gone](docs/gone.md).'
run_check
expect_broken "broken inline link" "README.md:4: docs/gone.md"
assert_not_contains "$err" "guide.md" "broken inline link: the resolving one is not named"

echo "=== image: a broken image target is refused ==="
mk_repo
put README.md '![logo](img/logo.png)'
run_check
expect_broken "broken image" "README.md:1: img/logo.png"
mkdir -p "$repo/img" && : > "$repo/img/logo.png"
run_check
expect_pass "resolving image"

echo "=== reference definition: checked, the usage is not a target ==="
mk_repo
put README.md 'See [the guide][g] and [x].' '' '[g]: docs/guide.md' '  [x]: docs/missing.md "Title"'
run_check
expect_broken "broken reference definition" "README.md:4: docs/missing.md"
assert_not_contains "$err" "docs/guide.md" "reference definition: the resolving one is not named"

echo "=== footnote definition: not a reference ==="
mk_repo
put README.md 'Text.[^1]' '' '[^1]: some prose, not a path'
run_check
expect_pass "footnote"

echo "=== fenced code: links inside are ignored, backticks and tildes ==="
mk_repo
put README.md '# r' '```md' '[a](docs/fenced.md)' '```' '' '~~~~' '[b](docs/tilde.md)' '```' '[c](docs/still.md)' '~~~~' \
    '' '[d](docs/after.md)'
run_check
expect_broken "after the fences" "README.md:12: docs/after.md"
assert_not_contains "$err" "fenced.md" "backtick fence: ignored"
assert_not_contains "$err" "tilde.md" "tilde fence: ignored"
assert_not_contains "$err" "still.md" "a shorter or other fence does not close: ignored"

echo "=== inline code: a link inside a code span is ignored ==="
mk_repo
# shellcheck disable=SC2016  # literal backticks: the Markdown under test
put README.md 'Write `[a](docs/span.md)` or ``[b](docs/double.md) ` x``.' \
    'A span `opened here' '[c](docs/carried.md)` closes on the next line.' '' \
    'Then [d](docs/real.md).'
run_check
expect_broken "after the spans" "README.md:5: docs/real.md"
assert_not_contains "$err" "span.md" "single-backtick span: ignored"
assert_not_contains "$err" "double.md" "double-backtick span: ignored"
assert_not_contains "$err" "carried.md" "a span across a line break: ignored"

echo "=== scheme and anchor: not references ==="
mk_repo
put README.md '[w](https://example.com/x.md) [m](mailto:a@b.c) [f](ftp://h/x)' \
    '[a](#section) [e](<>) [s](/abs/path.md) <https://example.com>'
run_check
expect_pass "scheme, anchor, empty and absolute"
assert_contains "$out" "0 references" "scheme and anchor: none counted"

echo "=== fragment: stripped before the lookup ==="
mk_repo
put README.md '[g](docs/guide.md#usage) [h](docs/gone.md#usage)'
run_check
expect_broken "fragment" "README.md:1: docs/gone.md#usage"
assert_not_contains "$err" "guide.md" "fragment: a resolving target with a fragment passes"

echo "=== angle brackets, a title and %20: the target is decoded ==="
mk_repo
put "docs/with space.md" '# s'
put README.md '[a](<docs/with space.md>) [b](docs/with%20space.md "A title")' \
    "[c](docs/guide.md 'single') [d](<docs/no such.md> \"t\")"
run_check
expect_broken "angle bracket target" "README.md:2: docs/no such.md"
assert_not_contains "$err" "with space" "decoded targets resolve"

echo "=== relative to the containing file, including ../ ==="
mk_repo
put docs/sub/page.md '[up](../guide.md) [here](page.md) [root](../../README.md) [bad](guide.md)'
put README.md '# r'
run_check
expect_broken "file-relative" "docs/sub/page.md:1: guide.md"
assert_not_contains "$err" "../guide.md" "../ climbs from the file's directory"

echo "=== a link split across lines is found on the target's line ==="
mk_repo
put README.md 'Some [long link' 'text](docs/nope.md) here.'
run_check
expect_broken "wrapped link text" "README.md:2: docs/nope.md"

echo "=== several offenders: every one is reported ==="
mk_repo
put README.md '[a](x.md)' '[b](y.md)'
put docs/guide.md '[c](z.md)'
run_check
assert_eq "$rc" "1" "several: exit code"
assert_contains "$err" "README.md:1: x.md — does not exist" "several: first"
assert_contains "$err" "README.md:2: y.md — does not exist" "several: second"
assert_contains "$err" "docs/guide.md:1: z.md — does not exist" "several: third, another file"

echo "=== HTML comments: a link inside one is not a reference ==="
mk_repo
put README.md 'Text <!-- [old](docs/old.md) --> and [x](docs/x.md).' '<!--' '[gone](docs/gone.md)' '-->' \
    '<!-- a --> [y](docs/y.md) <!-- [z](docs/z.md)' 'still hidden [w](docs/w.md) -->'
run_check
assert_eq "$rc" "1" "comments: exit code"
assert_contains "$err" "README.md:1: docs/x.md — does not exist" "comments: a link after a comment is read"
assert_contains "$err" "README.md:5: docs/y.md — does not exist" "comments: a link between comments is read"
assert_not_contains "$err" "old.md" "comments: single-line comment skipped"
assert_not_contains "$err" "gone.md" "comments: multi-line comment skipped"
assert_not_contains "$err" "z.md" "comments: a comment opened mid-line skipped"
assert_not_contains "$err" "w.md" "comments: its continuation skipped"

echo "=== escaped brackets: not a link ==="
mk_repo
put README.md '\[text\](docs/not-a-link.md) and [real](docs/real.md)'
run_check
expect_broken "escaped brackets" "README.md:1: docs/real.md"
assert_not_contains "$err" "not-a-link" "escaped brackets: skipped"

echo "=== a backtick run with a backtick after it is a code span, not a fence ==="
mk_repo
# shellcheck disable=SC2016  # literal backticks: the Markdown under test
put README.md '```just precommit``` is the gate.' '' '[g](docs/gone.md)' '' '```sh' '[ex](docs/example.md)' '```'
run_check
expect_broken "inline triple backticks" "README.md:3: docs/gone.md"
assert_not_contains "$err" "example.md" "inline triple backticks: the real fence is still skipped"

echo "=== a target above the repository root is refused ==="
mk_repo
printf '# outside\n' > "$sandbox/outside.md"
put README.md '[out](../outside.md)'
put docs/a.md '[out](../../outside.md) [root](../)'
run_check
assert_eq "$rc" "1" "leaves the repository: exit code"
assert_contains "$err" "README.md:1: ../outside.md — leaves the repository" "leaves the repository: from the root"
assert_contains "$err" "docs/a.md:1: ../../outside.md — leaves the repository" "leaves the repository: from a subdirectory"
assert_not_contains "$err" "docs/a.md:1: ../ —" "the root itself is in the repository"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall check-refs syntax scenarios passed\n'

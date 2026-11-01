#!/usr/bin/env bash
# End-to-end test of toolkit/check-frontmatter.sh against real git repos in a
# temp dir, with the real PyYAML of the repo's .venv.
#
# Scope: the block itself. A file with no frontmatter block (empty, no opening
# line, an opening line that is not exactly `---`, a block never closed), one
# that is not UTF-8, one whose block is not YAML (`description: a: b`,
# `description: [x`), and one whose block is not a mapping each fail with
# `check-frontmatter: <path>: <reason>` and a reason word, in all three kinds.
# Every case first signs off on a repo holding only a good file of the kind,
# then adds the bad one, so the refusal is the bad file's own. Siblings:
# check-frontmatter-fields-test.sh, -scope-test.sh, -interpreter-test.sh.
#
# Reason words pinned: "block", "UTF-8", "YAML", "mapping".
#
# Usage: bash tests/check-frontmatter-block-test.sh   (run from repo root)
suite=block
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo, never this repo.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into a $(cd … && pwd) capture
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"
check="$repo_root/toolkit/check-frontmatter.sh"
venv_bin="$repo_root/.venv/bin"

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

# The suite parses with the real PyYAML of this repo's venv. A venv without it
# is a broken environment, not a reason to skip: fail the suite outright.
if ! "$venv_bin/python3" -I -c 'import yaml' 2>/dev/null; then
    printf 'FATAL: python3 -I -c "import yaml" fails with %s first on PATH; run uv sync\n' \
        "$venv_bin" >&2
    exit 1
fi

# mk_repo: a fresh git repo $repo whose own path holds a space, no commit.
mk_repo() {
    sandbox="$(cd "$(mktemp -d "${TMPDIR:-/tmp}/check-frontmatter-$suite.XXXXXX")" && pwd -P)"
    sandboxes+=("$sandbox")
    repo="$sandbox/plug in"
    mkdir -p "$repo"
    git -C "$repo" init -q
}

# put <path> <content>: write content verbatim (no added newline) under $repo.
put() {
    mkdir -p "$(dirname "$repo/$1")"
    printf '%s' "$2" > "$repo/$1"
}

# commit_in <dir>: commit everything in a repo, ignores respected.
commit_in() {
    git -C "$1" add -A
    git -C "$1" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false \
        commit -q -m fixture
}

# kind_path <skill|agent|command> <tag>: where a file of that kind lives.
kind_path() {
    case "$1" in
        skill) printf 'skills/%s/SKILL.md' "$2" ;;
        agent) printf 'agents/%s.md' "$2" ;;
        command) printf 'commands/%s.md' "$2" ;;
    esac
}

# signoff <skills> <agents> <commands>: the exact stdout of a passing run.
signoff() { printf 'check-frontmatter ok (%s skills, %s agents, %s commands)' "$1" "$2" "$3"; }

# one_of <kind>: the sign-off of a repo holding exactly one file of that kind.
one_of() {
    case "$1" in
        skill) signoff 1 0 0 ;;
        agent) signoff 0 1 0 ;;
        command) signoff 0 0 1 ;;
    esac
}

good_fm=$'---\ndescription: a fine description\n---\nbody\n'

# run_check: run the script with cwd at $repo, the venv first on PATH
# and the C locale (a UTF-8 file must not depend on the locale). Sets $rc,
# $out, $err and $nlines (stderr line count). A missing script is rc 127.
run_check() {
    rc=0
    (cd "$repo" && env LC_ALL=C PATH="$venv_bin:$PATH" bash "$check" \
        >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
    out="$(cat "$sandbox/stdout")"
    err="$(cat "$sandbox/stderr")"
    nlines="$(wc -l < "$sandbox/stderr" | tr -d ' ')"
}

# expect_ok <label> <sign-off>: exit 0, the exact sign-off, nothing on stderr.
expect_ok() {
    assert_eq "$rc" "0" "$1: exit code"
    assert_eq "$out" "$2" "$1: sign-off"
    assert_eq "$err" "" "$1: stderr"
}

# expect_refusals <label> <n>: exit 1, no sign-off, exactly n stderr lines, all
# of them check-frontmatter refusals.
expect_refusals() {
    assert_eq "$rc" "1" "$1: exit code"
    assert_eq "$out" "" "$1: no sign-off"
    assert_eq "$nlines" "$2" "$1: stderr line count"
    local bad
    bad="$(grep -vc '^check-frontmatter: ' "$sandbox/stderr" || true)"
    assert_eq "$bad" "0" "$1: every stderr line is a check-frontmatter line"
}

# has_refusal <label> <path> <word>...: some stderr line is
# `check-frontmatter: <path>: <reason>` whose reason holds every word.
has_refusal() {
    local label="$1" path="$2" prefix line rest w hit=0 miss
    shift 2
    prefix="check-frontmatter: $path: "
    while IFS= read -r line; do
        [[ "$line" == "$prefix"* ]] || continue
        rest="${line#"$prefix"}"
        miss=0
        for w in "$@"; do
            [[ "$rest" == *"$w"* ]] || miss=1
        done
        if (( miss == 0 )); then hit=1; fi
    done < "$sandbox/stderr"
    if (( hit == 0 )); then
        fail "$label: no line '$prefix<reason with: $*>'"
        printf '  --- stderr ---\n%s\n  --------------\n' "$err" >&2
    fi
}

# refused_one <label> <path> <word>...: exactly one refusal, for that path.
refused_one() {
    local label="$1"
    expect_refusals "$label" 1
    has_refusal "$@"
}

finish() {
    if (( failures > 0 )); then
        printf '\n%d failure(s)\n' "$failures" >&2
        exit 1
    fi
    printf '\nall check-frontmatter %s scenarios passed\n' "$suite"
}

# refuse_in_all_kinds <label> <content> <word>...: a good file of each kind
# signs off; adding one bad file of that kind gives its single refusal.
refuse_in_all_kinds() {
    local label="$1" content="$2" kind bad
    shift 2
    for kind in skill agent command; do
        mk_repo
        put "$(kind_path "$kind" good)" "$good_fm"
        run_check
        expect_ok "$label [$kind] control" "$(one_of "$kind")"
        bad="$(kind_path "$kind" bad)"
        put "$bad" "$content"
        run_check
        refused_one "$label [$kind]" "$bad" "$@"
    done
}

# accept_in_all_kinds <label> <content>: one file of each kind with that
# content signs off.
accept_in_all_kinds() {
    local kind
    for kind in skill agent command; do
        mk_repo
        put "$(kind_path "$kind" fine)" "$2"
        run_check
        expect_ok "$1 [$kind]" "$(one_of "$kind")"
    done
}

echo "=== no block: empty file ==="
refuse_in_all_kinds "empty file" "" "block"

echo "=== no block: plain prose ==="
refuse_in_all_kinds "prose only" $'# Title\n\ndescription: not in a block\n' "block"

echo "=== no block: opening line not exactly --- ==="
refuse_in_all_kinds "trailing space" $'--- \ndescription: x\n---\nbody\n' "block"
refuse_in_all_kinds "leading space" $' ---\ndescription: x\n---\nbody\n' "block"
refuse_in_all_kinds "four dashes" $'----\ndescription: x\n----\nbody\n' "block"
refuse_in_all_kinds "block not on line one" $'\n---\ndescription: x\n---\nbody\n' "block"

echo "=== no block: never closed ==="
refuse_in_all_kinds "unclosed" $'---\ndescription: x\nbody\n' "block"
refuse_in_all_kinds "closing line not exactly ---" $'---\ndescription: x\n--- \nbody\n' "block"

echo "=== not UTF-8 ==="
refuse_in_all_kinds "latin-1 byte" $'---\ndescription: caf\xe9\n---\nbody\n' "UTF-8"

echo "=== block is not YAML ==="
refuse_in_all_kinds "description: a: b" $'---\ndescription: a: b\n---\nbody\n' "YAML"
refuse_in_all_kinds "description: [x" $'---\ndescription: [x\n---\nbody\n' "YAML"
refuse_in_all_kinds "tab indentation" $'---\ndescription: x\n\tname: y\n---\nbody\n' "YAML"

echo "=== block is not a mapping ==="
refuse_in_all_kinds "list" $'---\n- a\n- b\n---\nbody\n' "mapping"
refuse_in_all_kinds "bare scalar" $'---\njust some words\n---\nbody\n' "mapping"
refuse_in_all_kinds "empty block" $'---\n---\nbody\n' "mapping"

echo "=== accepted shapes of the block ==="
accept_in_all_kinds "closing line is the last line, no newline" $'---\ndescription: x\n---'
accept_in_all_kinds "first closing line wins; a later --- and later junk are body" \
    $'---\ndescription: x\n---\nbody\n---\nnot: [yaml\n---\n'
accept_in_all_kinds "non-ASCII UTF-8 under LC_ALL=C" $'---\ndescription: caf\xc3\xa9 \xe2\x80\x94 ok\n---\nbody\n'

echo "=== YAML that executes code, or that PyYAML fails on without a YAMLError ==="
refuse_in_all_kinds "python/object tag" $'---\ndescription: !!python/object/apply:os.getcwd []\n---\nbody\n' "YAML"
refuse_in_all_kinds "impossible date" $'---\ndescription: 2026-13-45\n---\nbody\n' "YAML"
refuse_in_all_kinds "undefined alias" $'---\ndescription: *nope\n---\nbody\n' "YAML"
for odd in 'description: 2026-13-45' 'description: *nope'; do
    mk_repo
    put "$(kind_path skill bad)" $'---\n'"$odd"$'\n---\n'
    put "$(kind_path agent later)" $'no block\n'
    run_check
    expect_refusals "$odd then a later file" 2
    has_refusal "$odd then a later file" "skills/bad/SKILL.md" "YAML"
    has_refusal "$odd then a later file" "agents/later.md" "block"
    assert_not_contains "$err" "Traceback" "$odd: no traceback"
done

echo "=== every refusing file is reported, and the good one is not ==="
mk_repo
put "$(kind_path skill good)" "$good_fm"
put "$(kind_path skill bad)" ""
put "$(kind_path agent bad)" $'---\ndescription: a: b\n---\n'
put "$(kind_path command bad)" $'---\n- x\n---\n'
run_check
expect_refusals "three bad files" 3
has_refusal "three bad files" "skills/bad/SKILL.md" "block"
has_refusal "three bad files" "agents/bad.md" "YAML"
has_refusal "three bad files" "commands/bad.md" "mapping"

finish

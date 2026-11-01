#!/usr/bin/env bash
# End-to-end test of toolkit/check-frontmatter.sh against real git repos in a
# temp dir, with the real PyYAML of the repo's .venv.
#
# Scope: the fields of a well-formed block. `description` missing, not a string
# (a number, a list, a mapping, a YAML boolean, a YAML date), or blank; `name`
# present and not a non-blank string; both at once giving one line each. In
# all three kinds, each after a control that signs off on a good file of the
# kind. Accepted: `name` absent, `name` differing from its directory or file,
# any other field, folded and quoted descriptions. Siblings:
# check-frontmatter-block-test.sh, -scope-test.sh, -interpreter-test.sh.
#
# Reason words pinned: "description" or "name", with "missing", "string" or
# "blank".
#
# Usage: bash tests/check-frontmatter-fields-test.sh   (run from repo root)
suite=fields
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

# fm <body-lines>: a block holding exactly those lines, then a body.
fm() { printf -- '---\n%s\n---\nbody\n' "$1"; }

# refuse_in_all_kinds <label> <content> <word>...: as in the block suite.
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

accept_in_all_kinds() {
    local kind
    for kind in skill agent command; do
        mk_repo
        put "$(kind_path "$kind" fine)" "$2"
        run_check
        expect_ok "$1 [$kind]" "$(one_of "$kind")"
    done
}

echo "=== description missing ==="
refuse_in_all_kinds "only a name" "$(fm 'name: x')" "description" "missing"
refuse_in_all_kinds "only other fields" "$(fm 'tools: [a, b]')" "description" "missing"

echo "=== description not a string ==="
refuse_in_all_kinds "number" "$(fm 'description: 42')" "description" "string"
refuse_in_all_kinds "list" "$(fm 'description: [a, b]')" "description" "string"
refuse_in_all_kinds "mapping" "$(fm $'description:\n  k: v')" "description" "string"
refuse_in_all_kinds "boolean yes" "$(fm 'description: yes')" "description" "string"
refuse_in_all_kinds "date" "$(fm 'description: 2026-11-01')" "description" "string"

echo "=== description blank ==="
refuse_in_all_kinds "empty quotes" "$(fm 'description: ""')" "description" "blank"
refuse_in_all_kinds "spaces" "$(fm 'description: "   "')" "description" "blank"
refuse_in_all_kinds "folded scalar of nothing" "$(fm $'description: >\n  ')" "description" "blank"

echo "=== name present and not a non-blank string ==="
refuse_in_all_kinds "number" "$(fm $'name: 42\ndescription: ok')" "name" "string"
refuse_in_all_kinds "list" "$(fm $'name: [a]\ndescription: ok')" "name" "string"
refuse_in_all_kinds "empty quotes" "$(fm $'name: ""\ndescription: ok')" "name" "blank"
refuse_in_all_kinds "spaces" "$(fm $'name: "  "\ndescription: ok')" "name" "blank"

echo "=== description or name with no value ==="
refuse_in_all_kinds "description with no value" "$(fm 'description:')" "description"
refuse_in_all_kinds "name with no value" "$(fm $'name:\ndescription: ok')" "name"

echo "=== two problems in one file give two lines ==="
mk_repo
put "$(kind_path skill good)" "$good_fm"
put "$(kind_path skill both)" "$(fm 'name: 42')"
run_check
expect_refusals "name and description" 2
has_refusal "name and description" "skills/both/SKILL.md" "name" "string"
has_refusal "name and description" "skills/both/SKILL.md" "description" "missing"

echo "=== accepted: name rules ==="
accept_in_all_kinds "name absent" "$good_fm"
accept_in_all_kinds "name differs from its directory or file" \
    "$(fm $'name: something-else\ndescription: ok')"
accept_in_all_kinds "name with a quoted number string" "$(fm $'name: "42"\ndescription: ok')"

echo "=== accepted: description forms ==="
accept_in_all_kinds "folded block scalar" "$(fm $'description: >\n  one\n  two')"
accept_in_all_kinds "quoted colon" "$(fm 'description: "a: b"')"
accept_in_all_kinds "literal block scalar" "$(fm $'description: |\n  line one\n  line two')"

echo "=== accepted: other fields are not checked ==="
accept_in_all_kinds "unknown and odd fields" \
    "$(fm $'description: ok\ntools: [Read, Grep]\nmodel: 42\nx-extra:\n  nested: [1, 2]\nallowed-tools: yes')"

finish

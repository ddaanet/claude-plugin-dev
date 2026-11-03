#!/usr/bin/env bash
# End-to-end test of toolkit/check-frontmatter.sh against real git repos in a
# temp dir, with the real PyYAML of the repo's .venv.
#
# Scope: the block itself. A file with no frontmatter block (empty, no opening
# line, an opening line that is not exactly `---`, a block never closed), one
# that is not UTF-8, one whose block is not YAML (`description: a: b`,
# `description: [x`), and one whose block is not a mapping each fail with
# `check-frontmatter: <path>: <reason>` and a reason word, in all three kinds.
# In each kind the refusals share one repo, a good control and every bad file
# under a path of its own, checked in one run: each bad file has exactly its one
# stderr line and the control has none, so a refusal is the bad file's own.
# Siblings: check-frontmatter-fields-test.sh, -scope-test.sh, -interpreter-test.sh.
#
# Reason words pinned: "block", "frontmatter", "UTF-8", "YAML", "mapping".
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

# put_good <path>: a valid file for that path. A skill's name is its directory's,
# an agent's or command's its file's stem, so the same fixture passes every
# kind's name rule.
put_good() {
    local n
    case "$1" in
        skills/*/SKILL.md) n="$(basename "$(dirname "$1")")" ;;
        *) n="$(basename "$1" .md)" ;;
    esac
    put "$1" "$(printf -- '---\nname: "%s"\ndescription: a fine description\n---\nbody\n' "$n")"
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

# path_lines <path>: how many stderr lines are about that file.
path_lines() {
    grep -cF -- "check-frontmatter: $1: " "$sandbox/stderr" || true
}

# signoff_of <kind> <n>: the sign-off of a repo holding n files, all of that kind.
signoff_of() {
    case "$1" in
        skill) signoff "$2" 0 0 ;;
        agent) signoff 0 "$2" 0 ;;
        command) signoff 0 0 "$2" ;;
    esac
}

# A batch is one repo of one $kind and one checker run. A cases function declares
# the files with refuse/accept calls; it runs twice, first with mode=put to write
# them and then, after the run, with mode=check to assert on each by its path.
# n numbers the files of a pass, and @NAME@ in a content or a word stands for the
# numbered file's own name, which a skill's `name` must equal.

# refusal_batch <cases-function>: a good control and every refused file, one run.
refusal_batch() {
    mk_repo
    put_good "$(kind_path "$kind" good)"
    mode=put; n=0
    "$1"
    run_check
    mode=check; n=0; expected=0
    "$1"
    expect_refusals "[$kind] refusals" "$expected"
    assert_eq "$(path_lines "$(kind_path "$kind" good)")" "0" "[$kind] refusals: the good file has no line"
}

# acceptance_batch <cases-function>: every accepted file, one run, one sign-off.
acceptance_batch() {
    mk_repo
    mode=put; n=0
    "$1"
    run_check
    mode=check; n=0; accepted=0
    "$1"
    expect_ok "[$kind] accepted" "$(signoff_of "$kind" "$accepted")"
}

# refuse <label> <content> <word>... [-- <word>...]: a refused file at the next
# numbered path of the kind.
refuse() {
    n=$((n + 1))
    local tag="c$n" args=() a
    for a in "${@:2}"; do
        args+=("${a//@NAME@/$tag}")
    done
    refuse_at "$1" "$(kind_path "$kind" "$tag")" "${args[@]}"
}

# refuse_at <label> <path> <content> <word>... [-- <word>...]: a refused file at
# that path. Each `--` separated group of words is one expected stderr line for
# the path, and the path carries no other.
refuse_at() {
    local label="$1 [$kind]" path="$2" count=0 w
    local -a words=()
    if [ "$mode" = put ]; then
        put "$path" "$3"
        return 0
    fi
    shift 3
    for w in "$@" --; do
        if [ "$w" = -- ]; then
            has_refusal "$label" "$path" "${words[@]}"
            count=$((count + 1))
            expected=$((expected + 1))
            words=()
        else
            words+=("$w")
        fi
    done
    assert_eq "$(path_lines "$path")" "$count" "$label: stderr lines for the file"
}

# accept <label> <content>: an accepted file at the next numbered path of the kind.
accept() {
    n=$((n + 1))
    accept_at "$1" "$(kind_path "$kind" "c$n")" "${2//@NAME@/c$n}"
}

# accept_at <label> <path> <content>: an accepted file at that path.
accept_at() {
    if [ "$mode" = put ]; then
        put "$2" "$3"
        return 0
    fi
    accepted=$((accepted + 1))
    assert_eq "$(path_lines "$2")" "0" "$1 [$kind]: stderr lines for the file"
}

finish() {
    if (( failures > 0 )); then
        printf '\n%d failure(s)\n' "$failures" >&2
        exit 1
    fi
    printf '\nall check-frontmatter %s scenarios passed\n' "$suite"
}

block_refusals() {
    refuse "empty file" "" "block"
    refuse "prose only" $'# Title\n\ndescription: not in a block\n' "block"
    refuse "trailing space" $'--- \ndescription: x\n---\nbody\n' "block"
    refuse "leading space" $' ---\ndescription: x\n---\nbody\n' "block"
    refuse "four dashes" $'----\ndescription: x\n----\nbody\n' "block"
    refuse "block not on line one" $'\n---\ndescription: x\n---\nbody\n' "block"
    refuse "unclosed" $'---\ndescription: x\nbody\n' "frontmatter"
    refuse "closing line not exactly ---" $'---\ndescription: x\n--- \nbody\n' "frontmatter"
    refuse "latin-1 byte" $'---\ndescription: caf\xe9\n---\nbody\n' "UTF-8"
    refuse "description: a: b" $'---\ndescription: a: b\n---\nbody\n' "YAML"
    refuse "description: [x" $'---\ndescription: [x\n---\nbody\n' "YAML"
    refuse "tab indentation" $'---\ndescription: x\n\tname: y\n---\nbody\n' "YAML"
    refuse "list" $'---\n- a\n- b\n---\nbody\n' "mapping"
    refuse "bare scalar" $'---\njust some words\n---\nbody\n' "mapping"
    refuse "empty block" $'---\n---\nbody\n' "mapping"
    # YAML that executes code, or that PyYAML fails on without a YAMLError.
    refuse "python/object tag" $'---\ndescription: !!python/object/apply:os.getcwd []\n---\nbody\n' "YAML"
    refuse "impossible date" $'---\ndescription: 2026-13-45\n---\nbody\n' "YAML"
    refuse "undefined alias" $'---\ndescription: *nope\n---\nbody\n' "YAML"
}

block_accepts() {
    accept "closing line is the last line, no newline" $'---\nname: @NAME@\ndescription: x\n---'
    accept "first closing line wins; a later --- and later junk are body" \
        $'---\nname: @NAME@\ndescription: x\n---\nbody\n---\nnot: [yaml\n---\n'
    accept "non-ASCII UTF-8 under LC_ALL=C" $'---\nname: @NAME@\ndescription: caf\xc3\xa9 \xe2\x80\x94 ok\n---\nbody\n'
}

echo "=== refused blocks: no block, not UTF-8, not YAML, not a mapping ==="
for kind in skill agent command; do
    refusal_batch block_refusals
done

echo "=== accepted shapes of the block ==="
for kind in skill agent command; do
    acceptance_batch block_accepts
done

echo "=== a YAML failure that is no YAMLError still lets a later file be read ==="
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
put_good "$(kind_path skill good)"
put "$(kind_path skill bad)" ""
put "$(kind_path agent bad)" $'---\ndescription: a: b\n---\n'
put "$(kind_path command bad)" $'---\n- x\n---\n'
run_check
expect_refusals "three bad files" 3
has_refusal "three bad files" "skills/bad/SKILL.md" "block"
has_refusal "three bad files" "agents/bad.md" "YAML"
has_refusal "three bad files" "commands/bad.md" "mapping"

finish

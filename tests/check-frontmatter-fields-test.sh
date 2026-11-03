#!/usr/bin/env bash
# End-to-end test of toolkit/check-frontmatter.sh against real git repos in a
# temp dir, with the real PyYAML of the repo's .venv.
#
# Scope: the fields of a well-formed block. `description` missing, not a string
# (a number, a list, a mapping, a YAML boolean, a YAML date), or blank; `name`
# present and not a non-blank string; both at once giving one line each. In
# all three kinds, each kind's refusals in one repo with a good control and one
# checker run, the control and every file's own stderr lines asserted by path.
# Accepted: `name` absent, `name` differing from its directory or file,
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

# fm <body-lines>: a block holding exactly those lines, then a body.
fm() { printf -- '---\n%s\n---\nbody\n' "$1"; }

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

# field_refusals: the files of one kind's refusal batch.
field_refusals() {
    local both
    # description missing, not a string, blank
    refuse "only a name" "$(fm 'name: @NAME@')" "description" "missing"
    refuse "only other fields" "$(fm $'name: @NAME@\ntools: [a, b]')" "description" "missing"
    refuse "description number" "$(fm $'name: @NAME@\ndescription: 42')" "description" "string"
    refuse "description list" "$(fm $'name: @NAME@\ndescription: [a, b]')" "description" "string"
    refuse "description mapping" "$(fm $'name: @NAME@\ndescription:\n  k: v')" "description" "string"
    refuse "description boolean yes" "$(fm $'name: @NAME@\ndescription: yes')" "description" "string"
    refuse "description date" "$(fm $'name: @NAME@\ndescription: 2026-11-01')" "description" "string"
    refuse "description empty quotes" "$(fm $'name: @NAME@\ndescription: ""')" "description" "blank"
    refuse "description spaces" "$(fm $'name: @NAME@\ndescription: "   "')" "description" "blank"
    refuse "description folded scalar of nothing" "$(fm $'name: @NAME@\ndescription: >\n  ')" "description" "blank"
    # name present and not a non-blank string
    refuse "name number" "$(fm $'name: 42\ndescription: ok')" "name" "string"
    refuse "name list" "$(fm $'name: [a]\ndescription: ok')" "name" "string"
    refuse "name empty quotes" "$(fm $'name: ""\ndescription: ok')" "name" "blank"
    refuse "name spaces" "$(fm $'name: "  "\ndescription: ok')" "name" "blank"
    # description or name with no value
    refuse "description with no value" "$(fm $'name: @NAME@\ndescription:')" "description"
    refuse "name with no value" "$(fm $'name:\ndescription: ok')" "name"
    # name and description both absent print both, but a command needs no name
    both="$(fm 'tools: [a]')"
    if [ "$kind" = command ]; then
        refuse "both absent: only description" "$both" "description" "missing"
    else
        refuse "both absent" "$both" "name" "missing" -- "description" "missing"
    fi
    case "$kind" in
        skill)
            skill_refusals
            ;;
        agent)
            refuse "name absent" "$(fm 'description: ok')" "name" "missing"
            ;;
    esac
}

# skill_refusals: the refusals only a skill has, a `name` that is not its directory's.
skill_refusals() {
    local v
    refuse "name absent" "$(fm 'description: ok')" "name" "missing"
    refuse_at "two problems in one file give two lines" "skills/both/SKILL.md" "$(fm 'name: 42')" \
        "name" "string" -- "description" "missing"
    refuse_at "wrong name and no description" "skills/dir/SKILL.md" "$(fm 'name: other')" \
        "directory" "dir" "other" -- "description" "missing"
    refuse_at "name differs from the directory" "skills/bad/SKILL.md" "$(fm $'name: other\ndescription: ok')" \
        "directory" "bad" "other"
    refuse_at "name is the top-level component, not the parent" "skills/parent/SKILL.md" \
        "$(fm $'name: skills\ndescription: ok')" "directory" "parent" "skills"
    refuse_at "name differs by case only" "skills/lower/SKILL.md" "$(fm $'name: LOWER\ndescription: ok')" \
        "directory" "lower" "LOWER"
    refuse_at "name is a prefix and a substring of the directory" "skills/abcd/SKILL.md" \
        "$(fm $'name: abc\ndescription: ok')" "directory" "abcd" "abc"
    refuse_at "name extends the directory" "skills/abc/SKILL.md" "$(fm $'name: abcd\ndescription: ok')" \
        "directory" "abc" "abcd"
    refuse_at "name equals the directory but for a trailing space" "skills/trail/SKILL.md" \
        "$(fm $'name: "trail "\ndescription: ok')" "directory" "trail"
    refuse_at "numeric-looking directory, unquoted name is an int" "skills/42/SKILL.md" \
        "$(fm $'name: 42\ndescription: ok')" "name" "string"
    # A blank or non-string name gets that one reason: the count of one line pins
    # that no directory reason is added.
    for v in '""' '"  "'; do
        refuse "blank name $v, no directory reason" "$(fm "name: $v"$'\ndescription: ok')" "name" "blank"
    done
    for v in '42' '[a]'; do
        refuse "non-string name $v, no directory reason" "$(fm "name: $v"$'\ndescription: ok')" "name" "string"
    done
}

# field_accepts: the files of one kind's acceptance batch.
field_accepts() {
    accept "folded block scalar" "$(fm $'name: @NAME@\ndescription: >\n  one\n  two')"
    accept "quoted colon" "$(fm $'name: @NAME@\ndescription: "a: b"')"
    accept "literal block scalar" "$(fm $'name: @NAME@\ndescription: |\n  line one\n  line two')"
    accept "unknown and odd fields" \
        "$(fm $'name: @NAME@\ndescription: ok\ntools: [Read, Grep]\nmodel: 42\nx-extra:\n  nested: [1, 2]\nallowed-tools: yes')"
    case "$kind" in
        skill)
            accept_at "name equals the directory" "skills/bad/SKILL.md" "$(fm $'name: bad\ndescription: ok')"
            accept_at "upper-case directory, same name" "skills/Mixed/SKILL.md" \
                "$(fm $'name: Mixed\ndescription: ok')"
            accept_at "directory with a space" "skills/my skill/SKILL.md" \
                "$(fm $'name: my skill\ndescription: ok')"
            accept_at "numeric-looking directory, quoted name" "skills/42/SKILL.md" \
                "$(fm $'name: "42"\ndescription: ok')"
            ;;
        agent)
            accept_at "name differs from the file" "agents/file-name.md" \
                "$(fm $'name: some-other-name\ndescription: ok')"
            accept_at "nested file, other name" "agents/sub/file-name.md" \
                "$(fm $'name: agents\ndescription: ok')"
            accept_at "name equals the file" "agents/same.md" "$(fm $'name: same\ndescription: ok')"
            ;;
        command)
            accept_at "name absent" "commands/c.md" "$good_fm"
            accept_at "name differs" "commands/d.md" "$(fm $'name: other\ndescription: ok')"
            ;;
    esac
}

echo "=== refused fields: description, name, and a skill's name against its directory ==="
for kind in skill agent command; do
    refusal_batch field_refusals
done

echo "=== accepted: description forms, other fields, names by kind ==="
for kind in skill agent command; do
    acceptance_batch field_accepts
done

finish

#!/usr/bin/env bash
# End-to-end test of toolkit/check-frontmatter.sh against real git repos in a
# temp dir, with the real PyYAML of the repo's .venv.
#
# Scope: which files are read and what the run reports. Paths with a space or an
# apostrophe; an untracked file read, a tracked one read, an ignored one not (the
# same file refused once the ignore is gone); a tracked file deleted from disk
# skipped; agents and commands read at any depth; a reference `.md` under a
# skill, a `skills/SKILL.md`, a deeper `SKILL.md`, a non-`.md`, a nested plugin
# root and files elsewhere not read (each bad, and each beside a control that
# the same content in a read place is refused); the sign-off counts, zeros
# included; a root argument. Siblings: check-frontmatter-block-test.sh,
# -fields-test.sh, -interpreter-test.sh.
#
# Usage: bash tests/check-frontmatter-scope-test.sh   (run from repo root)
suite=scope
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

# commit_in <dir>: commit everything in a repo, ignores respected.
commit_in() {
    git -C "$1" add -A
    git -C "$1" -c user.name=t -c user.email=t@t.invalid -c commit.gpgsign=false \
        commit -q -m fixture
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

bad_fm=$'no frontmatter here\n'

echo "=== paths with a space and an apostrophe ==="
mk_repo
put_good "skills/my skill/SKILL.md"
put_good "agents/my agent.md"
put_good "commands/it's here.md"
run_check
expect_ok "spaced names pass" "$(signoff 1 1 1)"
put "skills/my skill/SKILL.md" "$bad_fm"
put "agents/my agent.md" "$bad_fm"
put "commands/it's here.md" "$bad_fm"
run_check
expect_refusals "spaced names refused" 3
has_refusal "spaced names refused" "skills/my skill/SKILL.md" "block"
has_refusal "spaced names refused" "agents/my agent.md" "block"
has_refusal "spaced names refused" "commands/it's here.md" "block"

echo "=== untracked and tracked files are read; ignored are not ==="
mk_repo
put_good "skills/tracked/SKILL.md"
commit_in "$repo"
put "skills/tracked/SKILL.md" "$bad_fm"
put "agents/untracked.md" "$bad_fm"
run_check
expect_refusals "tracked (modified) and untracked" 2
has_refusal "tracked and untracked" "skills/tracked/SKILL.md" "block"
has_refusal "tracked and untracked" "agents/untracked.md" "block"

mk_repo
put_good "skills/good/SKILL.md"
put "skills/ignored/SKILL.md" "$bad_fm"
put "agents/ignored.md" "$bad_fm"
put ".gitignore" $'skills/ignored/\nagents/ignored.md\n'
run_check
expect_ok "ignored files are not read" "$(signoff 1 0 0)"
rm "$repo/.gitignore"
run_check
expect_refusals "same files without the ignore" 2
has_refusal "same files without the ignore" "skills/ignored/SKILL.md" "block"
has_refusal "same files without the ignore" "agents/ignored.md" "block"

echo "=== a listed file gone from disk is skipped ==="
mk_repo
put_good "skills/good/SKILL.md"
put "skills/gone/SKILL.md" "$bad_fm"
put "agents/gone.md" "$bad_fm"
commit_in "$repo"
run_check
expect_refusals "control: committed bad files are read" 2
rm "$repo/skills/gone/SKILL.md" "$repo/agents/gone.md"
run_check
expect_ok "deleted tracked files" "$(signoff 1 0 0)"

echo "=== agents and commands are read at any depth ==="
mk_repo
put_good "agents/top.md"
put_good "agents/sub/deep.md"
put_good "commands/ns/deeper/x.md"
run_check
expect_ok "nested pass" "$(signoff 0 2 1)"
put "agents/sub/deep.md" "$bad_fm"
put "commands/ns/deeper/x.md" "$bad_fm"
run_check
expect_refusals "nested bad" 2
has_refusal "nested bad" "agents/sub/deep.md" "block"
has_refusal "nested bad" "commands/ns/deeper/x.md" "block"

echo "=== files outside the three globs are not read ==="
mk_repo
put_good "skills/good/SKILL.md"
put "skills/good/reference.md" "$bad_fm"
put "skills/good/references/node.md" "$bad_fm"
put "skills/SKILL.md" "$bad_fm"
put "skills/good/deeper/SKILL.md" "$bad_fm"
put "skills/good/SKILL.txt" "$bad_fm"
put "agents/notes.txt" "$bad_fm"
put "commands/run.sh" "$bad_fm"
put "README.md" "$bad_fm"
put "docs/guide.md" "$bad_fm"
put "plugin/skills/inner/SKILL.md" "$bad_fm"
put "plugin/agents/inner.md" "$bad_fm"
run_check
expect_ok "unread places" "$(signoff 1 0 0)"
# Control: the same content where it is read is refused, so the pass above is
# not the fixture being fine.
put "skills/other/SKILL.md" "$bad_fm"
put "agents/other.md" "$bad_fm"
run_check
expect_refusals "control: same content in read places" 2
has_refusal "control" "skills/other/SKILL.md" "block"
has_refusal "control" "agents/other.md" "block"

echo "=== sign-off counts ==="
mk_repo
put_good "skills/a/SKILL.md"
put_good "skills/b/SKILL.md"
put_good "agents/a.md"
put_good "agents/n/b.md"
put_good "agents/c.md"
put_good "commands/a.md"
run_check
expect_ok "2 skills, 3 agents, 1 command" "$(signoff 2 3 1)"

echo "=== zero files signs off with zeros ==="
mk_repo
run_check
expect_ok "empty repo" "$(signoff 0 0 0)"
put "README.md" "$bad_fm"
put "docs/x.md" "$bad_fm"
run_check
expect_ok "only unrelated files" "$(signoff 0 0 0)"
mk_repo
put_good "skills/only/SKILL.md"
run_check
expect_ok "skills only" "$(signoff 1 0 0)"

echo "=== a root argument ==="
mk_repo
put_good "skills/good/SKILL.md"
put "agents/bad.md" "$bad_fm"
elsewhere="$sandbox/elsewhere dir"
mkdir -p "$elsewhere"
rc=0
(cd "$elsewhere" && env LC_ALL=C PATH="$venv_bin:$PATH" bash "$check" "$repo" \
    >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
out="$(cat "$sandbox/stdout")"
err="$(cat "$sandbox/stderr")"
nlines="$(wc -l < "$sandbox/stderr" | tr -d ' ')"
refused_one "root argument from another directory" "agents/bad.md" "block"
rm "$repo/agents/bad.md"
rc=0
(cd "$elsewhere" && env LC_ALL=C PATH="$venv_bin:$PATH" bash "$check" "$repo" \
    >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
out="$(cat "$sandbox/stdout")"
err="$(cat "$sandbox/stderr")"
expect_ok "root argument, good plugin" "$(signoff 1 0 0)"

# run_root <dir> <root-arg>: run from <dir> (not a repo) with a root argument.
run_root() {
    rc=0
    (cd "$1" && env LC_ALL=C PATH="$venv_bin:$PATH" bash "$check" "$2" \
        >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
    out="$(cat "$sandbox/stdout")"
    err="$(cat "$sandbox/stderr")"
    nlines="$(wc -l < "$sandbox/stderr" | tr -d ' ')"
}

echo "=== a non-ASCII path is read ==="
mk_repo
put_good "skills/é/SKILL.md"
run_check
expect_ok "non-ASCII path passes" "$(signoff 1 0 0)"
put "skills/é/SKILL.md" "$bad_fm"
run_check
refused_one "non-ASCII path refused" "skills/é/SKILL.md" "block"

echo "=== a module planted at the root is not imported ==="
mk_repo
put_good "agents/good.md"
put "yaml.py" $'raise RuntimeError("planted yaml.py was imported")\n'
put "sitecustomize.py" $'raise RuntimeError("planted sitecustomize.py was imported")\n'
run_check
expect_ok "planted yaml.py" "$(signoff 0 1 0)"

echo "=== directory names that only start like a kind are not read ==="
mk_repo
put_good "agents/good.md"
put "agents-old/a.md" "$bad_fm"
put "skills2/a/SKILL.md" "$bad_fm"
put "commands.bak/a.md" "$bad_fm"
run_check
expect_ok "lookalike directories" "$(signoff 0 1 0)"
put "agents/a.md" "$bad_fm"
run_check
refused_one "control: agents/a.md is read" "agents/a.md" "block"

echo "=== a root below the top level reads that subtree alone ==="
mk_repo
put "agents/outer.md" "$bad_fm"
put_good "plugin/agents/good.md"
elsewhere="$sandbox/elsewhere dir"
mkdir -p "$elsewhere"
run_root "$elsewhere" "$repo/plugin"
expect_ok "subtree root, outer bad file unread" "$(signoff 0 1 0)"
put "plugin/skills/s/SKILL.md" "$bad_fm"
run_root "$elsewhere" "$repo/plugin"
refused_one "subtree root, inner bad file" "skills/s/SKILL.md" "block"
run_root "$elsewhere" "$repo"
refused_one "control: the top level reads the outer file" "agents/outer.md" "block"

echo "=== a bad root cannot sign off zeros ==="
mk_repo
run_root "$sandbox" "$sandbox/no such root"
assert_eq "$rc" "1" "nonexistent root: exit code"
assert_eq "$out" "" "nonexistent root: no sign-off"
assert_eq "$(grep -c '^check-frontmatter: ' "$sandbox/stderr")" "1" "nonexistent root: one check-frontmatter line"
assert_contains "$err" "check-frontmatter: " "nonexistent root: prefixed line"
nogit="$sandbox/not a repo"
mkdir -p "$nogit/agents"
printf '%s' "$bad_fm" > "$nogit/agents/bad.md"
run_root "$sandbox" "$nogit"
assert_eq "$rc" "1" "outside a git work tree: exit code"
assert_eq "$out" "" "outside a git work tree: no sign-off"
assert_eq "$(grep -c '^check-frontmatter: ' "$sandbox/stderr")" "1" "outside a git work tree: one check-frontmatter line"
assert_contains "$err" "check-frontmatter: " "outside a git work tree: prefixed line"

finish

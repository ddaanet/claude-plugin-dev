#!/usr/bin/env bash
# End-to-end test of toolkit/check-frontmatter.sh against real git repos in a
# temp dir: the interpreter it needs.
#
# Scope: no `python3` on PATH, and a `python3` that cannot import `yaml`. With a
# file to check, each exits 1 with ONE stderr line naming python3, `pyyaml`,
# `pyproject.toml`, `uv sync`, `.venv/bin` and `.envrc`, never `uv run` or
# `pip`, and no sign-off. With no file to check, neither matters: the run signs
# off with zeros. The narrowed PATH holds symlinks to the system tools and no
# interpreter; the one case that needs a working interpreter there (the
# control) reaches the venv's python3 through a wrapper script that execs it by
# path, never a symlink, which would lose the venv's site-packages. Siblings:
# check-frontmatter-block-test.sh, -fields-test.sh, -scope-test.sh.
#
# Usage: bash tests/check-frontmatter-interpreter-test.sh   (run from repo root)
suite=interpreter
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

# mk_narrow: $narrow, a bin directory of the system tools and no python.
mk_narrow() {
    narrow="$sandbox/narrow bin"
    mkdir -p "$narrow"
    local t p
    for t in git bash sh env mktemp tar sed awk grep cat tr wc sort cut head tail rm mkdir \
        dirname basename find xargs od ls cp mv date uniq tee readlink realpath chmod \
        ln cmp stat expr gzip; do
        p="$(type -P "$t" 2>/dev/null || true)"
        if [[ -n "$p" ]]; then ln -s "$p" "$narrow/$t"; fi
    done
    bash_path="$(type -P bash)"
    assert_eq "$(PATH="$narrow" type -P python3 2>/dev/null || true)" "" \
        "fixture: no python3 reachable on the narrowed PATH"
}

# run_narrow: run the script with only $narrow on PATH.
run_narrow() {
    rc=0
    (cd "$repo" && env LC_ALL=C PATH="$narrow" "$bash_path" "$check" \
        >"$sandbox/stdout" 2>"$sandbox/stderr") || rc=$?
    out="$(cat "$sandbox/stdout")"
    err="$(cat "$sandbox/stderr")"
    nlines="$(wc -l < "$sandbox/stderr" | tr -d ' ')"
}

# expect_remedy <label>: exit 1, no sign-off, one line naming the remedy.
expect_remedy() {
    assert_eq "$rc" "1" "$1: exit code"
    assert_eq "$out" "" "$1: no sign-off"
    assert_eq "$nlines" "1" "$1: exactly one stderr line"
    assert_contains "$err" "check-frontmatter: " "$1: prefixed"
    assert_contains "$err" "python3" "$1: names the interpreter"
    assert_contains "$err" "pyyaml" "$1: names the package"
    assert_contains "$err" "pyproject.toml" "$1: names the dev group file"
    assert_contains "$err" "uv sync" "$1: names the install step"
    assert_contains "$err" ".venv/bin" "$1: names the venv directory"
    assert_contains "$err" ".envrc" "$1: names the PATH wiring"
    assert_not_contains "$err" "uv run" "$1: never suggests uv run"
    assert_not_contains "$err" "pip" "$1: never suggests pip"
}

echo "=== no python3 on PATH, nothing to check: signs off ==="
mk_repo
mk_narrow
put "README.md" "$bad_fm"
put "docs/x.md" "$bad_fm"
run_narrow
assert_eq "$rc" "0" "no python3, zero files: exit code"
assert_eq "$out" "$(signoff 0 0 0)" "no python3, zero files: sign-off"
assert_eq "$err" "" "no python3, zero files: stderr"

echo "=== control: the narrowed PATH suffices once an interpreter is reachable ==="
mk_repo
mk_narrow
put_good "skills/good/SKILL.md"
put "agents/bad.md" "$bad_fm"
printf '#!/bin/sh\nexec "%s/python3" "$@"\n' "$venv_bin" > "$narrow/python3"
chmod +x "$narrow/python3"
run_narrow
refused_one "wrapper to the venv python3" "agents/bad.md" "block"
rm "$repo/agents/bad.md"
run_narrow
expect_ok "wrapper to the venv python3, good plugin" "$(signoff 1 0 0)"

echo "=== no python3 on PATH, files to check: the remedy ==="
rm "$narrow/python3"
run_narrow
expect_remedy "no python3 with a skill"
mk_repo
mk_narrow
put_good "agents/x.md"
run_narrow
expect_remedy "no python3 with an agent"
mk_repo
mk_narrow
put "commands/x.md" "$bad_fm"
run_narrow
expect_remedy "no python3 with a command"

echo "=== a python3 without yaml, files to check: the remedy ==="
mk_repo
mk_narrow
put_good "skills/good/SKILL.md"
stub_log="$sandbox/stub.log"
# Logs the call, then runs the venv's interpreter with -S (no site-packages), so
# the check sees a real ModuleNotFoundError for yaml from a real interpreter.
cat > "$narrow/python3" <<STUB
#!/bin/sh
echo "called" >> "$stub_log"
exec "$venv_bin/python3" -S "\$@"
STUB
chmod +x "$narrow/python3"
run_narrow
expect_remedy "stub python3 without yaml"
if [[ ! -s "$stub_log" ]]; then
    fail "stub python3 without yaml: the stub was never called, so the case is vacuous"
fi
assert_not_contains "$err" "ModuleNotFoundError" \
    "stub python3 without yaml: the interpreter's traceback is not the report"

echo "=== a python3 without yaml, nothing to check: signs off ==="
mk_repo
mk_narrow
put "README.md" "$bad_fm"
cat > "$narrow/python3" <<'STUB'
#!/bin/sh
echo "ModuleNotFoundError: No module named 'yaml'" >&2
exit 1
STUB
chmod +x "$narrow/python3"
run_narrow
assert_eq "$rc" "0" "stub python3, zero files: exit code"
assert_eq "$out" "$(signoff 0 0 0)" "stub python3, zero files: sign-off"
assert_eq "$err" "" "stub python3, zero files: stderr"

finish

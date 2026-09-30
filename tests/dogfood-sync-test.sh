#!/usr/bin/env bash
# End-to-end test of toolkit/dogfood.sh sync against real git repos in a temp
# dir: what the copy holds, what it leaves out, and the usage message. Each
# scenario builds a consumer fixture and runs the script as a consumer would,
# from its vendored spot at plugin-dev/dogfood.sh. The refusals and failures
# are in dogfood-sync-refusal-test.sh.
#
# Usage: bash tests/dogfood-sync-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit`
# leaks GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every
# git command below targets a synthetic fixture repo via `-C`, never this
# repo, so it's always safe to drop them here.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repo_root"

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
    # $1=haystack $2=needle $3=label
    # Residual bound: the needle is a grep BRE matched line by line --
    # a metacharacter in it is live, and a needle that spans a newline
    # can never match.
    if ! printf '%s' "$1" | grep -q -- "$2"; then
        fail "$3: output did not contain '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}
assert_file() {
    # $1=path $2=label : a regular file, not a link
    if [[ ! -f "$1" || -L "$1" ]]; then
        fail "$2: '$1' is not a regular file"
    fi
}
assert_absent() {
    # $1=path $2=label : neither a file, a directory nor a dangling link
    if [[ -e "$1" || -L "$1" ]]; then
        fail "$2: '$1' exists"
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

# make_consumer: build a consumer fixture in a fresh sandbox. Sets $sandbox
# (physical spelling: macOS $TMPDIR sits under a symlink) and $consumer, a
# git repo whose own path contains a space. Tests append the ignore patterns
# and files they need, then call commit_all.
make_consumer() {
    sandbox="$(cd "$(mktemp -d)" && pwd -P)"
    sandboxes+=("$sandbox")
    consumer="$sandbox/my consumer"
    mkdir -p "$consumer/.claude-plugin" "$consumer/skills/demo" "$consumer/plugin-dev"
    git -C "$consumer" init -q
    printf '{"name":"fixture","version":"1.0.0"}\n' > "$consumer/.claude-plugin/plugin.json"
    printf '/dist/plugin/\n' > "$consumer/.gitignore"
    printf '# demo skill\n' > "$consumer/skills/demo/SKILL.md"
    cp "$repo_root/toolkit/dogfood.sh" "$consumer/plugin-dev/dogfood.sh"
    commit_all
}

# commit_all: track everything not ignored in $consumer.
commit_all() {
    git -C "$consumer" add -A
    git -C "$consumer" \
        -c user.name=fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false \
        commit -q --allow-empty -m fixture
}

# make_decoy <dir>: make <dir> a plugin root of its own, a git repo with a
# manifest and /dist/plugin/ ignored, so a script that took its root from <dir>
# would sync there and succeed rather than fail on a non-repo.
make_decoy() {
    mkdir -p "$1/.claude-plugin"
    git -C "$1" init -q
    printf '{"name":"decoy","version":"1.0.0"}\n' > "$1/.claude-plugin/plugin.json"
    printf '/dist/plugin/\n' > "$1/.gitignore"
    git -C "$1" add .claude-plugin/plugin.json .gitignore
    git -C "$1" \
        -c user.name=fixture -c user.email=fixture@example.invalid \
        -c commit.gpgsign=false \
        commit -q -m decoy
}

# run_dogfood <args...>: run the vendored script with the cwd at $sandbox and
# CLAUDE_PROJECT_DIR naming a directory that is not the consumer. Sets $rc,
# $out (stdout) and $err (stderr).
run_dogfood() {
    mkdir -p "$sandbox/elsewhere"
    local errfile="$sandbox/stderr"
    set +e
    out="$(cd "$sandbox" && CLAUDE_PROJECT_DIR="$sandbox/elsewhere" \
        bash "$consumer/plugin-dev/dogfood.sh" "$@" 2>"$errfile")"
    rc=$?
    set -e
    err="$(cat "$errfile")"
}

echo "=== sync copies a tracked file ==="
make_consumer
run_dogfood sync
assert_eq "$rc" "0" "sync copies a tracked file exit code"
assert_eq "$out" "" "sync copies a tracked file prints nothing on stdout"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" "sync copies a tracked file"
if ! cmp -s "$consumer/skills/demo/SKILL.md" "$consumer/dist/plugin/skills/demo/SKILL.md"; then
    fail "sync copies a tracked file: copy bytes differ from the source"
fi
# -ef is true for a hardlink and for a path through a symlinked directory,
# neither of which -L on the file itself sees.
if [[ "$consumer/skills/demo/SKILL.md" -ef "$consumer/dist/plugin/skills/demo/SKILL.md" ]]; then
    fail "sync copies a tracked file: the copy is the source file itself"
fi

echo "=== sync leaves out an ignored file and .git ==="
# Each absence is paired with a presence differing only in what excludes it:
# the tracked kept.log beside the ignored build.log, the tracked
# .claude-plugin/ beside .git. The deep skills/ copy alone would let a sync
# that drops root-level files, or dot-directories, pass.
make_consumer
printf 'build.log\n' >> "$consumer/.gitignore"
printf 'noise\n' > "$consumer/build.log"
printf 'kept\n' > "$consumer/kept.log"
commit_all
run_dogfood sync
assert_eq "$rc" "0" "sync leaves out an ignored file exit code"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "sync leaves out an ignored file: the copy exists"
assert_file "$consumer/dist/plugin/kept.log" \
    "sync leaves out an ignored file: a tracked root-level file is copied"
assert_file "$consumer/dist/plugin/.claude-plugin/plugin.json" \
    "sync leaves out .git: the tracked .claude-plugin/ is copied"
assert_absent "$consumer/dist/plugin/build.log" "sync leaves out an ignored file"
assert_absent "$consumer/dist/plugin/.git" "sync leaves out .git"

echo "=== sync resolves the root from its own location ==="
# The cwd and CLAUDE_PROJECT_DIR are both valid plugin roots, so a script that
# prefers either one, falling back to its own location, syncs the decoy.
make_consumer
make_decoy "$sandbox"
make_decoy "$sandbox/elsewhere"
run_dogfood sync
assert_eq "$rc" "0" "sync resolves the root exit code"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "sync resolves the root from its own location"
assert_absent "$sandbox/elsewhere/dist" "sync resolves the root: CLAUDE_PROJECT_DIR untouched"
assert_absent "$sandbox/dist" "sync resolves the root: cwd untouched"

echo "=== sync keeps a root whose name ends in a newline ==="
# A $(...) capture of the root strips the newline, naming a sibling that does
# not exist, so the manifest check refuses there.
make_consumer
mv "$consumer" "$consumer"$'\n'
consumer+=$'\n'
run_dogfood sync
assert_eq "$rc" "0" "a root ending in a newline: exit code"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "a root ending in a newline: the copy is made inside it"

echo "=== a committed deletion propagates ==="
# The first sync must have put the file in the copy, else its absence after the
# second proves nothing. The sibling SKILL.md stays, so the removal is of one
# file and not of the whole copy.
make_consumer
printf 'gone soon\n' > "$consumer/skills/demo/extra.md"
commit_all
run_dogfood sync
assert_eq "$rc" "0" "a committed deletion propagates: first sync exit code"
assert_file "$consumer/dist/plugin/skills/demo/extra.md" \
    "a committed deletion propagates: the first sync copies the file"
git -C "$consumer" rm -q skills/demo/extra.md
commit_all
run_dogfood sync
assert_eq "$rc" "0" "a committed deletion propagates: second sync exit code"
assert_absent "$consumer/dist/plugin/skills/demo/extra.md" \
    "a committed deletion propagates"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "a committed deletion propagates: the sibling file stays"

echo "=== a tracked file deleted in the worktree does not fail sync ==="
# Deleted but not committed: the index still lists it, the worktree does not
# have it. The first sync puts it in the copy, so its absence afterwards is
# the sync's doing.
make_consumer
printf 'gone soon\n' > "$consumer/skills/demo/extra.md"
commit_all
run_dogfood sync
assert_eq "$rc" "0" "a tracked file deleted in the worktree: first sync exit code"
assert_file "$consumer/dist/plugin/skills/demo/extra.md" \
    "a tracked file deleted in the worktree: the first sync copies the file"
rm "$consumer/skills/demo/extra.md"
if [[ -z "$(git -C "$consumer" ls-files skills/demo/extra.md)" ]]; then
    fail "a tracked file deleted in the worktree: the file is no longer tracked"
fi
run_dogfood sync
assert_eq "$rc" "0" "a tracked file deleted in the worktree exit code"
assert_eq "$err" "" "a tracked file deleted in the worktree prints nothing on stderr"
assert_absent "$consumer/dist/plugin/skills/demo/extra.md" \
    "a tracked file deleted in the worktree: the copy lacks it"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "a tracked file deleted in the worktree: the sibling file stays"

echo "=== a file that becomes ignored leaves the copy ==="
# Unlike the two deletions above, the file stays in the worktree: only its
# leaving the source set through the ignore list can remove it from the copy,
# which is what --delete-excluded does and --delete alone does not.
make_consumer
printf 'ignored soon\n' > "$consumer/skills/demo/extra.md"
commit_all
run_dogfood sync
assert_eq "$rc" "0" "a file that becomes ignored: first sync exit code"
assert_file "$consumer/dist/plugin/skills/demo/extra.md" \
    "a file that becomes ignored: the first sync copies the file"
git -C "$consumer" rm -q --cached skills/demo/extra.md
printf '/skills/demo/extra.md\n' >> "$consumer/.gitignore"
commit_all
assert_file "$consumer/skills/demo/extra.md" \
    "a file that becomes ignored: the file stays in the worktree"
if ! git -C "$consumer" check-ignore -q skills/demo/extra.md; then
    fail "a file that becomes ignored: the file is not ignored"
fi
run_dogfood sync
assert_eq "$rc" "0" "a file that becomes ignored: second sync exit code"
assert_absent "$consumer/dist/plugin/skills/demo/extra.md" \
    "a file that becomes ignored leaves the copy"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "a file that becomes ignored: the sibling file stays"

echo "=== names with spaces survive ==="
# Each ignored name holds whitespace where a different mistake loses it, and is
# excluded only if its entry reaches rsync whole: split apart, the pieces match
# nothing and the file is copied.
# - "out dir/": a wholly ignored directory, collapsed by --directory to one
#   entry. Lost to word splitting.
# - "skills/a b/draft x.log": a lone file in a directory that also holds
#   tracked content, so it is listed as itself, spaces mid-path.
# - " lead.log": lost to a read that trims leading whitespace (no IFS=).
# - "nl<newline>x.log": lost to a newline-delimited list, where git also
#   C-quotes the name.
# The tracked "skills/a b/SKILL.md", sibling of the ignored draft, pairs with
# the absences: a sync that dropped every spaced name would pass them all.
make_consumer
mkdir -p "$consumer/skills/a b" "$consumer/out dir"
printf '# spaced skill\n' > "$consumer/skills/a b/SKILL.md"
printf 'noise\n' > "$consumer/skills/a b/draft x.log"
printf 'noise\n' > "$consumer/out dir/x"
printf 'noise\n' > "$consumer/ lead.log"
printf 'noise\n' > "$consumer/nl"$'\n'"x.log"
printf '/out dir/\n*.log\n' >> "$consumer/.gitignore"
commit_all
# The list must hold each name in the shape described above, or an absence
# below tests some other entry than the one it names.
assert_eq "$(git -C "$consumer" ls-files -z -o -i --exclude-standard --directory |
    tr '\0' '|')" " lead.log|nl"$'\n'"x.log|out dir/|skills/a b/draft x.log|" \
    "names with spaces survive: the fixture's ignore list"
run_dogfood sync
assert_eq "$rc" "0" "names with spaces survive exit code"
assert_file "$consumer/dist/plugin/skills/a b/SKILL.md" \
    "names with spaces survive: a tracked file under a spaced directory is copied"
assert_absent "$consumer/dist/plugin/out dir" \
    "names with spaces survive: an ignored spaced directory is absent"
assert_absent "$consumer/dist/plugin/skills/a b/draft x.log" \
    "names with spaces survive: an ignored spaced file beside a tracked one is absent"
assert_absent "$consumer/dist/plugin/ lead.log" \
    "names with spaces survive: an ignored name with a leading space is absent"
assert_absent "$consumer/dist/plugin/nl"$'\n'"x.log" \
    "names with spaces survive: an ignored name holding a newline is absent"

echo "=== a nested repo's .git stays out ==="
# memory/ is a repo of its own, recorded in the consumer as a gitlink the way a
# mounted memory submodule is: its .git is a gitfile pointing into the
# consumer's .git/modules/, which a directory-only '.git/' exclude would copy.
# memory/tier/ nests a second repo with a .git directory, the other shape. Each
# copied fact.md pairs with an absent .git: a sync that skipped a nested repo
# whole would pass the second.
make_consumer
mkdir -p "$consumer/.git/modules"
git init -q --separate-git-dir "$consumer/.git/modules/memory" "$consumer/memory"
git init -q "$consumer/memory/tier"
printf 'a fact\n' | tee "$consumer/memory/fact.md" > "$consumer/memory/tier/fact.md"
git -C "$consumer/memory" add fact.md
git -C "$consumer/memory" \
    -c user.name=fixture -c user.email=fixture@example.invalid \
    -c commit.gpgsign=false commit -q -m fact
git -C "$consumer" update-index --add --cacheinfo \
    "160000,$(git -C "$consumer/memory" rev-parse HEAD),memory"
commit_all
assert_eq "$(git -C "$consumer" ls-files -s memory | cut -c1-6)" "160000" \
    "a nested repo's .git stays out: memory is a gitlink in the fixture"
assert_file "$consumer/memory/.git" \
    "a nested repo's .git stays out: memory/.git is a gitfile in the fixture"
run_dogfood sync
assert_eq "$rc" "0" "a nested repo's .git stays out exit code"
for p in memory memory/tier; do
    assert_file "$consumer/dist/plugin/$p/fact.md" \
        "a nested repo's .git stays out: $p/fact.md is copied"
    assert_absent "$consumer/dist/plugin/$p/.git" "a nested repo's .git stays out: $p"
done

echo "=== sync never recurses into the copy ==="
# Checked after each sync. The first is the one only the script's own hard
# /dist/plugin/ exclude protects: the copy does not exist when git lists the
# ignored paths, so the ignore list cannot name it. From the second on, the
# ignore list excludes it too, and --delete-excluded clears a nested copy the
# first sync left.
make_consumer
run_dogfood sync
assert_eq "$rc" "0" "sync never recurses into the copy: first sync exit code"
assert_absent "$consumer/dist/plugin/dist/plugin" "sync never recurses into the copy: first sync"
run_dogfood sync
assert_eq "$rc" "0" "sync never recurses into the copy exit code"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "sync never recurses into the copy: the copy exists"
assert_absent "$consumer/dist/plugin/dist/plugin" "sync never recurses into the copy"

echo "=== unknown subcommand is usage ==="
make_consumer
run_dogfood bogus
assert_eq "$rc" "2" "unknown subcommand exit code"
assert_eq "$out" "" "unknown subcommand prints nothing on stdout"
for word in sync pre-tool session-start; do
    assert_contains "$err" "$word" "unknown subcommand usage names $word"
done
run_dogfood
assert_eq "$rc" "2" "no subcommand exit code"
assert_eq "$out" "" "no subcommand prints nothing on stdout"
for word in sync pre-tool session-start; do
    assert_contains "$err" "$word" "no subcommand usage names $word"
done

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall dogfood sync scenarios passed\n'

#!/usr/bin/env bash
# End-to-end test of toolkit/dogfood.sh against real git repos in a temp dir.
# Each scenario builds a consumer fixture and runs the script as a consumer
# would, from its vendored spot at plugin-dev/dogfood.sh.
#
# Usage: bash tests/dogfood-test.sh   (run from repo root)
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

echo "=== an ignored entry holding a pattern character aborts ==="
# One fixture per name, so one name cannot mask another. rsync would read the
# entry as a pattern, so the script refuses before it runs: the sentinel
# pre-placed in the copy survives (it is not source, so --delete would remove
# it) and the committed new.md is not copied. The name is matched as a fixed
# string, not through assert_contains, whose needle is a live BRE.
for name in 'a*b.log' 'a?b.log' 'a[b.log' 'a]b.log' 'a\b.log'; do
    make_consumer
    printf '*.log\n' >> "$consumer/.gitignore"
    printf 'noise\n' > "$consumer/$name"
    commit_all
    printf 'new\n' > "$consumer/skills/demo/new.md"
    commit_all
    assert_eq "$(git -C "$consumer" ls-files -z -o -i --exclude-standard --directory |
        tr '\0' '|')" "$name|" \
        "a pattern character ($name): the fixture's ignore list"
    mkdir -p "$consumer/dist/plugin"
    printf 'keep\n' > "$consumer/dist/plugin/sentinel"
    run_dogfood sync
    assert_eq "$rc" "1" "a pattern character ($name) exit code"
    if [[ "$err" != "dogfood: "*"$name"* || "$err" == *$'\n'* ]]; then
        fail "a pattern character ($name): stderr is not one dogfood: line naming it: '$err'"
    fi
    assert_file "$consumer/dist/plugin/sentinel" \
        "a pattern character ($name): the copy is untouched"
    assert_absent "$consumer/dist/plugin/skills/demo/new.md" \
        "a pattern character ($name): rsync never ran"
done
# Only ignore-list entries reach rsync as patterns: a tracked and an untracked
# name holding every pattern character are source, copied as themselves.
make_consumer
odd='a*?[]\b.md'
printf 'tracked\n' > "$consumer/skills/demo/$odd"
commit_all
printf 'untracked\n' > "$consumer/$odd"
run_dogfood sync
assert_eq "$rc" "0" "a pattern character outside the ignore list: exit code"
assert_file "$consumer/dist/plugin/skills/demo/$odd" \
    "a pattern character outside the ignore list: a tracked name is copied"
assert_file "$consumer/dist/plugin/$odd" \
    "a pattern character outside the ignore list: an untracked name is copied"

echo "=== sync never recurses into the copy ==="
# Residual: /dist/plugin/ is git-ignored here (make_consumer), which slice 6
# makes a precondition, so the ignore list excludes the copy as well and
# dropping the script's own hard /dist/plugin/ exclude survives this test.
make_consumer
run_dogfood sync
run_dogfood sync
assert_eq "$rc" "0" "sync never recurses into the copy exit code"
assert_file "$consumer/dist/plugin/skills/demo/SKILL.md" \
    "sync never recurses into the copy: the copy exists"
assert_absent "$consumer/dist/plugin/dist/plugin" "sync never recurses into the copy"

echo "=== refuses without a root manifest ==="
make_consumer
rm "$consumer/.claude-plugin/plugin.json"
commit_all
run_dogfood sync
assert_eq "$rc" "1" "no manifest exit code"
if [[ "$err" != "dogfood: "*".claude-plugin/plugin.json"* || "$err" == *$'\n'* ]]; then
    fail "no manifest: stderr is not one dogfood: line naming the manifest: '$err'"
fi
assert_absent "$consumer/dist/plugin" "no manifest: the copy is not created"

echo "=== refuses when dist/plugin is not ignored ==="
# The first-sync case: no dist/plugin/ yet. A check that drops the trailing
# slash refuses here too; the first sync of every other test, where
# /dist/plugin/ is ignored, is what reds it. The precondition rules out a
# global excludes file ignoring dist/ behind the emptied .gitignore.
make_consumer
: > "$consumer/.gitignore"
commit_all
assert_absent "$consumer/dist/plugin" "not ignored: the fixture has no copy yet"
if git -C "$consumer" check-ignore -q dist/plugin/; then
    fail "not ignored: the fixture still ignores dist/plugin/"
fi
run_dogfood sync
assert_eq "$rc" "1" "not ignored exit code"
if [[ "$err" != "dogfood: "*"/dist/plugin/"* || "$err" == *$'\n'* ]]; then
    fail "not ignored: stderr is not one dogfood: line naming /dist/plugin/: '$err'"
fi
assert_absent "$consumer/dist/plugin" "not ignored: the copy is not created"

echo "=== a git failure stops sync before rsync ==="
# A stub git first on PATH fails ls-files alone, after the refusal checks have
# passed. Removing .git instead would fail the ignore check's own git call
# first, leaving an unguarded ignore list green. Nothing may reach dist/: rsync
# on a partial ignore list would copy into it.
make_consumer
mkdir "$sandbox/stub"
real_git="$(command -v git)"
cat > "$sandbox/stub/git" <<EOF
#!/usr/bin/env bash
for a; do [[ "\$a" == ls-files ]] && { echo 'git: stub failure' >&2; exit 128; }; done
exec "$real_git" "\$@"
EOF
chmod +x "$sandbox/stub/git"
PATH="$sandbox/stub:$PATH" run_dogfood sync
if [[ "$rc" == "0" ]]; then
    fail "a git failure: exit code is 0"
fi
assert_contains "$err" "git: stub failure" "a git failure: the run reached ls-files"
assert_absent "$consumer/dist" "a git failure: dist/ is not created"

echo "=== an rsync failure keeps its status and stderr ==="
# The stub stands in for rsync alone: git runs for real, so the run reaches
# rsync. Its status and its one stderr line must arrive unaltered.
make_consumer
mkdir "$sandbox/stub"
cat > "$sandbox/stub/rsync" <<'EOF'
#!/usr/bin/env bash
echo 'rsync: stub failure' >&2
exit 23
EOF
chmod +x "$sandbox/stub/rsync"
PATH="$sandbox/stub:$PATH" run_dogfood sync
assert_eq "$rc" "23" "an rsync failure: exit code is rsync's own"
assert_eq "$(printf '%s\n' "$err" | grep -c -x 'rsync: stub failure')" "1" \
    "an rsync failure: its stderr line appears exactly once"

# run_pre_tool <path>: run_dogfood pre-tool, fed an Edit payload naming <path>
# on stdin. The payload is built with jq so a spaced path survives.
run_pre_tool() {
    run_dogfood pre-tool <<<"$(jq -cn --arg p "$1" '{tool_name:"Edit",tool_input:{file_path:$p}}')"
}

# jq_holds <label> <filter> [jq options...]: fail unless <filter> is true over
# $out. Checked in jq rather than on `jq -r` text: its contains() is literal
# where assert_contains' needle is a BRE, a non-string field cannot pass as its
# printed JSON, and a trailing newline in a value is not lost to $(...).
jq_holds() {
    local label="$1" filter="$2"
    shift 2
    if ! printf '%s' "$out" | jq -e "$@" "$filter" >/dev/null 2>&1; then
        fail "$label: $filter is not true over stdout '$out'"
    fi
}

echo "=== pre-tool denies an Edit into the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
run_pre_tool "$root/dist/plugin/skills/demo/SKILL.md"
assert_eq "$rc" "0" "pre-tool denies an Edit into the copy exit code"
assert_eq "$err" "" "pre-tool denies an Edit into the copy prints nothing on stderr"
# Slurped, so a second value or trailing garbage after the object fails here:
# a per-field jq reads the first object and errors only after it.
jq_holds "deny stdout is one JSON object" 'length == 1 and (.[0] | type) == "object"' -s
jq_holds "deny hookEventName" '.hookSpecificOutput.hookEventName == "PreToolUse"'
jq_holds "deny permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "deny reason names the denied path" \
    '.hookSpecificOutput.permissionDecisionReason | type == "string" and contains($p)' \
    --arg p "$root/dist/plugin/skills/demo/SKILL.md"
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "deny additionalContext names the source path" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
    --arg p "$root/skills/demo/SKILL.md"
jq_holds "deny systemMessage names the copy" \
    '.systemMessage | type == "string" and contains("dist/plugin")'
jq_holds "deny systemMessage is one line" \
    '.systemMessage | type == "string" and (test("[\r\n]") | not)'

echo "=== pre-tool allows a source edit ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
run_pre_tool "$root/skills/demo/SKILL.md"
assert_eq "$rc" "0" "pre-tool allows a source edit exit code"
assert_eq "$out" "" "pre-tool allows a source edit prints nothing on stdout"
assert_eq "$err" "" "pre-tool allows a source edit prints nothing on stderr"

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
printf '\nall dogfood scenarios passed\n'

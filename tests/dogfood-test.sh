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
# A parent Claude Code session exports this. The session-start tests set it per
# run or rely on its absence, whichever session launched the suite.
unset CLAUDE_CODE_PLUGIN_DIRS
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

# run_pre_tool <tool> <field> <path>: run_dogfood pre-tool, fed a payload for
# <tool> that names <path> under .tool_input.<field> on stdin. The payload is
# built with jq so a spaced path survives.
run_pre_tool() {
    run_dogfood pre-tool <<<"$(jq -cn --arg t "$1" --arg f "$2" --arg p "$3" \
        '{tool_name:$t,tool_input:{($f):$p}}')"
}

# make_jqless_bin <dir>: <dir> holds symlinks to the commands the script and
# run_dogfood invoke, jq left out. A PATH of <dir> alone reaches those and not
# jq; the caller asserts `command -v jq` fails under it.
make_jqless_bin() {
    local c
    mkdir -p "$1"
    for c in bash dirname mkdir cat; do
        ln -s "$(command -v "$c")" "$1/$c"
    done
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

# assert_denied <label> <root>: the last pre-tool run denied an edit into
# <root>/dist/plugin/skills/demo/SKILL.md, naming that path and its source.
assert_denied() {
    local label="$1" root="$2"
    assert_denied_source "$label" "$root"
    # shellcheck disable=SC2016  # $p is a jq variable bound by --arg
    jq_holds "$label: reason names the denied path" \
        '.hookSpecificOutput.permissionDecisionReason | type == "string" and contains($p)' \
        --arg p "$root/dist/plugin/skills/demo/SKILL.md"
}

# assert_denied_source <label> <root>: the last pre-tool run denied, naming the
# source path <root>/skills/demo/SKILL.md. The reason is not checked for a path:
# the payload may reach the copy without spelling it.
assert_denied_source() {
    local label="$1" root="$2"
    assert_eq "$rc" "0" "$label exit code"
    assert_eq "$err" "" "$label prints nothing on stderr"
    # Slurped, so a second value or trailing garbage after the object fails here:
    # a per-field jq reads the first object and errors only after it.
    jq_holds "$label: stdout is one JSON object" 'length == 1 and (.[0] | type) == "object"' -s
    jq_holds "$label: hookEventName" '.hookSpecificOutput.hookEventName == "PreToolUse"'
    jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
    # shellcheck disable=SC2016  # $p is a jq variable bound by --arg
    jq_holds "$label: additionalContext names the source path" \
        '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
        --arg p "$root/skills/demo/SKILL.md"
    jq_holds "$label: systemMessage names the copy" \
        '.systemMessage | type == "string" and contains("dist/plugin")'
    jq_holds "$label: systemMessage is one line" \
        '.systemMessage | type == "string" and (test("[\r\n]") | not)'
}

echo "=== pre-tool denies an Edit into the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
run_pre_tool Edit file_path "$root/dist/plugin/skills/demo/SKILL.md"
assert_denied "pre-tool denies an Edit into the copy" "$root"

echo "=== pre-tool denies a NotebookEdit into the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
run_pre_tool NotebookEdit notebook_path "$root/dist/plugin/skills/demo/SKILL.md"
assert_denied "pre-tool denies a NotebookEdit into the copy" "$root"

echo "=== pre-tool allows a source edit ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
run_pre_tool Edit file_path "$root/skills/demo/SKILL.md"
assert_eq "$rc" "0" "pre-tool allows a source edit exit code"
assert_eq "$out" "" "pre-tool allows a source edit prints nothing on stdout"
assert_eq "$err" "" "pre-tool allows a source edit prints nothing on stderr"

# The outside path holds /dist/plugin/ itself, so only an anchored prefix
# match, not a substring one, lets it through. It also lies under
# run_dogfood's CLAUDE_PROJECT_DIR, so a root taken from there denies it.
echo "=== pre-tool allows a path outside the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
for pair in \
    "a path outside the repo:$sandbox/elsewhere/dist/plugin/x" \
    "a sibling of the copy:$root/dist/other" \
    "a prefix-sharing sibling:$root/dist/plugin-old/x"; do
    run_pre_tool Edit file_path "${pair#*:}"
    assert_eq "$rc" "0" "pre-tool allows ${pair%%:*} exit code"
    assert_eq "$out" "" "pre-tool allows ${pair%%:*} prints nothing on stdout"
    assert_eq "$err" "" "pre-tool allows ${pair%%:*} prints nothing on stderr"
done

# new/ does not exist under the copy, so the physical comparison has to resolve
# the nearest existing ancestor (dist/plugin) and re-append the rest.
echo "=== pre-tool denies a copy path through a symlinked repo ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$consumer" "$sandbox/link"
label="pre-tool denies a copy path through a symlinked repo"
assert_absent "$consumer/dist/plugin/new" "$label: new/ is not in the copy"
run_pre_tool Edit file_path "$sandbox/link/dist/plugin/new/file.md"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "$label: additionalContext names the physical source path" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
    --arg p "$root/new/file.md"

# The payload spells no /dist/plugin/ at all: only resolving the path's own
# nearest existing ancestor finds the copy. Splitting the text at /dist/plugin/
# and resolving the part before it passes the test above and allows this one.
echo "=== pre-tool denies a copy path through a symlink to the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$consumer/dist/plugin" "$sandbox/copy-link"
run_pre_tool Edit file_path "$sandbox/copy-link/new/file.md"
label="pre-tool denies a copy path through a symlink to the copy"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "$label: additionalContext names the physical source path" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
    --arg p "$root/new/file.md"

# nope/ and new/ do not exist, so the kernel cannot resolve the .. after them;
# the edit lands where the .. leads. Keeping the missing tail as spelled leaves
# the .. in the compared path: it allows the first path, into the copy, and
# denies the second, a source path spelled through the copy.
echo "=== pre-tool follows .. past a directory not yet created ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="pre-tool follows .. into the copy"
assert_absent "$consumer/skills/nope" "$label: nope/ is not in the source"
run_pre_tool Edit file_path "$root/skills/nope/../../dist/plugin/skills/demo/SKILL.md"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "$label: additionalContext names the physical source path" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
    --arg p "$root/skills/demo/SKILL.md"
label="pre-tool follows .. out of the copy"
assert_absent "$consumer/dist/plugin/new" "$label: new/ is not in the copy"
run_pre_tool Edit file_path "$root/dist/plugin/new/../../../skills/demo/SKILL.md"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

# A $(...) capture strips a name's trailing newline: a dirname taken through one
# turns lnk<newline>, a link to the copy, into lnk, a directory outside it. The
# source path keeps the leaf's own trailing newline, pinned by the full stop
# the message puts after it. The link named - pins that a relative cd onto it
# does not read as cd -.
echo "=== pre-tool keeps a trailing newline and a bare - in a name ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
nl=$'\n'
mkdir "$sandbox/lnk"
ln -s "$consumer/dist/plugin" "$sandbox/lnk$nl"
label="pre-tool keeps a trailing newline"
run_pre_tool Edit file_path "$sandbox/lnk$nl/new/file.md$nl"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "$label: additionalContext names the source path, newline kept" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p + ".")' \
    --arg p "$root/new/file.md$nl"
ln -s "$consumer/dist/plugin" "$sandbox/-"
label="pre-tool follows a link named -"
run_pre_tool Edit file_path "$sandbox/-/new/file.md"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: permissionDecision" '.hookSpecificOutput.permissionDecision == "deny"'
# shellcheck disable=SC2016  # $p is a jq variable bound by --arg
jq_holds "$label: additionalContext names the physical source path" \
    '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
    --arg p "$root/new/file.md"

echo "=== pre-tool invoked through the symlink denies a physical path ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$consumer" "$sandbox/link"
consumer="$sandbox/link"
run_pre_tool Edit file_path "$root/dist/plugin/skills/demo/SKILL.md"
assert_denied "pre-tool invoked through the symlink denies a physical path" "$root"

# The payload is built with the real jq before the PATH narrows: run_pre_tool
# would call jq under it. The same payload is denied with jq on PATH first, so
# the silence below is the missing jq and not the allow of a path outside the
# copy.
echo "=== pre-tool is silent without jq ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
make_jqless_bin "$sandbox/nojq"
label="pre-tool is silent without jq"
if PATH="$sandbox/nojq" command -v jq >/dev/null; then
    fail "$label: jq is still reachable on the jq-less PATH"
fi
payload="$(jq -cn --arg p "$root/dist/plugin/skills/demo/SKILL.md" \
    '{tool_name:"Edit",tool_input:{file_path:$p}}')"
run_dogfood pre-tool <<<"$payload"
assert_denied "$label: control with jq on PATH" "$root"
PATH="$sandbox/nojq" run_dogfood pre-tool <<<"$payload"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

# The silence above is a jq-presence guard, not jq's stderr thrown away: with
# jq present, a payload it cannot read still fails the hook with jq's own error.
echo "=== pre-tool fails loudly on a payload jq cannot read ==="
make_consumer
label="pre-tool fails loudly on a payload jq cannot read"
run_dogfood pre-tool <<<"not json"
if [[ "$rc" == 0 ]]; then
    fail "$label: exit code was 0"
fi
assert_eq "$out" "" "$label prints nothing on stdout"
assert_contains "$err" "jq: " "$label shows jq's error"

# Claude Code realpaths the leaf, so a symlink at the leaf into the copy is an
# edit of the copy. In the chain, y.md reaches it through x.md: a one-hop
# readlink stops at x.md. Both chain links are relative, so a hop resolved
# against the cwd rather than the link's own directory misses the copy.
echo "=== pre-tool follows a symlink at the leaf into the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$root/dist/plugin/skills/demo/SKILL.md" "$root/skills/x.md"
run_pre_tool Edit file_path "$root/skills/x.md"
assert_denied_source "pre-tool follows a symlink at the leaf into the copy" "$root"

echo "=== pre-tool follows a chain of leaf symlinks into the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s ../dist/plugin/skills/demo/SKILL.md "$root/skills/x.md"
ln -s x.md "$root/skills/y.md"
run_pre_tool Edit file_path "$root/skills/y.md"
assert_denied_source "pre-tool follows a chain of leaf symlinks into the copy" "$root"

echo "=== pre-tool allows a leaf symlink out of the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$root/skills/demo/SKILL.md" "$root/dist/plugin/skills/z.md"
run_pre_tool Edit file_path "$root/dist/plugin/skills/z.md"
label="pre-tool allows a leaf symlink out of the copy"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

# run_session_start: run_dogfood session-start, fed a SessionStart payload whose
# cwd is not the consumer, as a resumed session's can be. A script taking its
# root from the payload, even as a fallback, would name the wrong copy.
run_session_start() {
    run_dogfood session-start <<<"$(jq -cn --arg cwd "$sandbox/elsewhere" \
        '{session_id:"fixture",hook_event_name:"SessionStart",source:"resume",cwd:$cwd}')"
}

# assert_session_warns <label> <root>: the last run_session_start printed one
# object, the warning on both channels, each naming <root>/dist/plugin.
assert_session_warns() {
    local label="$1" copy="$2/dist/plugin"
    assert_eq "$rc" "0" "$label exit code"
    assert_eq "$err" "" "$label prints nothing on stderr"
    jq_holds "$label: stdout is one JSON object" 'length == 1 and (.[0] | type) == "object"' -s
    # shellcheck disable=SC2016  # $p is a jq variable bound by --arg
    jq_holds "$label: systemMessage leads with an ANSI reset and names the copy" \
        '.systemMessage | type == "string" and startswith("\u001b[0m") and contains($p)' \
        --arg p "$copy"
    jq_holds "$label: hookEventName" '.hookSpecificOutput.hookEventName == "SessionStart"'
    # shellcheck disable=SC2016  # $p is a jq variable bound by --arg
    jq_holds "$label: additionalContext names the copy" \
        '.hookSpecificOutput.additionalContext | type == "string" and contains($p)' \
        --arg p "$copy"
}

# CLAUDE_CODE_PLUGIN_DIRS is unset by the preamble; a test wanting it passes it
# as a prefix. The warn test below is this one's positive: the same fixture,
# differing only in the variable.
echo "=== session-start is silent on the copy ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start is silent on the copy"
CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

echo "=== session-start warns when the variable is unset ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start warns when the variable is unset"
run_session_start
assert_session_warns "$label" "$root"

# Each spelling below names the copy, so each is silent; the variable, and for
# the last a link to the root, is all that differs from the warn test above.
# The copy sits between two entries, so neither the first nor the last entry
# alone, nor a suffix of the whole value, can stand in for splitting on ':'.
# The link spelling is set while the script is invoked at the physical path, so
# only an entry resolved to its physical spelling matches the root.
echo "=== session-start matches the copy among several entries ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start is silent on one entry of several"
CLAUDE_CODE_PLUGIN_DIRS="/x/other:$root/dist/plugin:/y/other" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

echo "=== session-start matches the copy with a trailing slash ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start is silent on a trailing slash"
CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin/" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

echo "=== session-start matches the copy through a symlink ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
ln -s "$root" "$sandbox/link"
label="session-start is silent on a symlinked spelling"
CLAUDE_CODE_PLUGIN_DIRS="$sandbox/link/dist/plugin" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

# The link resolves to a sibling of the copy whose name is the copy's plus a
# newline, so a resolution read through a $(...) capture loses the newline and
# names the copy.
echo "=== session-start keeps a resolved entry's trailing newline ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
mkdir "$root/dist/plugin"$'\n'
ln -s "$root/dist/plugin"$'\n' "$sandbox/nl"
label="session-start warns on an entry resolving to plugin<LF>"
CLAUDE_CODE_PLUGIN_DIRS="$sandbox/nl" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: stdout is the warning" '.hookSpecificOutput.hookEventName == "SessionStart"'

# Claude Code drops a relative entry, so it loads nothing; run_dogfood runs from
# $sandbox, where this spelling would resolve to the copy.
echo "=== session-start does not resolve a relative entry ==="
make_consumer
run_dogfood sync
label="session-start warns on a relative entry"
CLAUDE_CODE_PLUGIN_DIRS="my consumer/dist/plugin" run_session_start
assert_eq "$rc" "0" "$label exit code"
assert_eq "$err" "" "$label prints nothing on stderr"
jq_holds "$label: stdout is the warning" '.hookSpecificOutput.hookEventName == "SessionStart"'

# A directory that cannot be entered does not resolve; its neighbour still
# names the copy. Running as root, the mode blocks nothing and this cannot red.
echo "=== session-start passes over a directory it cannot enter ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
mkdir "$sandbox/sealed"
chmod 000 "$sandbox/sealed"
label="session-start is silent past a sealed directory"
CLAUDE_CODE_PLUGIN_DIRS="$sandbox/sealed:$root/dist/plugin" run_session_start
chmod 755 "$sandbox/sealed"
assert_eq "$rc" "0" "$label exit code"
assert_eq "$out" "" "$label prints nothing on stdout"
assert_eq "$err" "" "$label prints nothing on stderr"

# Each entry below names something other than the copy, so each warns. The
# other repo's copy is real and synced, so an entry that merely is an existing
# plugin directory, or ends in /dist/plugin, does not match; the /x entry does
# not exist, so it is compared literally and a substring does not match; the
# skills entry is a real directory inside the copy, so a prefix does not match.
echo "=== session-start warns on another repo's real copy ==="
make_consumer
run_dogfood sync
other_root="$(cd "$consumer" && pwd -P)"
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
[[ -d "$other_root/dist/plugin" ]] || fail "fixture: the other repo's copy does not exist"
label="session-start warns on another repo's copy"
CLAUDE_CODE_PLUGIN_DIRS="$other_root/dist/plugin" run_session_start
assert_session_warns "$label" "$root"

echo "=== session-start warns on a longer, non-existent entry ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
label="session-start warns on /x<root>/dist/plugin"
CLAUDE_CODE_PLUGIN_DIRS="/x$root/dist/plugin" run_session_start
assert_session_warns "$label" "$root"

echo "=== session-start warns on a longer, real entry ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
[[ -d "$root/dist/plugin/skills" ]] || fail "fixture: the copy has no skills directory"
label="session-start warns on <root>/dist/plugin/skills"
CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin/skills" run_session_start
assert_session_warns "$label" "$root"

# The payload is built with the real jq before the PATH narrows, and stdout is
# read with the suite's own jq after the run. The message is static, and only a
# user can install jq, so it stays off hookSpecificOutput. The copy check needs
# jq's absence to be skipped, not merely survived: the second run names the copy
# in the variable, where the check would be silent, and still gets the message.
# Their jq-present controls are `session-start is silent on the copy` and
# `session-start warns when the variable is unset` above: the same fixture and
# payload, differing only in the PATH. The sandbox path is random and may hold
# "jq", so it is cut out of the message before the message is searched for jq.
echo "=== session-start reports a missing jq on systemMessage only ==="
make_consumer
run_dogfood sync
root="$(cd "$consumer" && pwd -P)"
make_jqless_bin "$sandbox/nojq"
label="session-start reports a missing jq on systemMessage only"
if PATH="$sandbox/nojq" command -v jq >/dev/null; then
    fail "$label: jq is still reachable on the jq-less PATH"
fi
payload="$(jq -cn --arg cwd "$sandbox/elsewhere" \
    '{session_id:"fixture",hook_event_name:"SessionStart",source:"resume",cwd:$cwd}')"
for spelling in unset names-the-copy; do
    if [[ "$spelling" == unset ]]; then
        PATH="$sandbox/nojq" run_dogfood session-start <<<"$payload"
    else
        CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin" PATH="$sandbox/nojq" \
            run_dogfood session-start <<<"$payload"
    fi
    assert_eq "$rc" "0" "$label ($spelling) exit code"
    assert_eq "$err" "" "$label ($spelling) prints nothing on stderr"
    jq_holds "$label ($spelling): stdout is one JSON object" 'length == 1 and (.[0] | type) == "object"' -s
    jq_holds "$label ($spelling): systemMessage opens with an ANSI reset" \
        '(.systemMessage | type) == "string" and (.systemMessage | startswith("\u001b[0m"))'
    # shellcheck disable=SC2016  # $s is a jq variable bound by --arg
    jq_holds "$label ($spelling): systemMessage names jq" \
        '(.systemMessage | type) == "string" and (.systemMessage | split($s) | join("") | contains("jq"))' \
        --arg s "$sandbox"
    jq_holds "$label ($spelling): hookSpecificOutput is absent" 'has("hookSpecificOutput") | not'
done

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

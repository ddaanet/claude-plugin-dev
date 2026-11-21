#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: the root TASK.md and TODO.md the release commit takes, in the index
# states the plain cases in release-tree-test.sh leave out -- a staged change
# whose worktree was put back, a `git rm`, a `git rm --cached` of an ignored
# file, an unmerged file -- and a failure while staging them, which rolls the
# bump back as a refused commit does. The commit records each as it is on disk.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -tree-submodule, -first,
# -lost-tag, -push-route, -tags, -rollback, -pipefail, -hint-size), and
# release-branch-test.sh, release-branch-resume-test.sh,
# release-branch-moved-test.sh, release-branch-moved-dev-test.sh,
# release-worktree-test.sh, release-dist-optin-test.sh,
# release-dist-publish-test.sh, release-dist-refusal-test.sh,
# release-dist-resume-test.sh, release-core-root-skip-test.sh.
#
# Usage: bash tests/release-handoff-test.sh   (run from repo root)
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
    # A here-string, never a pipe: under pipefail grep -q exits on its first
    # match, the writer can take SIGPIPE, and the pipeline reports failure.
    if ! grep -q -- "$2" <<<"$1"; then
        fail "$3: output did not contain '$2'"
        printf '  --- output ---\n%s\n  --------------\n' "$1" >&2
    fi
}

assert_not_contains() {
    # $1=haystack $2=needle $3=label
    # Residual bound: the needle is a grep BRE matched line by line --
    # a metacharacter in it is live, and a needle that spans a newline
    # can never match.
    # A here-string, never a pipe: under pipefail grep -q exits on its first
    # match, the writer can take SIGPIPE, and the pipeline reports failure.
    if grep -q -- "$2" <<<"$1"; then
        fail "$3: output contained '$2'"
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

# out/rc from the last run_in call.
out=""
rc=0
run_in() {
    # $1=dir, rest=command. Captures stdout+stderr in $out, status in $rc.
    local dir="$1"
    shift
    set +e
    out="$(cd "$dir" && "$@" 2>&1)"
    rc=$?
    set -e
}

git_init() {
    # $1=path. A repo with a deterministic identity and a bare origin.
    git init -q -b main "$1"
    git -C "$1" config user.email test@example.com
    git -C "$1" config user.name "Toolkit Test"
    git -C "$1" config commit.gpgsign false
    git init -q --bare -b main "$1-origin.git"
    git -C "$1" remote add origin "$1-origin.git"
}

new_sandbox() {
    # $1=marketplace entry version, or "" for no entry (first publication).
    # Sets $sandbox, $plugin, $marketplace; exports MARKETPLACE_DIR, PATH, GH_*.
    local entry_version="$1"
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/release-handoff.XXXXXX")"
    sandboxes+=("$sandbox")
    plugin="$sandbox/plugin"
    marketplace="$sandbox/marketplace"

    # gh stub: records every call, and "remembers" created releases as marker
    # files so `release view` can answer truthfully on a second run.
    mkdir -p "$sandbox/bin" "$sandbox/releases"
    cat > "$sandbox/bin/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_LOG"
case "$1 $2" in
    "release view")   [ -f "$GH_RELEASES/$3" ] || exit 1 ;;
    "release create") : > "$GH_RELEASES/$3" ;;
    *) printf 'gh stub: unhandled: %s\n' "$*" >&2; exit 127 ;;
esac
STUB
    chmod +x "$sandbox/bin/gh"
    export GH_LOG="$sandbox/gh.log"
    export GH_RELEASES="$sandbox/releases"
    : > "$GH_LOG"
    export PATH="$sandbox/bin:$PATH"

    # Fixture plugin, vendoring the toolkit the way a consumer does.
    git_init "$plugin"
    mkdir -p "$plugin/.claude-plugin" "$plugin/plugin-dev"
    cat > "$plugin/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.2.3",
  "description": "test fixture",
  "license": "MIT"
}
JSON
    cp "$repo_root"/toolkit/*.sh "$plugin/plugin-dev/"
    git -C "$plugin" add -A
    git -C "$plugin" commit -qm "init"
    git -C "$plugin" tag -a v1.2.3 -m "Release 1.2.3"
    git -C "$plugin" push -q -u origin main
    git -C "$plugin" push -q origin v1.2.3
    git -C "$plugin" remote set-head origin main

    # Fixture marketplace.
    git_init "$marketplace"
    mkdir -p "$marketplace/.claude-plugin"
    if [ -n "$entry_version" ]; then
        jq -n --arg v "$entry_version" \
            '{plugins: [{name: "fixture", source: {source: "github", repo: "o/fixture"}, version: $v}]}' \
            > "$marketplace/.claude-plugin/marketplace.json"
    else
        jq -n '{plugins: []}' > "$marketplace/.claude-plugin/marketplace.json"
    fi
    git -C "$marketplace" add -A
    git -C "$marketplace" commit -qm "init"
    git -C "$marketplace" push -q -u origin main
    export MARKETPLACE_DIR="$marketplace"
}

commit_handoff() {
    # Commits the root TASK.md and TODO.md at known content and pushes, the
    # state a session leaves its frame in between releases.
    printf 'task\n' > "$plugin/TASK.md"
    printf 'todo\n' > "$plugin/TODO.md"
    git -C "$plugin" add TASK.md TODO.md
    git -C "$plugin" commit -qm "handoff files"
    git -C "$plugin" push -q origin main
}

release_paths() {
    # The paths the release commit changed, with their status, sorted.
    git -C "$plugin" diff-tree --no-commit-id --name-status -r HEAD | sort
}

echo "=== release: a staged TODO.md edit whose worktree was put back is not committed ==="
new_sandbox "1.2.3"
commit_handoff
printf 'staged only\n' > "$plugin/TODO.md"
git -C "$plugin" add TODO.md
printf 'todo\n' > "$plugin/TODO.md"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "staged-reverted TODO.md exit code ($out)"
assert_eq "$(git -C "$plugin" show HEAD:TODO.md)" "todo" "the release commit takes TODO.md as it is on disk"
assert_eq "$(release_paths)" "$(printf 'M\t.claude-plugin/plugin.json')" \
    "the release commit carries the manifest alone"
assert_eq "$(git -C "$plugin" status --porcelain -- TODO.md)" "" "TODO.md matches the release commit"

echo "=== release: a TASK.md staged as new and then deleted from disk is not committed ==="
new_sandbox "1.2.3"
printf 'staged new\n' > "$plugin/TASK.md"
git -C "$plugin" add TASK.md
rm "$plugin/TASK.md"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "staged-new deleted TASK.md exit code ($out)"
assert_eq "$(release_paths)" "$(printf 'M\t.claude-plugin/plugin.json')" \
    "the release commit leaves out a TASK.md not on disk"
assert_eq "$(git -C "$plugin" status --porcelain)" "" "staged-new deleted TASK.md leaves the tree clean"

echo "=== release: a TASK.md removed with git rm is committed as deleted ==="
new_sandbox "1.2.3"
commit_handoff
git -C "$plugin" rm -q TASK.md
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "git-rm TASK.md exit code ($out)"
assert_eq "$(release_paths)" "$(printf 'D\tTASK.md\nM\t.claude-plugin/plugin.json')" \
    "the release commit deletes TASK.md"
assert_eq "$(git -C "$plugin" status --porcelain)" "" "git-rm TASK.md leaves the tree clean"

echo "=== release: a tracked TASK.md removed from the index and ignored keeps its disk content ==="
new_sandbox "1.2.3"
commit_handoff
git -C "$plugin" rm -q --cached TASK.md
printf 'TASK.md\n' >> "$plugin/.git/info/exclude"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "rm-cached ignored TASK.md exit code ($out)"
assert_eq "$(git -C "$plugin" show HEAD:TASK.md 2>&1)" "task" "the release commit keeps TASK.md as it is on disk"
assert_eq "$(release_paths)" "$(printf 'M\t.claude-plugin/plugin.json')" \
    "the release commit carries the manifest alone"

echo "=== release: an unmerged TASK.md refuses, naming it ==="
new_sandbox "1.2.3"
commit_handoff
git -C "$plugin" checkout -q -b other
printf 'task, other\n' > "$plugin/TASK.md"
git -C "$plugin" commit -qam "other task"
git -C "$plugin" checkout -q main
printf 'task, main\n' > "$plugin/TASK.md"
git -C "$plugin" commit -qam "main task"
git -C "$plugin" push -q origin main
git -C "$plugin" merge -q other >/dev/null 2>&1 || true
unmerged_head="$(git -C "$plugin" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "unmerged TASK.md exit code"
assert_contains "$out" "unmerged handoff file" "unmerged TASK.md message"
assert_contains "$out" "        TASK.md$" "unmerged TASK.md names the path"
assert_eq "$(git -C "$plugin" rev-parse HEAD)" "$unmerged_head" "unmerged TASK.md commits nothing"
assert_eq "$(git -C "$plugin" tag --list 'v1.2.4')" "" "unmerged TASK.md creates no tag"
assert_eq "$(cat "$GH_LOG")" "" "unmerged TASK.md release must not call gh"

echo "=== release: a failure staging the handoff files rolls the bump back ==="
new_sandbox "1.2.3"
commit_handoff
printf 'task, edited\n' > "$plugin/TASK.md"
real_git="$(command -v git)"
# A git that refuses to stage TASK.md, whatever command stages it; every other
# call goes through. Removed after the run: later sandboxes keep this bin/ on
# PATH behind their own.
cat > "$sandbox/bin/git" <<STUB
#!/usr/bin/env bash
case "\$1" in
    add|update-index)
        for a in "\$@"; do
            [ "\$a" != TASK.md ] || { echo "git stub: refusing to stage TASK.md" >&2; exit 1; }
        done ;;
esac
exec "$real_git" "\$@"
STUB
chmod +x "$sandbox/bin/git"
staging_head="$(git -C "$plugin" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
rm "$sandbox/bin/git"
assert_eq "$rc" "1" "staging failure exit code"
assert_contains "$out" "could not stage the handoff files" "staging failure message"
assert_contains "$out" "rolled back to 1.2.3" "staging failure prints the rollback hint"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.3" "staging failure restores the manifest"
assert_eq "$(git -C "$plugin" status --porcelain)" " M TASK.md" "staging failure leaves TASK.md as it is on disk, unstaged"
assert_eq "$(git -C "$plugin" rev-parse HEAD)" "$staging_head" "staging failure commits nothing"
assert_eq "$(git -C "$plugin" tag --list 'v1.2.4')" "" "staging failure creates no tag"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release handoff scenarios passed\n'

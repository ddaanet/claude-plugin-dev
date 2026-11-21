#!/usr/bin/env bash
# End-to-end test of scripts/self-release.sh against real git repos in a temp
# dir. No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: the root TASK.md and TODO.md the release commit takes, in the index
# states a plain edit leaves out -- a staged change whose worktree was put
# back, a `git rm`, a `git rm --cached` of an ignored file, an unmerged file --
# and a failure while staging them, which rolls toolkit/VERSION back as a
# refused commit does. The commit records each as it is on disk. The consumer
# counterpart is tests/release-handoff-test.sh. Siblings:
# self-release-{publish,refusal,branch,amend}-test.sh.
#
# Usage: bash tests/self-release-handoff-test.sh   (run from repo root)
set -euo pipefail

# When run as this repo's own pre-commit hook, the enclosing `git commit` leaks
# GIT_DIR/GIT_INDEX_FILE/etc. into this process's environment. Every git command
# below targets a fixture repo via `-C` or a `cd`, never this repo, so it's
# always safe to drop them here.
# shellcheck disable=SC2046  # word-splitting is the point: a var-name list
unset $(git rev-parse --local-env-vars)

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
script="$repo_root/scripts/self-release.sh"

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
refute_tag() {
    # $1=tag $2=label
    if git -C "$repo" rev-parse -q --verify "refs/tags/$1" >/dev/null; then
        fail "$2: tag $1 should not exist"
    fi
}
assert_gh_untouched() {
    # $1=label. Fails unless $GH_LOG is empty -- pinning that the refusal
    # happened before `gh` was ever reached, not merely that its visible
    # output was absent. $GH_LOG is truncated per new_sandbox, so a scenario
    # sharing one sandbox across several refusals must call this between runs
    # rather than once at the end, or an earlier touch could be attributed to
    # the wrong one.
    local logged
    logged="$(cat "$GH_LOG")"
    [ -z "$logged" ] || fail "$1: gh was touched ($logged)"
}

sandboxes=()
cleanup() {
    local s
    for s in "${sandboxes[@]:-}"; do
        [ -n "$s" ] && rm -rf "$s"
    done
}
trap cleanup EXIT

out=""
rc=0
run() {
    # Runs the script under test in $repo. Captures stdout+stderr in $out.
    set +e
    out="$(cd "$repo" && bash "$script" "$@" 2>&1)"
    rc=$?
    set -e
}

new_sandbox() {
    # A repo shaped like claude-plugin-dev, already released at 0.1.0: both
    # tags pushed and the GitHub release "created", so the prior-release guard
    # is satisfied and a test that wants it unsatisfied breaks it explicitly.
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/self-release-handoff.XXXXXX")"
    sandboxes+=("$sandbox")
    repo="$sandbox/repo"

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

    git init -q -b main "$repo"
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name "Toolkit Test"
    git -C "$repo" config commit.gpgsign false
    git init -q --bare -b main "$repo-origin.git"
    git -C "$repo" remote add origin "$repo-origin.git"

    mkdir -p "$repo/toolkit"
    printf '0.1.0\n' > "$repo/toolkit/VERSION"
    printf '# shipped manual\n' > "$repo/toolkit/README.md"
    printf 'this file is the dev environment, not the dist tree\n' > "$repo/ROOT-ONLY.md"
    git -C "$repo" add -A
    git -C "$repo" commit -qm "init"
    git -C "$repo" tag -a v0.1.0 -m "Release 0.1.0"
    local dist_sha
    dist_sha=$(git -C "$repo" subtree split -q --prefix=toolkit v0.1.0)
    git -C "$repo" tag -a dist-v0.1.0 -m "Dist 0.1.0" "$dist_sha"
    git -C "$repo" push -q -u origin main
    git -C "$repo" push -q origin v0.1.0 dist-v0.1.0
    : > "$GH_RELEASES/v0.1.0"
}

commit_handoff() {
    # Commits the root TASK.md and TODO.md at known content and pushes, the
    # state a session leaves its frame in between releases.
    printf 'task\n' > "$repo/TASK.md"
    printf 'todo\n' > "$repo/TODO.md"
    git -C "$repo" add TASK.md TODO.md
    git -C "$repo" commit -qm "handoff files"
    git -C "$repo" push -q origin main
}

release_paths() {
    # The paths the release commit changed, with their status, sorted.
    git -C "$repo" diff-tree --no-commit-id --name-status -r HEAD | sort
}

echo "=== a staged TODO.md edit whose worktree was put back is not committed ==="
new_sandbox
commit_handoff
printf 'staged only\n' > "$repo/TODO.md"
git -C "$repo" add TODO.md
printf 'todo\n' > "$repo/TODO.md"
run patch
assert_eq "$rc" 0 "staged-reverted TODO.md: exit status ($out)"
assert_eq "$(git -C "$repo" show HEAD:TODO.md)" "todo" "staged-reverted TODO.md: committed as on disk"
assert_eq "$(release_paths)" "$(printf 'M\ttoolkit/VERSION')" "staged-reverted TODO.md: VERSION alone"
assert_eq "$(git -C "$repo" status --porcelain -- TODO.md)" "" "staged-reverted TODO.md: matches the commit"

echo "=== a TASK.md staged as new and then deleted from disk is not committed ==="
new_sandbox
printf 'staged new\n' > "$repo/TASK.md"
git -C "$repo" add TASK.md
rm "$repo/TASK.md"
run patch
assert_eq "$rc" 0 "staged-new deleted TASK.md: exit status ($out)"
assert_eq "$(release_paths)" "$(printf 'M\ttoolkit/VERSION')" "staged-new deleted TASK.md: left out"
assert_eq "$(git -C "$repo" status --porcelain)" "" "staged-new deleted TASK.md: tree clean"

echo "=== a TASK.md removed with git rm is committed as deleted ==="
new_sandbox
commit_handoff
git -C "$repo" rm -q TASK.md
run patch
assert_eq "$rc" 0 "git-rm TASK.md: exit status ($out)"
assert_eq "$(release_paths)" "$(printf 'D\tTASK.md\nM\ttoolkit/VERSION')" "git-rm TASK.md: deleted"
assert_eq "$(git -C "$repo" status --porcelain)" "" "git-rm TASK.md: tree clean"

echo "=== a tracked TASK.md removed from the index and ignored keeps its disk content ==="
new_sandbox
commit_handoff
git -C "$repo" rm -q --cached TASK.md
printf 'TASK.md\n' >> "$repo/.git/info/exclude"
run patch
assert_eq "$rc" 0 "rm-cached ignored TASK.md: exit status ($out)"
assert_eq "$(git -C "$repo" show HEAD:TASK.md 2>&1)" "task" "rm-cached ignored TASK.md: kept as on disk"
assert_eq "$(release_paths)" "$(printf 'M\ttoolkit/VERSION')" "rm-cached ignored TASK.md: VERSION alone"

echo "=== an unmerged TASK.md refuses, naming it ==="
new_sandbox
commit_handoff
git -C "$repo" checkout -q -b other
printf 'task, other\n' > "$repo/TASK.md"
git -C "$repo" commit -qam "other task"
git -C "$repo" checkout -q main
printf 'task, main\n' > "$repo/TASK.md"
git -C "$repo" commit -qam "main task"
git -C "$repo" push -q origin main
git -C "$repo" merge -q other >/dev/null 2>&1 || true
unmerged_head="$(git -C "$repo" rev-parse HEAD)"
run patch
assert_eq "$rc" 1 "unmerged TASK.md: exit status"
assert_contains "$out" "unmerged handoff file" "unmerged TASK.md: message"
assert_contains "$out" "        TASK.md$" "unmerged TASK.md: names the path"
assert_eq "$(git -C "$repo" rev-parse HEAD)" "$unmerged_head" "unmerged TASK.md: nothing committed"
refute_tag v0.1.1 "unmerged TASK.md"
assert_gh_untouched "unmerged TASK.md"

echo "=== a failure staging the handoff files rolls the bump back ==="
new_sandbox
commit_handoff
printf 'task, edited\n' > "$repo/TASK.md"
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
staging_head="$(git -C "$repo" rev-parse HEAD)"
run patch
rm "$sandbox/bin/git"
assert_eq "$rc" 1 "staging failure: exit status"
assert_contains "$out" "could not stage the handoff files" "staging failure: message"
assert_contains "$out" "toolkit/VERSION was rolled back" "staging failure: rollback hint"
assert_eq "$(cat "$repo/toolkit/VERSION")" "0.1.0" "staging failure: VERSION restored"
assert_eq "$(git -C "$repo" status --porcelain)" " M TASK.md" "staging failure: TASK.md as on disk, unstaged"
assert_eq "$(git -C "$repo" rev-parse HEAD)" "$staging_head" "staging failure: nothing committed"
refute_tag v0.1.1 "staging failure"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall self-release handoff scenarios passed\n'

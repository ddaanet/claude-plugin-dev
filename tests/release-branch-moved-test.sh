#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir, for an
# origin whose main another writer moved after the release was cut and before
# its push. No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: the release is refused with nothing public, and its hint is two
# commands: merge origin's main, then resume. The test runs the merge verbatim
# and the resume as its recipe body, then checks that the tag still names the
# commit it was cut on and that origin's main is the merge, its first parent
# the release side and its second the other writer's commit. Three states: from
# main; from dev with HEAD at the release commit; the other writer edited the
# TODO.md the release commit took, so the merge conflicts and is resolved by
# hand; the other writer also pushed the release's tag at its own commit, so
# the release is refused with no merge hint and origin's main and tag untouched.
# The later-commits and first-release-from-dev states are in
# release-branch-moved-dev-test.sh.
#
# The other writer moves origin from inside the run: a reference-transaction
# hook in the fixture fires when the release's tag is created, which is after
# the ancestry fetch and before the push, and pushes from a second clone.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -tree-submodule, -first,
# -lost-tag, -push-route, -tags, -rollback, -pipefail, -hint-size, -handoff),
# and release-branch-test.sh, release-branch-resume-test.sh,
# release-branch-moved-dev-test.sh, release-worktree-test.sh,
# release-dist-optin-test.sh, release-dist-publish-test.sh,
# release-dist-refusal-test.sh, release-dist-resume-test.sh,
# release-core-root-skip-test.sh.
#
# Usage: bash tests/release-branch-moved-test.sh   (run from repo root)
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
    # $1=haystack $2=needle $3=label (same residual bound as assert_contains)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/release-branch.XXXXXX")"
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

rev() {
    # $1=a revision in the plugin repo. Prints its sha, empty when it does not
    # resolve. Never fails: a missing ref is a value for an assertion to judge,
    # not a reason for `set -e` to end the suite.
    git -C "$plugin" rev-parse -q --verify "$1" || true
}
origin_rev() {
    # $1=a revision in the bare origin, read from the bare repo itself and never
    # through the clone's remote-tracking refs. Prints its sha, empty if absent.
    git -C "$plugin-origin.git" rev-parse -q --verify "$1" || true
}
branch_now() {
    git -C "$plugin" symbolic-ref -q --short HEAD || true
}

to_dev() {
    # Branches `dev` off main with one commit, never pushed: the state a release
    # from dev starts in.
    git -C "$plugin" checkout -q -b dev
    printf 'work on dev\n' > "$plugin/dev-work.md"
    git -C "$plugin" add -A
    git -C "$plugin" commit -qm "work: dev-work.md"
}

writer_clone() {
    # A second clone of origin acting as another writer. Sets $other.
    other="$sandbox/other"
    git clone -q "$plugin-origin.git" "$other"
    git -C "$other" config user.email test@example.com
    git -C "$other" config user.name "Toolkit Test"
    git -C "$other" config commit.gpgsign false
}

install_mover() {
    # $1=tag, $2=the file the other writer writes (default origin-only.md),
    # $3=its content, $4=non-empty to have the other writer also tag its commit
    # $1 and push that tag. Makes the other writer push to origin's main at the
    # moment the run creates tag $1. Fires once; the ref-transaction stdin is
    # drained.
    local file="${2:-origin-only.md}" content="${3:-only on origin}" push_tag="${4:-}"
    cat > "$sandbox/move-origin.sh" <<SH
#!/bin/sh
unset \$(git rev-parse --local-env-vars)
cd "$other" || exit 1
printf '%s\\n' '$content' > '$file'
git add '$file'
git commit -qm "work: $file"
git push -q origin main
git rev-parse HEAD > "$sandbox/other-sha"
if [ -n '$push_tag' ]; then
    git tag -a '$1' -m 'Release elsewhere'
    git push -q origin '$1'
fi
SH
    cat > "$plugin/.git/hooks/reference-transaction" <<HOOK
#!/bin/sh
[ "\$1" = committed ] || exit 0
while read -r old new ref; do
    if [ "\$ref" = "refs/tags/$1" ] && [ ! -e "$sandbox/moved" ]; then
        : > "$sandbox/moved"
        sh "$sandbox/move-origin.sh" >/dev/null 2>&1 || :
    fi
done
HOOK
    chmod +x "$plugin/.git/hooks/reference-transaction"
}

install_prepush() {
    # A pre-push hook that records it ran: a release origin moved past must be
    # refused before any push is attempted.
    cat > "$plugin/.git/hooks/pre-push" <<HOOK
#!/bin/sh
: > "$sandbox/pre-push-ran"
exit 0
HOOK
    chmod +x "$plugin/.git/hooks/pre-push"
}

moved_sha() {
    # Sets $other_sha from the mover's record, empty when it never fired.
    other_sha="$(cat "$sandbox/other-sha" 2>/dev/null || true)"
}

extract_hint() {
    # Sets $hint_cmds to the commands the refusal prints, one per line: from the
    # hint line naming origin's main to the `error:` line, those starting with
    # `git ` or `just ` once indentation is stripped. Empty when none printed.
    local line s started=0
    hint_cmds=""
    while IFS= read -r line; do
        s="${line#"${line%%[![:space:]]*}"}"
        case "$s" in "hint: origin's main has commits"*) started=1 ;; "error:"*) started=0 ;; esac
        [ "$started" = 1 ] || continue
        case "$s" in
            "git "*|"just "*) hint_cmds+="$s"$'\n' ;;
        esac
    done <<<"$out"
}

check_refused() {
    # $1=label $2=tag. The release failed with nothing public: origin's main is
    # still the other writer's head, no tag on origin, no GitHub release. The
    # hint is the merge and the resume, and origin/main is fresh enough for the
    # merge to take the other writer's commit. Sets $rel_sha to the tag's commit.
    assert_eq "$rc" "1" "$1: exit status"
    [ ! -e "$plugin/.git/hooks/reference-transaction" ] || [ -e "$sandbox/moved" ] || fail "$1: the other writer never moved origin"
    assert_eq "$(origin_rev refs/heads/main)" "$other_sha" "$1: origin main still the other writer's"
    assert_eq "$(origin_rev "refs/tags/$2")" "" "$1: no tag on origin"
    assert_not_contains "$(cat "$GH_LOG")" "release create" "$1: no GitHub release"
    assert_eq "$(origin_rev refs/heads/dev)" "" "$1: dev not on origin"
    [ ! -e "$sandbox/pre-push-ran" ] || fail "$1: a push was attempted (pre-push hook ran)"
    if ! grep -qiE 'nothing.*public' <<<"$out"; then
        fail "$1: the refusal does not say nothing is public"
        printf '  --- output ---\n%s\n  --------------\n' "$out" >&2
    fi
    extract_hint
    assert_eq "$hint_cmds" $'git merge origin/main\njust resume-release\n' "$1: the hint is the merge, then the resume"
    assert_eq "$(rev refs/remotes/origin/main)" "$other_sha" "$1: origin/main refetched for the merge"
    rel_sha="$(rev "refs/tags/$2^{commit}")"
    [ -n "$rel_sha" ] || fail "$1: the refusal left no local tag $2"
}

run_hint() {
    # $1=label, rest=the hint lines to run. Runs each in the plugin repo: a
    # `git` line verbatim, `just resume-release` as its recipe body
    # (release.just runs release.sh --resume). Reads $rc/$out of the last.
    local label="$1" cmd
    shift
    for cmd in "$@"; do
        case "$cmd" in
            "just resume-release") run_in "$plugin" bash plugin-dev/release.sh --resume ;;
            "git "*) run_in "$plugin" bash -ec "$cmd" ;;
            *) fail "$label: unexpected hint line: $cmd"; return 1 ;;
        esac
        if [ "$rc" != 0 ]; then
            fail "$label: hint line failed (status $rc): $cmd"
            printf '  --- output ---\n%s\n  --------------\n' "$out" >&2
            return 1
        fi
    done
}

check_resumed() {
    # $1=label $2=tag $3=branch the checkout started on $4=the merge's expected
    # first parent (default the tag's commit). The tag still names $rel_sha, the
    # commit it was cut on; origin's main is the merge made on the checked-out
    # branch, its first parent the release side and its second the other
    # writer's commit, and local main sits there too.
    local merged
    merged="$(origin_rev refs/heads/main)"
    assert_eq "$(rev "refs/tags/$2^{commit}")" "$rel_sha" "$1: the tag still names the commit it was cut on"
    assert_eq "$(origin_rev "refs/tags/$2^{commit}")" "$rel_sha" "$1: tag on origin at that commit"
    assert_eq "$merged" "$(rev HEAD)" "$1: origin main is the merged HEAD"
    assert_eq "$(rev refs/heads/main)" "$merged" "$1: local main at origin's main"
    assert_eq "$(rev "$merged^1")" "${4:-$rel_sha}" "$1: the merge's first parent is the release side"
    assert_eq "$(rev "$merged^2")" "$other_sha" "$1: the merge's second parent is the other writer's commit"
    assert_contains "$(cat "$GH_LOG")" "release create $2" "$1: GitHub release created"
    assert_eq "$(branch_now)" "$3" "$1: checkout branch unchanged"
    assert_eq "$(origin_rev refs/heads/dev)" "" "$1: dev not on origin"
}

echo "=== origin moved before the push, release from main ==="
new_sandbox "1.2.3"
writer_clone
install_prepush
install_mover v1.2.4
run_in "$plugin" bash plugin-dev/release.sh patch
moved_sha
check_refused "moved, from main" v1.2.4
if run_hint "moved, from main" "git merge origin/main" "just resume-release"; then
    check_resumed "moved, from main" v1.2.4 main
fi

echo "=== origin moved before the push, release from dev with HEAD at the release commit ==="
new_sandbox "1.2.3"
to_dev
writer_clone
install_prepush
install_mover v1.2.4
run_in "$plugin" bash plugin-dev/release.sh patch
moved_sha
check_refused "moved, from dev" v1.2.4
if run_hint "moved, from dev" "git merge origin/main" "just resume-release"; then
    check_resumed "moved, from dev" v1.2.4 dev
fi

echo "=== origin moved before the push, the other writer edited TODO.md too ==="
# The release commit takes the handoff files as they are on disk, and the other
# writer's commit edits TODO.md as well, so the merge the hint names conflicts
# on it and is resolved as any merge conflict is.
new_sandbox "1.2.3"
printf 'todo\n' > "$plugin/TODO.md"
git -C "$plugin" add TODO.md
git -C "$plugin" commit -qm "todo"
git -C "$plugin" push -q origin main
writer_clone
printf 'todo, release done\n' > "$plugin/TODO.md"
printf 'task frame\n' > "$plugin/TASK.md"
install_prepush
install_mover v1.2.4 TODO.md "todo, theirs"
run_in "$plugin" bash plugin-dev/release.sh patch
moved_sha
check_refused "moved, TODO.md conflict" v1.2.4
run_in "$plugin" bash -ec "git merge origin/main"
assert_eq "$rc" "1" "moved, TODO.md conflict: the merge stops on the conflict"
assert_eq "$(git -C "$plugin" diff --name-only --diff-filter=U)" "TODO.md" "moved, TODO.md conflict: TODO.md is the conflict"
printf 'todo, release done\ntodo, theirs\n' > "$plugin/TODO.md"
git -C "$plugin" add TODO.md
git -C "$plugin" commit -q --no-edit
if run_hint "moved, TODO.md conflict" "just resume-release"; then
    check_resumed "moved, TODO.md conflict" v1.2.4 main
    assert_eq "$(git -C "$plugin" show v1.2.4:TODO.md)" "todo, release done" "moved, TODO.md conflict: the tag keeps the TODO.md it took"
    assert_eq "$(git -C "$plugin" show v1.2.4:TASK.md)" "task frame" "moved, TODO.md conflict: the tag keeps the TASK.md it took"
    assert_eq "$(git -C "$plugin-origin.git" show main:TODO.md)" "$(printf 'todo, release done\ntodo, theirs')" \
        "moved, TODO.md conflict: origin main carries the resolution"
fi

echo "=== origin moved before the push, and already holds the tag at another commit ==="
# Another clone released the same version first: its main and its v1.2.4 are on
# origin. Its release is not this one to merge, so the refusal names the tag
# and prints no merge hint.
new_sandbox "1.2.3"
writer_clone
install_mover v1.2.4 origin-only.md "only on origin" yes
run_in "$plugin" bash plugin-dev/release.sh patch
moved_sha
elsewhere_tag="$(origin_rev refs/tags/v1.2.4)"
[ -n "$elsewhere_tag" ] || fail "tag elsewhere: the other writer never pushed v1.2.4"
assert_eq "$rc" "1" "tag elsewhere: the release is refused"
assert_contains "$out" "v1.2.4 on origin points at $elsewhere_tag, not $(rev refs/tags/v1.2.4)" "tag elsewhere: the refusal names the tag and both shas"
assert_contains "$out" "nothing was pushed" "tag elsewhere: the refusal says nothing was pushed"
assert_not_contains "$out" "git merge origin/main" "tag elsewhere: no merge hint"
assert_eq "$(origin_rev refs/heads/main)" "$other_sha" "tag elsewhere: origin main still the other writer's"
assert_eq "$(origin_rev refs/tags/v1.2.4)" "$elsewhere_tag" "tag elsewhere: origin's tag unchanged"
assert_not_contains "$(cat "$GH_LOG")" "release create" "tag elsewhere: no GitHub release"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release branch moved scenarios passed\n'

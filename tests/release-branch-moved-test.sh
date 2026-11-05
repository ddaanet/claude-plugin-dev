#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir, for an
# origin whose main another writer moved after the release was cut and before
# its push. No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: the release is refused with nothing public and prints the undo; the
# test then runs the printed commands VERBATIM, parsed out of the output, never
# a hand-written equivalent, and releases again with the same bump. The new
# tag's commit must carry the other writer's commit and be origin's main. Three
# states: from main; from dev with HEAD at the release commit; a first release
# from main after a hand commit changed the manifest's version, which is not a
# bump to drop. The later-commits and first-release-from-dev states are in
# release-branch-moved-dev-test.sh.
#
# The other writer moves origin from inside the run: a reference-transaction
# hook in the fixture fires when the release's tag is created, which is after
# the ancestry fetch and before the push, and pushes from a second clone.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size), and
# release-branch-test.sh, release-branch-resume-test.sh and
# release-branch-moved-dev-test.sh for the other halves of the same contract.
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

market_version() {
    jq -r '.plugins[] | select(.name=="fixture") | .version' \
        "$marketplace/.claude-plugin/marketplace.json"
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

after_release() {
    # $1=label. What every successful release from dev leaves: the branch it
    # started on checked out, dev never published.
    assert_eq "$(branch_now)" "dev" "$1: HEAD branch unchanged"
    assert_eq "$(origin_rev refs/heads/dev)" "" "$1: dev not on origin"
}

make_virgin() {
    # $1=manifest version. Strips the fixture's release history so the plugin
    # has never been released: no v* tags locally or on origin, and the manifest
    # seeded at $1. Paired with new_sandbox "" (no marketplace entry).
    git -C "$plugin" tag -d v1.2.3 >/dev/null
    git -C "$plugin" push -q origin :refs/tags/v1.2.3
    jq --arg v "$1" '.version = $v' "$plugin/.claude-plugin/plugin.json" \
        > "$plugin/.claude-plugin/plugin.json.tmp"
    mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
    git -C "$plugin" add -A
    if ! git -C "$plugin" diff --cached --quiet; then
        git -C "$plugin" commit -qm "scaffold at $1"
    fi
    git -C "$plugin" push -q origin main
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
    # $1=tag. Makes the other writer push to origin's main at the moment the
    # run creates tag $1. Fires once; the ref-transaction stdin is drained.
    cat > "$sandbox/move-origin.sh" <<SH
#!/bin/sh
unset \$(git rev-parse --local-env-vars)
cd "$other" || exit 1
printf 'only on origin\n' > origin-only.md
git add origin-only.md
git commit -qm "work: origin-only.md"
git push -q origin main
git rev-parse HEAD > "$sandbox/other-sha"
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

# Format the green phase must print: one command per line, each starting `git `
# or `jq `; the jq step a single line ending `&& mv <tmp> <manifest>`; the commit
# of it on separate `git` lines. A line may carry a `hint:` prefix, indentation,
# list numbering, a `$ ` prompt or wrapping backticks; all are stripped.
extract_undo() {
    # Sets $undo_cmds to the printed undo, one command per line: from the line
    # `git fetch --no-tags origin` to the line `git merge --no-edit origin/...`,
    # keeping those starting with `git ` or `jq ` once a leading `hint:`,
    # indentation and list numbering are stripped. Empty when none was printed.
    local line s started=0
    undo_cmds=""
    while IFS= read -r line; do
        s="${line#hint:}"
        s="${s#"${s%%[![:space:]]*}"}"
        if [[ "$s" =~ ^[0-9]+[.\)][[:space:]]+(.*)$ ]]; then
            s="${BASH_REMATCH[1]}"
        fi
        s="${s#\$ }"
        if [[ "$s" =~ ^\`(.*)\`$ ]]; then
            s="${BASH_REMATCH[1]}"
        fi
        if [ "$started" = 0 ]; then
            case "$s" in "git fetch --no-tags origin"*) started=1 ;; esac
        fi
        [ "$started" = 1 ] || continue
        case "$s" in
            "git "*|"jq "*) undo_cmds+="$s"$'\n' ;;
        esac
        case "$s" in "git merge --no-edit origin/"*) break ;; esac
    done <<<"$out"
}

check_refused() {
    # $1=label $2=tag $3=bump ("" for none). The release failed with nothing public: origin's main is
    # still the other writer's head, no tag on origin, no GitHub release.
    assert_eq "$rc" "1" "$1: exit status"
    [ -e "$sandbox/moved" ] || [ "$mode_resume" = 1 ] || fail "$1: the other writer never moved origin"
    assert_eq "$(origin_rev refs/heads/main)" "$other_sha" "$1: origin main still the other writer's"
    assert_eq "$(origin_rev "refs/tags/$2")" "" "$1: no tag on origin"
    assert_not_contains "$(cat "$GH_LOG")" "release create" "$1: no GitHub release"
    assert_eq "$(origin_rev refs/heads/dev)" "" "$1: dev not on origin"
    [ ! -e "$sandbox/pre-push-ran" ] || fail "$1: a push was attempted (pre-push hook ran)"
    if ! grep -qiE 'nothing.*public' <<<"$out"; then
        fail "$1: the refusal does not say nothing is public"
        printf '  --- output ---\n%s\n  --------------\n' "$out" >&2
    fi
    assert_contains "$out" "just release${3:+ $3}" "$1: names just release with the same bump"
}

run_undo() {
    # $1=label. Extracts the printed undo and runs it verbatim in the plugin
    # repo under errexit. Returns 1, after recording why, when it cannot.
    extract_undo
    if [ -z "$undo_cmds" ]; then
        fail "$1: the refusal printed no undo commands"
        printf '  --- output ---\n%s\n  --------------\n' "$out" >&2
        return 1
    fi
    local printed="$out"
    run_in "$plugin" bash -ec "$undo_cmds"
    if [ "$rc" != 0 ]; then
        fail "$1: the printed undo failed (status $rc): $undo_cmds"
        printf '  --- output ---\n%s\n  ---- printed ----\n%s\n  --------------\n' "$out" "$printed" >&2
        return 1
    fi
}

check_rerun() {
    # $1=label $2=tag $3=branch the checkout started on. After the undo, the
    # same release again lands a tag on a commit that carries the other
    # writer's commit and is origin's main. Reads $rc/$out of that rerun.
    local tag_commit
    assert_eq "$rc" "0" "$1: second release exit status"
    tag_commit="$(rev "refs/tags/$2^{commit}")"
    [ -n "$tag_commit" ] || fail "$1: tag $2 does not resolve to a commit"
    assert_eq "$(origin_rev refs/heads/main)" "$tag_commit" "$1: origin main is the new tag's commit"
    assert_eq "$(origin_rev "refs/tags/$2^{commit}")" "$tag_commit" "$1: tag on origin at that commit"
    if ! git -C "$plugin" merge-base --is-ancestor "$other_sha" "$tag_commit"; then
        fail "$1: the new tag's commit lacks the other writer's commit"
    fi
    assert_contains "$(cat "$GH_LOG")" "release create $2" "$1: GitHub release created"
    assert_eq "$(branch_now)" "$3" "$1: checkout branch unchanged"
    assert_eq "$(origin_rev refs/heads/dev)" "" "$1: dev not on origin"
}

mode_resume=0

echo "=== origin moved before the push, release from main ==="
new_sandbox "1.2.3"
writer_clone
install_prepush
install_mover v1.2.4
run_in "$plugin" bash plugin-dev/release.sh patch
moved_sha
check_refused "moved, from main" v1.2.4 patch
assert_contains "$out" "git tag -d v1.2.4" "moved, from main: printed undo drops the tag"
if run_undo "moved, from main"; then
    assert_contains "$undo_cmds" "git reset --hard HEAD~1" "moved, from main: HEAD is the release commit, so reset"
    assert_not_contains "$undo_cmds" "git branch -f" "moved, from main: main is checked out, nothing to rewind"
    assert_eq "$(rev HEAD)" "$other_sha" "moved, from main: undo leaves HEAD at the other writer's commit"
    run_in "$plugin" bash plugin-dev/release.sh patch
    check_rerun "moved, from main" v1.2.4 main
fi

echo "=== origin moved before the push, release from dev with HEAD at the release commit ==="
new_sandbox "1.2.3"
to_dev
writer_clone
install_prepush
install_mover v1.2.4
run_in "$plugin" bash plugin-dev/release.sh patch
moved_sha
check_refused "moved, from dev" v1.2.4 patch
assert_contains "$out" "git tag -d v1.2.4" "moved, from dev: printed undo drops the tag"
if run_undo "moved, from dev"; then
    assert_contains "$undo_cmds" "git reset --hard HEAD~1" "moved, from dev: HEAD is the release commit, so reset"
    assert_contains "$undo_cmds" "git branch -f main origin/main" "moved, from dev: the run moved main, so rewind it"
    assert_eq "$(rev refs/heads/main)" "$other_sha" "moved, from dev: undo rewinds local main to origin's"
    assert_eq "$(branch_now)" "dev" "moved, from dev: undo leaves dev checked out"
    run_in "$plugin" bash plugin-dev/release.sh patch
    check_rerun "moved, from dev" v1.2.4 dev
fi

echo "=== origin moved before the push, a first release from main after a hand version commit ==="
new_sandbox ""
make_virgin "0.0.9"
writer_clone
jq '.version = "0.1.0"' "$plugin/.claude-plugin/plugin.json" > "$plugin/m.tmp"
mv "$plugin/m.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" add .claude-plugin/plugin.json
git -C "$plugin" commit -qm "version 0.1.0"
hand_version="$(rev HEAD)"
install_prepush
install_mover v0.1.0
run_in "$plugin" bash plugin-dev/release.sh
moved_sha
check_refused "moved, first release after hand bump" v0.1.0 ""
assert_not_contains "$out" "just release patch" "moved, first release after hand bump: rerun names no bump (patch)"
assert_not_contains "$out" "just release minor" "moved, first release after hand bump: rerun names no bump (minor)"
assert_not_contains "$out" "just release major" "moved, first release after hand bump: rerun names no bump (major)"
if run_undo "moved, first release after hand bump"; then
    assert_contains "$undo_cmds" "git tag -d v0.1.0" "moved, first release after hand bump: undo drops the tag"
    assert_not_contains "$undo_cmds" "reset --hard" "moved, first release after hand bump: the hand commit is not a release commit to reset"
    assert_not_contains "$undo_cmds" "jq " "moved, first release after hand bump: no bump to drop"
    git -C "$plugin" merge-base --is-ancestor "$hand_version" HEAD \
        || fail "moved, first release after hand bump: the hand version commit is no longer an ancestor of HEAD"
    assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "0.1.0" "moved, first release after hand bump: manifest still 0.1.0"
    run_in "$plugin" bash plugin-dev/release.sh
    check_rerun "moved, first release after hand bump" v0.1.0 main
fi

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release branch moved scenarios passed\n'

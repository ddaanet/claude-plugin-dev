#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Scope: what counts as a clean tree -- a resting memory submodule is exempt; a
# staged handoff frame under .claude, like any other dirty path, refuses -- in
# the plugin root and the marketplace repo; and the root TASK.md and TODO.md,
# exempt in the plugin root, where the release commit takes them, and not in
# the marketplace repo.
# Siblings: the other tests/release-*-test.sh suites, one per scenario group
# (release-core, -resume-push, -resume-hint, -tree-submodule, -first, -lost-tag,
# -push-route, -tags, -rollback, -pipefail, -hint-size, -handoff), and
# release-branch-test.sh, release-branch-resume-test.sh,
# release-branch-moved-test.sh, release-branch-moved-dev-test.sh,
# release-worktree-test.sh, release-dist-optin-test.sh,
# release-dist-publish-test.sh, release-dist-refusal-test.sh,
# release-dist-resume-test.sh, release-core-root-skip-test.sh.
#
# Usage: bash tests/release-tree-test.sh   (run from repo root)
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
    sandbox="$(mktemp -d "${TMPDIR:-/tmp}/release-tree.XXXXXX")"
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

mount_resting_submodule() {
    # $1=parent repo path. $2=mount path, default `memory`. $3=submodule name,
    # default `gitlore-memory` — the name gitlore's install.sh fixes, and what
    # common_preflight keys its exclusion on. Mounts the submodule and commits
    # the mount, then advances the submodule's checked-out HEAD by one commit
    # without folding the moved gitlink into a parent commit — gitlore's
    # ordinary resting state between commits (see release.sh's tree_is_clean).
    local parent="$1" path="${2:-memory}" name="${3:-gitlore-memory}"
    local sub_origin sub_seed
    sub_origin="$parent-$name-origin.git"
    sub_seed=$(mktemp -d "${TMPDIR:-/tmp}/release-tree.XXXXXX")
    git init -q --bare -b main "$sub_origin"
    git init -q -b main "$sub_seed"
    git -C "$sub_seed" config user.email test@example.com
    git -C "$sub_seed" config user.name "Toolkit Test"
    git -C "$sub_seed" config commit.gpgsign false
    printf 'seed\n' > "$sub_seed/MEMORY.md"
    git -C "$sub_seed" add -A
    git -C "$sub_seed" commit -qm seed
    git -C "$sub_seed" remote add origin "$sub_origin"
    git -C "$sub_seed" push -q -u origin main
    rm -rf "$sub_seed"

    env GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always \
        git -C "$parent" submodule add -q --name "$name" "$sub_origin" "$path"
    git -C "$parent" commit -qm "mount $name submodule"

    printf 'advance\n' >> "$parent/$path/MEMORY.md"
    git -C "$parent/$path" add -A
    git -C "$parent/$path" -c user.email=test@example.com -c user.name="Toolkit Test" \
        -c commit.gpgsign=false commit -qm advance
    # Deliberately no parent commit here.
}

stage_handoff_frame() {
    # $1=repo root. Reproduces what the handoff and precompact skills leave
    # behind: a task frame under .claude, committed once and then rewritten and
    # staged for "whatever commit lands next". Staged, not merely written,
    # because `git diff HEAD` sees only tracked paths — an untracked frame never
    # reached the check in the first place.
    local dir="$1"
    mkdir -p "$dir/.claude"
    printf 'frame v1\n' > "$dir/.claude/handoff-task.md"
    git -C "$dir" add .claude/handoff-task.md
    git -C "$dir" commit -qm "handoff frame"
    printf 'frame v2\n' > "$dir/.claude/handoff-task.md"
    git -C "$dir" add .claude/handoff-task.md
}

echo "=== release: proceeds with a resting memory submodule in the plugin root ==="
new_sandbox "1.2.3"
mount_resting_submodule "$plugin"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "resting-memory release exit code"
assert_contains "$out" "Release v1.2.4 complete" "resting-memory release summary"
assert_eq "$(market_version)" "1.2.4" "resting-memory release bumped the marketplace"

echo "=== release: still refuses a genuinely dirty non-memory path in the plugin root ==="
new_sandbox "1.2.3"
mount_resting_submodule "$plugin"
jq '.description = "dirty"' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "dirty-plugin-root release exit code"
assert_contains "$out" "uncommitted changes" "dirty-plugin-root release message"
# A bare "uncommitted changes" is what made the operator suspect the checker
# rather than the tree. The message names the path it refused on, and the
# exemption it did apply — here the memory store's, since one is mounted. There
# is no .claude/ exemption to name, nor a note ruling out a near-miss reading.
assert_contains "$out" ".claude-plugin/plugin.json" "dirty-plugin-root names the offending path"
assert_contains "$out" "memory/ — the gitlore memory submodule" "dirty-plugin-root names the memory exemption"
assert_not_contains "$out" ".claude/ — agent working state" "dirty-plugin-root names no .claude exemption"
assert_not_contains "$out" ".claude-plugin/ is NOT exempt" "dirty-plugin-root carries no near-miss note"
assert_eq "$(cat "$GH_LOG")" "" "dirty-plugin-root release must not call gh"

# A word-split read of `git diff --name-only` reports one spaced path as two,
# and both halves are then wrong: neither names a file the operator can act on.
echo "=== release: the dirty-path report keeps a spaced path in one piece ==="
new_sandbox "1.2.3"
printf 'v1\n' > "$plugin/a tracked file.txt"
git -C "$plugin" add -A
git -C "$plugin" commit -qm "add a spaced path"
printf 'v2\n' >> "$plugin/a tracked file.txt"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "spaced-path exit code"
# The leading indent is the assertion: the whole path sits on one reported line.
assert_contains "$out" "        a tracked file.txt$" "spaced path reported whole"
# No memory store is mounted here, so the handoff files are the only exemption
# the list names.
assert_contains "$out" "        TASK.md — " "spaced path: the handoff exemption is listed"
assert_not_contains "$out" "gitlore memory submodule" "spaced path: no memory exemption without a store"

echo "=== release: proceeds with a resting memory submodule in the marketplace repo ==="
new_sandbox "1.2.3"
mount_resting_submodule "$marketplace"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "resting-memory marketplace release exit code"
assert_contains "$out" "Release v1.2.4 complete" "resting-memory marketplace release summary"
assert_eq "$(market_version)" "1.2.4" "resting-memory marketplace release bumped the marketplace"

echo "=== release: still refuses a genuinely dirty non-memory path in the marketplace repo ==="
new_sandbox "1.2.3"
mount_resting_submodule "$marketplace"
jq '.plugins[0].description = "dirty"' "$marketplace/.claude-plugin/marketplace.json" > "$marketplace/.claude-plugin/marketplace.json.tmp"
mv "$marketplace/.claude-plugin/marketplace.json.tmp" "$marketplace/.claude-plugin/marketplace.json"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "dirty-marketplace release exit code"
assert_contains "$out" "$MARKETPLACE_DIR has uncommitted changes" "dirty-marketplace release message"
# This one can also fire on a release that is already public through its GitHub
# release, with the bump staged and its commit refused — so it must name both
# the path and the command that finishes such a release.
assert_contains "$out" ".claude-plugin/marketplace.json" "dirty-marketplace names the offending path"
assert_contains "$out" "just resume-release" "dirty-marketplace names the recovery command"
assert_eq "$(cat "$GH_LOG")" "" "dirty-marketplace release must not call gh"

# A space in the mount path is the case a word-split read of .gitmodules would
# pass on every other input: `git config --get` returns the value whole.
echo "=== release: proceeds with the memory submodule at a non-default mount path ==="
new_sandbox "1.2.3"
mount_resting_submodule "$plugin" "store dir"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "non-default-mount release exit code"
assert_contains "$out" "Release v1.2.4 complete" "non-default-mount release summary"
assert_eq "$(market_version)" "1.2.4" "non-default-mount release bumped the marketplace"

echo "=== release: proceeds with the marketplace memory submodule at a non-default mount path ==="
new_sandbox "1.2.3"
mount_resting_submodule "$marketplace" store
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "non-default-mount marketplace exit code"
assert_contains "$out" "Release v1.2.4 complete" "non-default-mount marketplace summary"

echo "=== release: refuses a staged handoff frame under .claude in the plugin root ==="
new_sandbox "1.2.3"
stage_handoff_frame "$plugin"
frame_head="$(git -C "$plugin" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "staged-frame release exit code"
assert_contains "$out" "uncommitted changes" "staged-frame release message"
assert_contains "$out" ".claude/handoff-task.md" "staged-frame release names the offending path"
# No memory store is mounted, so the list of exemptions applied names the
# handoff files alone; the message claims no exemption it did not apply.
assert_contains "$out" "        TODO.md — " "staged-frame lists the handoff exemption"
assert_not_contains "$out" "gitlore memory submodule" "staged-frame claims no memory exemption"
assert_not_contains "$out" ".claude/ — agent working state" "staged-frame names no .claude exemption"
assert_eq "$(git -C "$plugin" rev-parse HEAD)" "$frame_head" "staged-frame refusal commits nothing"
assert_eq "$(git -C "$plugin" tag --list 'v1.2.4')" "" "staged-frame refusal creates no tag"
assert_eq "$(market_version)" "1.2.3" "staged-frame refusal leaves the marketplace alone"
assert_eq "$(cat "$GH_LOG")" "" "staged-frame release must not call gh"

echo "=== release: refuses a staged handoff frame under .claude in the marketplace repo ==="
new_sandbox "1.2.3"
stage_handoff_frame "$marketplace"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "staged-frame marketplace exit code"
assert_contains "$out" "$MARKETPLACE_DIR has uncommitted changes" "staged-frame marketplace message"
assert_contains "$out" ".claude/handoff-task.md" "staged-frame marketplace names the offending path"
assert_not_contains "$out" "exempt from this check" "staged-frame marketplace prints no exemption header"
assert_eq "$(market_version)" "1.2.3" "staged-frame marketplace refusal leaves the marketplace alone"
assert_eq "$(cat "$GH_LOG")" "" "staged-frame marketplace release must not call gh"

echo "=== release: refuses a staged change whose worktree was put back to HEAD ==="
new_sandbox "1.2.3"
printf 'staged\n' > "$plugin/notes file.md"
git -C "$plugin" add "notes file.md"
git -C "$plugin" commit -qm notes
printf 'staged edit\n' > "$plugin/notes file.md"
git -C "$plugin" add "notes file.md"
printf 'staged\n' > "$plugin/notes file.md"
git -C "$plugin" push -q origin main
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "staged-reverted file exit code"
assert_contains "$out" "uncommitted changes" "staged-reverted file message"
assert_contains "$out" "        notes file.md$" "staged-reverted file names the spaced path whole"
assert_eq "$(cat "$GH_LOG")" "" "staged-reverted file release must not call gh"

echo "=== release: the release commit takes a modified TODO.md and a deleted TASK.md ==="
new_sandbox "1.2.3"
printf 'task\n' > "$plugin/TASK.md"
printf 'todo\n' > "$plugin/TODO.md"
git -C "$plugin" add TASK.md TODO.md
git -C "$plugin" commit -qm "handoff files"
git -C "$plugin" push -q origin main
printf 'todo, release done\n' > "$plugin/TODO.md"
rm "$plugin/TASK.md"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "handoff-files release exit code ($out)"
assert_contains "$out" "Release v1.2.4 complete" "handoff-files release summary"
assert_eq "$(git -C "$plugin" diff-tree --no-commit-id --name-status -r HEAD | sort)" \
    "$(printf 'D\tTASK.md\nM\t.claude-plugin/plugin.json\nM\tTODO.md')" \
    "the release commit carries the manifest and both handoff files"
assert_eq "$(git -C "$plugin" status --porcelain)" "" "handoff-files release leaves the tree clean"

echo "=== release: an untracked TASK.md rides the release commit; an ignored TODO.md does not ==="
new_sandbox "1.2.3"
printf 'task\n' > "$plugin/TASK.md"
printf 'TODO.md\n' >> "$plugin/.git/info/exclude"
printf 'todo\n' > "$plugin/TODO.md"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "untracked-frame release exit code ($out)"
assert_eq "$(git -C "$plugin" diff-tree --no-commit-id --name-status -r HEAD | sort)" \
    "$(printf 'A\tTASK.md\nM\t.claude-plugin/plugin.json')" \
    "the release commit adds the untracked TASK.md and leaves the ignored TODO.md"

echo "=== release: a refused release commit leaves an unstaged TODO.md unstaged ==="
new_sandbox "1.2.3"
printf 'todo\n' > "$plugin/TODO.md"
git -C "$plugin" add TODO.md
git -C "$plugin" commit -qm "todo"
git -C "$plugin" push -q origin main
printf 'todo, edited\n' > "$plugin/TODO.md"
printf '#!/bin/sh\nexit 1\n' > "$plugin/.git/hooks/pre-commit"
chmod +x "$plugin/.git/hooks/pre-commit"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "refused handoff release exit code"
assert_eq "$(git -C "$plugin" status --porcelain)" " M TODO.md" \
    "a refused release commit leaves TODO.md as the run found it"

echo "=== release: a dirty TODO.md in the marketplace repo still refuses ==="
new_sandbox "1.2.3"
printf 'todo\n' > "$marketplace/TODO.md"
git -C "$marketplace" add TODO.md
git -C "$marketplace" commit -qm "todo"
printf 'todo, edited\n' > "$marketplace/TODO.md"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "dirty marketplace TODO.md exit code"
assert_contains "$out" "$MARKETPLACE_DIR has uncommitted changes" "dirty marketplace TODO.md message"
assert_contains "$out" "        TODO.md$" "dirty marketplace TODO.md names the path"
assert_not_contains "$out" "exempt from this check" "the marketplace repo has no handoff exemption"
assert_eq "$(cat "$GH_LOG")" "" "dirty marketplace TODO.md release must not call gh"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release tree scenarios passed\n'

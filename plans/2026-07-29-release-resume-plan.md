# release.sh + `resume-release` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the consumer release flow out of `release.just`'s recipe body into
`plugin-dev/release.sh`, and add a `--resume` mode that completes a release which
landed only partially — exposed to consumers as `just resume-release`.

**Architecture:** One script, two entry paths through three blocks: a common
pre-flight, a mode-specific pre-flight (compute-and-bump for `release`,
locate-the-tag for `--resume`), and a shared idempotent tail (push branch, push
tag, GitHub release, marketplace bump) that probes remote state before acting.
`release.just` shrinks to two one-line wrappers.

**Tech Stack:** bash, jq, git, gh, just. Tests are plain bash driving real git
repos in a temp dir with a `gh` stub on `PATH`.

**Spec:** `plans/2026-07-29-release-resume-design.md`. Read it first.

## Global Constraints

- **bash 3.2 compatible.** No associative arrays, no `mapfile`, no `${x^^}`,
  no `&>>`. The toolkit runs on macOS's system bash in consumer plugins.
- **Portable `sed`.** BSD and GNU differ on `-i` and on `\+`/`\?`. Use `-E`, and
  never `sed -i` inside shipped scripts (`jq` to a `mktemp` then `mv` is the
  established pattern).
- **Never `local x=$(cmd)`.** The assignment masks the command's exit status
  under `set -e` (SC2155). Declare on one line, assign on the next.
- **`set -euo pipefail`** at the top of every script, matching `check-version.sh`.
- **shellcheck clean.** `just precommit` runs `shellcheck` over the `.sh` files;
  `release.sh` and `tests/release-test.sh` join that list in Task 1.
- **Vendored path prefix is `plugin-dev/`** — `release.just` addresses siblings as
  `{{toolkit_prefix}}/…`, scripts address them via `BASH_SOURCE`.
- **No network in tests.** All git remotes are local bare repos; `gh` is stubbed.
- **Commit message style:** gitmoji prefix, e.g. `✨ add release.sh with a resumable tail`.
- **Quality gate:** `just precommit` must be green before every commit (it runs as
  this repo's pre-commit hook).

---

## File Structure

**Create:**

- `release.sh` — the whole consumer release flow, both modes. Vendored into
  consumers at `plugin-dev/release.sh`.
- `tests/release-test.sh` — offline end-to-end harness: fixture plugin repo, bare
  origin, fixture marketplace repo with its own bare origin, `gh` stub.
- `docs/changelog/<release-date>-resume-release.md` — write-time record.

**Modify:**

- `release.just:38-139` — the `release` recipe body becomes one line; a
  `resume-release` recipe is added.
- `justfile:7-12` — `precommit` gains `release.sh` in the shellcheck list and runs
  `tests/release-test.sh`.
- `justfile:86-127` — `_import-check` gains an assertion that `resume-release`
  resolves in a stub consumer.
- `check-version.sh` — no code change; `release.sh` adds the `resume-release` hint
  around its failure.
- `docs/design.md` — new section, revisited Limitations.
- `docs/changelog.md` — pointer line for the new entry.

**Delete:**

- `brief-half-landed-release-recovery.md` — superseded by the spec.

---

### Task 1: `release.sh` reproduces today's release flow, under test

The move first, the feature second: after this task `release.sh` does exactly
what the recipe body did, with a test harness proving it. `--resume` arrives in
Task 2.

**Files:**
- Create: `release.sh`
- Create: `tests/release-test.sh`
- Modify: `justfile:7-12` (precommit)

**Interfaces:**
- Consumes: `check-version.sh` (sibling, invoked as `bash "$here/check-version.sh"`).
- Produces: `release.sh` accepting `patch|minor|major` as `$1`; shell functions
  `common_preflight`, `release_preflight`, `bump_commit_tag`, `push_branch`,
  `push_tag`, `create_github_release`, `bump_marketplace`, and the globals they
  set: `manifest`, `branch`, `plugin_name`, `marketplace_json`,
  `marketplace_entry_exists`, `V`, `tag`, `acted`. Task 2 adds `resume_preflight`
  and the `mode` dispatch; Task 3 reads `acted`.

- [ ] **Step 1: Write the harness and the happy-path scenario**

Create `tests/release-test.sh`:

```bash
#!/usr/bin/env bash
# End-to-end test of release.sh against real git repos in a temp dir.
# No network: origins are local bare repos and `gh` is a stub on PATH.
#
# Usage: bash tests/release-test.sh   (run from repo root)
set -euo pipefail

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
    if ! printf '%s' "$1" | grep -q -- "$2"; then
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
    sandbox="$(mktemp -d)"
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
    cp "$repo_root/release.sh" "$repo_root/check-version.sh" "$plugin/plugin-dev/"
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

echo "=== release: happy path ==="
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "happy-path exit code"
assert_contains "$out" "Release v1.2.4 complete" "happy-path summary"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.4" "manifest version"
assert_eq "$(git -C "$plugin" rev-parse --verify -q refs/tags/v1.2.4 >/dev/null && echo yes || echo no)" \
    "yes" "local tag created"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.2.4 | wc -l | tr -d ' ')" \
    "1" "tag pushed to origin"
assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "gh release created"
assert_eq "$(market_version)" "1.2.4" "marketplace bumped"
assert_eq "$(git -C "$marketplace" log -1 --format=%s)" "release: fixture 1.2.4" "marketplace commit"

if (( failures > 0 )); then
    printf '\n%d failure(s)\n' "$failures" >&2
    exit 1
fi
printf '\nall release scenarios passed\n'
```

- [ ] **Step 2: Run it to confirm it fails for the right reason**

```sh
bash tests/release-test.sh
```

Expected: FAIL — `cp: .../release.sh: No such file or directory`. The harness is
correct; the script does not exist yet.

- [ ] **Step 3: Write `release.sh`**

Create `release.sh`. Every block below is a straight port of
`release.just:38-139`; only the structure is new.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Release a Claude Code plugin: bump the manifest, commit, tag, push, create the
# GitHub release, and bump the plugin's entry in the marketplace repo.
#
# Usage: release.sh [patch|minor|major]
#
# Run from the plugin root (the directory holding .claude-plugin/plugin.json);
# `just release` does that for you. Requires bash, jq, git, gh, and
# MARKETPLACE_DIR pointing at the claude-plugins repo.

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

manifest=".claude-plugin/plugin.json"
bump="${1:-patch}"
acted=0

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
note() { printf '%s\n' "$*"; }

common_preflight() {
    [ -f "$manifest" ] || die "$manifest not found — run from the plugin root"
    git diff --quiet HEAD || die "uncommitted changes"
    branch=$(git symbolic-ref -q --short HEAD || echo "")
    # Use symbolic-ref (not rev-parse): when origin/HEAD is unset, rev-parse
    # exits non-zero AND prints "origin/HEAD" to stdout, so the substitution
    # captures both the failed output and the fallback.
    main_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo "main")
    [ "$branch" = "$main_branch" ] || die "must be on $main_branch (currently $branch)"

    [ -n "${MARKETPLACE_DIR:-}" ] \
        || die "MARKETPLACE_DIR not set (set in .envrc to the claude-plugins repo root)"
    marketplace_json="$MARKETPLACE_DIR/.claude-plugin/marketplace.json"
    [ -f "$marketplace_json" ] || die "$marketplace_json not found"
    plugin_name=$(jq -r .name "$manifest")
    # A missing entry is not an error: on first publication we create one from
    # plugin.json. Synthesising its `source` needs an `origin` remote to derive
    # owner/repo from, so validate that here, before any destructive op.
    if jq -e --arg n "$plugin_name" 'any(.plugins[]; .name == $n)' "$marketplace_json" >/dev/null; then
        marketplace_entry_exists=1
    else
        marketplace_entry_exists=0
        git remote get-url origin >/dev/null 2>&1 \
            || die "'$plugin_name' has no entry in $marketplace_json and no 'origin' remote to derive one from"
    fi
    git -C "$MARKETPLACE_DIR" diff --quiet HEAD \
        || die "$MARKETPLACE_DIR has uncommitted changes"
}

release_preflight() {
    local manifest_version latest_tag
    # Catch a previous release that didn't fully complete (tag/manifest bumped,
    # marketplace bump never landed) before starting a new one on top of it.
    bash "$here/check-version.sh" || {
        printf 'hint: `just resume-release` completes a release that landed partially.\n' >&2
        die "fix the version drift above before releasing"
    }
    manifest_version=$(jq -r .version "$manifest")
    latest_tag=$(git describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || true)
    if [ -n "$latest_tag" ] && [ "$manifest_version" != "$latest_tag" ]; then
        printf 'hint: plugin.json holds the LAST released version. `just release` bumps from there.\n' >&2
        printf '      revert any manual version bump and re-run.\n' >&2
        die "plugin.json version ($manifest_version) does not match latest tag (v$latest_tag)"
    fi
    V=$(jq -r --arg bump "$bump" '
      (.version | split(".") | map(tonumber)) as [$maj,$min,$pat]
      | if   $bump == "major" then [$maj+1, 0, 0]
        elif $bump == "minor" then [$maj, $min+1, 0]
        elif $bump == "patch" then [$maj, $min, $pat+1]
        else error("unknown bump type: " + $bump) end
      | map(tostring) | join(".")
    ' "$manifest")
    tag="v$V"
    ! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || die "tag $tag already exists"
}

bump_commit_tag() {
    local tmp
    tmp=$(mktemp)
    jq --arg v "$V" '.version = $v' "$manifest" > "$tmp"
    mv "$tmp" "$manifest"
    git add "$manifest"
    git commit -m "release: $V"
    git tag -a "$tag" -m "Release $V"
    acted=1
    note "manifest + tag: $tag created locally"
}

push_branch() {
    local remote_head
    remote_head=$(git ls-remote origin "refs/heads/$branch" | cut -f1)
    if [ -n "$remote_head" ] && [ "$remote_head" = "$(git rev-parse HEAD)" ]; then
        note "branch $branch: already pushed"
        return
    fi
    git push
    acted=1
    note "branch $branch: pushed"
}

push_tag() {
    local remote_tag local_tag
    remote_tag=$(git ls-remote origin "refs/tags/$tag" | cut -f1)
    local_tag=$(git rev-parse "$tag")
    if [ -n "$remote_tag" ]; then
        # Never move a published tag: a mismatch means it was reused, which no
        # recovery should paper over.
        [ "$remote_tag" = "$local_tag" ] \
            || die "$tag on origin points at $remote_tag, not $local_tag — refusing to move a published tag"
        note "github tag $tag: already pushed"
        return
    fi
    git push origin "$tag"
    acted=1
    note "github tag $tag: pushed"
}

create_github_release() {
    if gh release view "$tag" >/dev/null 2>&1; then
        note "github release $tag: already created"
        return
    fi
    gh release create "$tag" --title "Release $V" --generate-notes
    acted=1
    note "github release $tag: created"
}

bump_marketplace() {
    local mp_tmp repo_slug
    mp_tmp=$(mktemp)
    if [ "$marketplace_entry_exists" = 1 ]; then
        jq --arg n "$plugin_name" --arg v "$V" \
            '(.plugins[] | select(.name == $n) | .version) = $v' \
            "$marketplace_json" > "$mp_tmp"
    else
        # Derive owner/repo from origin for the `github` source. Strip a trailing
        # .git, then everything up to the host separator, leaving `owner/repo`
        # for both git@host:owner/repo and https://host/owner/repo.
        repo_slug=$(git remote get-url origin | sed -E 's#\.git$##; s#^.*[:/]([^/]+/[^/]+)$#\1#')
        jq --arg v "$V" --arg repo "$repo_slug" --slurpfile m "$manifest" '
          .plugins += [{
            name: $m[0].name,
            source: { source: "github", repo: $repo },
            description: ($m[0].description // ""),
            version: $v,
            author: ($m[0].author // { name: "" }),
            repository: ($m[0].repository // $m[0].homepage // ("https://github.com/" + $repo)),
            license: ($m[0].license // "MIT")
          }]
        ' "$marketplace_json" > "$mp_tmp"
    fi
    mv "$mp_tmp" "$marketplace_json"
    git -C "$MARKETPLACE_DIR" add .claude-plugin/marketplace.json
    # Idempotent: when the entry was already at $V the rewrite is a no-op, and
    # `git commit` would exit 1 under `set -e` after the irreversible steps.
    if git -C "$MARKETPLACE_DIR" diff --cached --quiet; then
        note "marketplace: already at $V"
        return
    fi
    git -C "$MARKETPLACE_DIR" commit -m "release: $plugin_name $V"
    git -C "$MARKETPLACE_DIR" push
    acted=1
    if [ "$marketplace_entry_exists" = 1 ]; then
        note "marketplace: bumped to $V"
    else
        note "marketplace: entry created at $V"
    fi
}

common_preflight
release_preflight
bump_commit_tag
push_branch
push_tag
create_github_release
bump_marketplace
note "Release $tag complete"
```

- [ ] **Step 4: Run the test and make it pass**

```sh
chmod +x release.sh
bash tests/release-test.sh
```

Expected: `all release scenarios passed`.

- [ ] **Step 5: Wire both files into `precommit`**

In `justfile`, extend the `precommit` recipe (currently lines 7-12):

```just
# Run all syntax + style checks on the toolkit's own scripts.
precommit: whitespace
    shellcheck install.sh version-guard.sh check-version.sh release.sh
    bash -n tests/hook-test.sh tests/release-test.sh
    just _import-check
    bash tests/hook-test.sh
    bash tests/release-test.sh
    @echo ok
```

- [ ] **Step 6: Run the gate**

```sh
just precommit
```

Expected: `ok`. Fix any shellcheck findings the move surfaces — most likely
SC2155 (`local x=$(cmd)`) if a declaration was collapsed, and SC2086 on unquoted
expansions.

- [ ] **Step 7: Commit**

```bash
git add release.sh tests/release-test.sh justfile
git commit -m "✨ move the consumer release flow into release.sh"
```

---

### Task 2: `--resume` completes a half-landed release

**Files:**
- Modify: `release.sh` (mode dispatch, `resume_preflight`)
- Modify: `tests/release-test.sh` (scenario 2)

**Interfaces:**
- Consumes: everything Task 1 produced.
- Produces: `mode` (`release` | `resume`), `resume_preflight`. Task 3 relies on
  `--resume` reaching the tail without bumping anything.

- [ ] **Step 1: Write the failing test**

Append to `tests/release-test.sh`, before the `failures` summary block:

```bash
echo "=== resume: completes a release whose push was rejected ==="
new_sandbox "1.2.3"
# A pre-push hook that refuses, reproducing the gitlore 0.4.3 failure: the
# recipe dies after the irreversible commit and tag, before the tag push.
cat > "$plugin/.git/hooks/pre-push" <<'HOOK'
#!/bin/sh
echo "pre-push: refusing" >&2
exit 1
HOOK
chmod +x "$plugin/.git/hooks/pre-push"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "interrupted release exit code"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.4" "manifest bumped before the failure"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.2.4 | wc -l | tr -d ' ')" \
    "0" "tag not on origin after the failure"
assert_eq "$(market_version)" "1.2.3" "marketplace still stale after the failure"

rm -f "$plugin/.git/hooks/pre-push"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "resume exit code"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" \
    "$(git -C "$plugin" rev-parse HEAD)" "resume pushed the branch"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.2.4 | wc -l | tr -d ' ')" \
    "1" "resume pushed the tag"
assert_contains "$(cat "$GH_LOG")" "release create v1.2.4" "resume created the GitHub release"
assert_eq "$(market_version)" "1.2.4" "resume bumped the marketplace"
assert_contains "$out" "Release v1.2.4 complete" "resume summary"
```

- [ ] **Step 2: Run it to verify it fails**

```sh
bash tests/release-test.sh
```

Expected: FAIL on `resume exit code` — `release.sh` treats `--resume` as a bump
type, so `release_preflight`'s jq raises `unknown bump type: --resume`.

- [ ] **Step 3: Add the mode dispatch and `resume_preflight`**

In `release.sh`, replace the `bump="${1:-patch}"` line with:

```bash
mode="release"
bump="patch"
case "${1:-}" in
    --resume) mode="resume" ;;
    "")       ;;
    -*)       die "unknown option: $1 (usage: release.sh [patch|minor|major|--resume])" ;;
    *)        bump="$1" ;;
esac
```

Add this function after `release_preflight`:

```bash
resume_preflight() {
    V=$(jq -r .version "$manifest")
    tag="v$V"
    # Resume only ever finishes a release whose commit and tag already landed
    # locally. No tag means no release was started at this version, and tagging
    # HEAD on a guess would tag whatever work landed since.
    git rev-parse -q --verify "refs/tags/$tag" >/dev/null || {
        printf 'hint: no release was started at this version.\n' >&2
        printf '      run `just release <bump>` instead.\n' >&2
        die "no tag $tag for plugin.json version $V"
    }
}
```

Replace the trailing call sequence with:

```bash
common_preflight
if [ "$mode" = "release" ]; then
    release_preflight
    bump_commit_tag
else
    resume_preflight
fi
push_branch
push_tag
create_github_release
bump_marketplace
note "Release $tag complete"
```

Update the usage comment at the top of the file:

```bash
# Usage:
#   release.sh [patch|minor|major]   full release
#   release.sh --resume              complete a release that landed partially
```

- [ ] **Step 4: Run the tests**

```sh
bash tests/release-test.sh
```

Expected: `all release scenarios passed`.

- [ ] **Step 5: Commit**

```bash
git add release.sh tests/release-test.sh
git commit -m "✨ add --resume to complete a half-landed release"
```

---

### Task 3: Resume on a healthy repo says so instead of re-releasing

**Files:**
- Modify: `release.sh` (final summary reads `acted`)
- Modify: `tests/release-test.sh` (scenario 3)

**Interfaces:**
- Consumes: `acted`, set to 1 by every step in the tail that actually acted.
- Produces: no new names.

- [ ] **Step 1: Write the failing test**

Append to `tests/release-test.sh`, before the summary block:

```bash
echo "=== resume: no-op on a healthy repo ==="
new_sandbox "1.2.3"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "setup release exit code"
: > "$GH_LOG"
marketplace_head_before="$(git -C "$marketplace" rev-parse HEAD)"
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "0" "healthy resume exit code"
assert_contains "$out" "already complete (nothing to do)" "healthy resume summary"
assert_contains "$(cat "$GH_LOG")" "release view v1.2.4" "healthy resume probed the release"
if grep -q "release create" "$GH_LOG"; then
    fail "healthy resume re-created the GitHub release"
fi
assert_eq "$(git -C "$marketplace" rev-parse HEAD)" "$marketplace_head_before" \
    "healthy resume left the marketplace untouched"
```

- [ ] **Step 2: Run it to verify it fails**

```sh
bash tests/release-test.sh
```

Expected: FAIL on `healthy resume summary` — the script prints
`Release v1.2.4 complete` unconditionally.

- [ ] **Step 3: Make the summary reflect what happened**

In `release.sh`, replace the final `note "Release $tag complete"` with:

```bash
if [ "$mode" = "resume" ] && [ "$acted" = 0 ]; then
    note "release $tag is already complete (nothing to do)"
else
    note "Release $tag complete"
fi
```

- [ ] **Step 4: Run the tests**

```sh
bash tests/release-test.sh
```

Expected: `all release scenarios passed` — including the Task 1 and 2 scenarios,
which still assert `Release v1.2.4 complete`.

- [ ] **Step 5: Commit**

```bash
git add release.sh tests/release-test.sh
git commit -m "✨ report nothing-to-do when resume finds a complete release"
```

---

### Task 4: Resume refuses when no release was started

**Files:**
- Modify: `tests/release-test.sh` (scenario 4)

**Interfaces:**
- Consumes: `resume_preflight` from Task 2. No source change is expected — this
  task pins the guard with a test. If it fails, the guard is wrong, not the test.

- [ ] **Step 1: Write the test**

Append to `tests/release-test.sh`, before the summary block:

```bash
echo "=== resume: refuses when no tag exists for the manifest version ==="
new_sandbox "1.2.3"
git -C "$plugin" tag -d v1.2.3 >/dev/null
run_in "$plugin" bash plugin-dev/release.sh --resume
assert_eq "$rc" "1" "no-tag resume exit code"
assert_contains "$out" "no tag v1.2.3 for plugin.json version 1.2.3" "no-tag resume message"
assert_contains "$out" "run \`just release <bump>\` instead" "no-tag resume hint"
assert_eq "$(cat "$GH_LOG")" "" "no-tag resume must not call gh"
```

- [ ] **Step 2: Run the tests**

```sh
bash tests/release-test.sh
```

Expected: PASS. If the exit code is 0, `resume_preflight` is missing its
`git rev-parse -q --verify` guard — re-read Task 2 Step 3.

- [ ] **Step 3: Commit**

```bash
git add tests/release-test.sh
git commit -m "✅ pin resume's refusal when no release was started"
```

---

### Task 5: First publication still creates the marketplace entry

The create branch is the one most likely to have been broken by the move, and the
only one no other scenario exercises.

**Files:**
- Modify: `tests/release-test.sh` (scenario 5)

**Interfaces:**
- Consumes: `bump_marketplace`'s `marketplace_entry_exists = 0` branch.

- [ ] **Step 1: Write the test**

Append to `tests/release-test.sh`, before the summary block:

```bash
echo "=== release: first publication creates the marketplace entry ==="
new_sandbox ""   # empty .plugins — pre-first-publication
run_in "$plugin" bash plugin-dev/release.sh minor
assert_eq "$rc" "0" "first-publication exit code"
assert_contains "$out" "marketplace: entry created at 1.3.0" "first-publication summary"
entry="$(jq -c '.plugins[] | select(.name=="fixture")' \
    "$marketplace/.claude-plugin/marketplace.json")"
assert_eq "$(printf '%s' "$entry" | jq -r .version)" "1.3.0" "created entry version"
assert_eq "$(printf '%s' "$entry" | jq -r .source.source)" "github" "created entry source type"
assert_eq "$(printf '%s' "$entry" | jq -r .license)" "MIT" "created entry license from manifest"
assert_eq "$(printf '%s' "$entry" | jq -r .description)" "test fixture" "created entry description"
# The repo slug is derived from origin, which is a local path in the fixture:
# it must be a non-empty owner/repo pair, not the whole path.
assert_eq "$(printf '%s' "$entry" | jq -r '.source.repo | split("/") | length')" \
    "2" "created entry repo slug shape"
```

- [ ] **Step 2: Run the tests**

```sh
bash tests/release-test.sh
```

Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add tests/release-test.sh
git commit -m "✅ pin first-publication entry creation through release.sh"
```

---

### Task 6: `release.just` wrappers and the `_import-check` contract

**Files:**
- Modify: `release.just:38-139` (recipe bodies), `release.just:1-33` (header comment)
- Modify: `justfile:86-127` (`_import-check`)

**Interfaces:**
- Consumes: `release.sh`'s CLI from Tasks 1-2.
- Produces: the `resume-release` recipe consumers call.

- [ ] **Step 1: Replace the `release` body and add `resume-release`**

In `release.just`, replace everything from `# Bump plugin.json, commit, tag…`
through the end of the recipe (line 139) with:

```just
# Bump plugin.json, commit, tag, push, GitHub release, bump marketplace.
release bump='patch': prerelease
    bash "{{toolkit_prefix}}/release.sh" "{{bump}}"

# Complete a release that landed only partially. Idempotent, no gate.
resume-release:
    bash "{{toolkit_prefix}}/release.sh" --resume
```

`resume-release` has no `prerelease` dependency on purpose: the code is already
committed and tagged, and re-running a consumer's paid gate to push a tag would
make the recovery path expensive enough to route around.

Add to the file header comment, after the `MARKETPLACE_DIR` paragraph:

```
# If a release dies partway — a rejected push, a `gh` failure — the plugin is
# left tagged at the new version with a stale marketplace entry. `just
# resume-release` completes it: it pushes whatever is missing and is a no-op
# when everything already landed.
```

- [ ] **Step 2: Extend `_import-check`**

In `justfile`'s `_import-check`, after the `check widened …` line, add:

```bash
    # `resume-release` must resolve with no gate dependency: a consumer must be
    # able to finish an interrupted release without re-running a paid prerelease.
    out=$(just --justfile "$tmp/plain/justfile" --dry-run resume-release 2>&1)
    grep -q 'release.sh --resume' <<< "$out" \
        || { echo "error: resume-release did not reach release.sh: $out" >&2; exit 1; }
    if grep -q 'stub-precommit' <<< "$out"; then
        echo "error: resume-release ran the commit gate" >&2
        exit 1
    fi
```

Update the recipe's final echo:

```bash
    echo "release.just import: ok (plain + widened + missing gate, resume-release)"
```

- [ ] **Step 3: Run the gate**

```sh
just precommit
```

Expected: `ok`, with `release.just import: ok (plain + widened + missing gate, resume-release)`.

Note the `if` form on the second assertion: `grep -q … && { … }` returns the
grep's status, so under `set -e` a *non*-matching grep — the passing case — would
abort the recipe.

- [ ] **Step 4: Verify the recipe surface by hand**

```sh
just --justfile /dev/stdin --list <<'EOF'
import '/Users/david/code/claude-plugin-dev/release.just'
precommit:
    @echo stub
prerelease: precommit
EOF
```

Expected: `release`, `resume-release`, `check-version` and `update-plugin-dev`
all listed, each with a single-line doc comment.

- [ ] **Step 5: Commit**

```bash
git add release.just justfile
git commit -m "✨ expose resume-release and thin the release recipe"
```

---

### Task 7: Documentation, and delete the brief

**Files:**
- Modify: `docs/design.md`
- Create: `docs/changelog/<today>-resume-release.md`
- Modify: `docs/changelog.md`
- Delete: `brief-half-landed-release-recovery.md`
- Check: `README.md`, `install.sh` for recipe lists needing `resume-release`

- [ ] **Step 1: Add the design section**

In `docs/design.md`, after "`check-version.sh`: catching a partially-completed
release", add a section titled **"Recovery: `resume-release` and the shared
release tail"** covering, in present tense:

- The tail (push branch, push tag, GitHub release, marketplace) is one idempotent
  block that both `release` and `resume-release` run; state is probed with
  `git ls-remote` and `gh release view` so the answer is authoritative without a
  fetch.
- Resume takes its version from the manifest and requires the local tag to
  exist — it completes a release, it never starts one.
- A remote tag at a different sha is an error, never a force-push.
- `resume-release` has no `prerelease` dependency, and why.
- Why the flow moved out of the recipe body: shellcheck coverage, offline
  testability, no just/bash quoting seam.
- Why this repo's own self-release recipe stays bespoke (copy the reasoning from
  the spec's Out of scope section).

Then revisit the **Limitations** list: "release is not atomic" stays true, but its
consequence is now recoverable — state that rather than deleting the entry.

- [ ] **Step 2: Write the changelog entry**

Create `docs/changelog/<release-date>-resume-release.md`, dated the day the
release ships, following the shape of the existing entries: what moved and the
reasoning available at the time. Ground it in the gitlore 0.4.3 incident from the
spec's Problem section, and record that the toolkit's own `v0.4.1` failed the
same way (a `VERSION` bump commit with no tag).

- [ ] **Step 3: Add the changelog pointer**

Add a line at the top of the list in `docs/changelog.md`:

```markdown
- [<date> — `resume-release`](changelog/<date>-resume-release.md) — the release tail became an idempotent block both `release` and a recovery path run (vX.Y.Z)
```

- [ ] **Step 4: Check for stale recipe lists**

```sh
grep -rn 'just release\|check-version\|precommit' README.md install.sh
```

If either lists the recipes the toolkit provides, add `resume-release`. If they
only describe installation, leave them alone.

- [ ] **Step 5: Delete the brief**

```bash
git rm brief-half-landed-release-recovery.md
```

- [ ] **Step 6: Run the gate and commit**

```sh
just precommit
git add docs release.just
git commit -m "📝 document resume-release"
```

---

### Task 8: Release and propagate

**Files:** none in this repo beyond `VERSION` (the self-release recipe owns it).

- [ ] **Step 1: Cut the toolkit release**

```sh
just release minor
```

Expected: `VERSION` at `0.5.0`, tag `v0.5.0` pushed, GitHub release created.
If it dies partway, finish it by hand — `git push`, `git push origin v0.5.0`,
`gh release create v0.5.0 --title "Release 0.5.0" --generate-notes` — which is
exactly why the self-release recipe stays bespoke.

- [ ] **Step 2: Propagate to consumers**

In each consumer, `just update-plugin-dev v0.5.0`. `gitlore` already defines
`prerelease: precommit evals` and needs no justfile edit. `handoff` and `gitmoji`
have not adopted v0.4.0 yet: each needs `prerelease: precommit` added **in the
same commit as the subtree pull**, or their justfiles fail to compile on arrival —
every recipe, not just `release`.

- [ ] **Step 3: Verify in one consumer**

```sh
just check-version && just --list
```

Expected: `check-version: in sync (…)`, and `resume-release` present in the list.

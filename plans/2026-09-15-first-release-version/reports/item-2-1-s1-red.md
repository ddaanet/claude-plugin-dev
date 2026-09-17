# Item 2.1, slice 1 — RED

Target: `tests/hook-test.sh`. SUT (`toolkit/version-guard.sh`) is untouched.

## Harness changes

1. **`unset $(git rev-parse --local-env-vars)`** added right after
   `set -euo pipefail`, before the existing `unset CDPATH`. Modelled on
   `tests/release-test.sh:8-13`: when this suite runs as the repo's own
   pre-commit hook, the enclosing `git commit` leaks
   `GIT_DIR`/`GIT_INDEX_FILE`/etc. into the test process's environment. The new
   git-repo fixture (below) runs real git commands of its own, so a leaked
   `GIT_DIR` would redirect `git init` at this repo instead of the fixture.
   Comment states this reasoning inline, same shape as the
   `# shellcheck disable=SC2046` sibling.

2. **`run_guard` gains a project argument and an env-injection mechanism**, both
   additive:

   ```sh
   run_guard() {
       local payload="$1"
       local project="${2:-$proj}"
       local extra_env=("${@:3}")
       set +e
       guard_out="$(printf '%s' "$payload" \
           | env CLAUDE_PROJECT_DIR="$project" PATH="$guard_path" "${extra_env[@]}" \
                 bash toolkit/version-guard.sh 2>"$guard_err")"
       guard_rc=$?
       set -e
   }
   ```

   `$2` defaults to `$proj`, so every existing single-argument call site
   (`run_guard "$json"`) is unchanged and untouched — none were edited. `$3...`
   is an array of `NAME=value` strings spliced into `env` ahead of the
   `bash toolkit/version-guard.sh` invocation; slice 1 doesn't need it (empty
   array, no-op), but it's built now per the dispatch brief so slice 5's
   `GIT_DIR=…` case doesn't require touching every call site again. `guard_path`
   is untouched and still works exactly as before (still reads from the
   enclosing scope, still restorable per-scenario for the BSD-realpath stub).

3. **`assert_contains` / `assert_not_contains` helpers**, in the
   `assert_eq`/`fail` style:

   ```sh
   assert_contains() {
       # $1=haystack $2=needle $3=label. Match against a specific extracted
       # field (e.g. permissionDecisionReason alone), never the whole payload
       # blob -- an unrelated line can satisfy a needle and hide the miss.
       if [[ "$1" != *"$2"* ]]; then
           fail "$3: expected to contain '$2', got '$1'"
       fi
   }
   assert_not_contains() {
       # $1=haystack $2=needle $3=label
       if [[ "$1" == *"$2"* ]]; then
           fail "$3: expected NOT to contain '$2', got '$1'"
       fi
   }
   ```

## Fixture

`git_proj`, a second `mktemp -d`, alongside the existing non-repo `$proj`:

```sh
git_proj="$(mktemp -d)"
git init -q "$git_proj"
mkdir -p "$git_proj/.claude-plugin"
cat > "$git_proj/.claude-plugin/plugin.json" <<'JSON'
{
  "name": "fixture",
  "version": "1.2.3",
  "license": "MIT"
}
JSON
```

Added to the existing `trap 'rm -rf "$proj" "$guard_err" "$git_proj"' EXIT` (the
trap body is single-quoted, so `$git_proj` resolves at exit time even though
it's assigned after the `trap` line runs).

**No commit, no `user.name`/`user.email`.** Checked directly before choosing:

```
$ d="$(mktemp -d)" && git -C "$d" init -q && git -C "$d" tag --list; echo "rc=$?"
rc=0
```

`git tag --list` on a zero-commit repo exits 0 with no output — exactly what a
"no tags" fixture needs to produce. A commit (and the `user.name`/`user.email`
it would require) buys nothing this suite checks, so the empty-HEAD repo is the
fixture: simpler and doesn't assert a git-identity concern the scenario doesn't
have.

## Scenario

Inserted after the BSD-realpath block, before `market="$proj/marketplace.json"`:

```sh
echo "=== version-guard (no tags: initial-release wording) ==="
run_guard "$(jq -nc --arg cwd "$git_proj" --arg fp "$git_proj/.claude-plugin/plugin.json" \
    '{cwd:$cwd, tool_name:"Edit", tool_input:{file_path:$fp, old_string:"1.2.3", new_string:"9.9.9"}}')" \
    "$git_proj"
assert_deny "version-guard no-tags"
reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$guard_out")"
assert_contains "$reason" "never been released" "version-guard no-tags reason: never-released wording"
assert_contains "$reason" "will publish" "version-guard no-tags reason: will-publish wording"
assert_not_contains "$reason" "last released version" "version-guard no-tags reason: no last-released wording"
```

The reason is extracted with
`jq -r '.hookSpecificOutput.permissionDecisionReason'` from `$guard_out` and
each assertion runs against that extracted string, never against `$guard_out`
whole.

## RED proof

`bash tests/hook-test.sh` output (full run):

```
=== version-guard (Edit version change: deny) ===
=== version-guard (Edit bare version value: deny) ===
=== version-guard (Edit unrelated field: allow) ===
=== version-guard (Write version change: deny) ===
=== version-guard (unrelated file: allow) ===
=== version-guard (drifted payload cwd: deny) ===
=== version-guard (relative file_path: deny) ===
=== version-guard (BSD realpath, unrelated file: allow) ===
=== version-guard (no tags: initial-release wording) ===
FAIL: version-guard no-tags reason: never-released wording: expected to contain 'never been released', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.

The manifest version is the last released version. It is changed only by
'just release {patch|minor|major}', which validates state, bumps, commits,
tags, and pushes in one step. The release recipe also refuses if plugin.json
and the latest git tag disagree.

If the goal is to ship a release, invoke the recipe instead of editing this
file. Do not bypass this guard, modify the recipe, or alter version state by
other means.'
FAIL: version-guard no-tags reason: will-publish wording: expected to contain 'will publish', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.

The manifest version is the last released version. It is changed only by
'just release {patch|minor|major}', which validates state, bumps, commits,
tags, and pushes in one step. The release recipe also refuses if plugin.json
and the latest git tag disagree.

If the goal is to ship a release, invoke the recipe instead of editing this
file. Do not bypass this guard, modify the recipe, or alter version state by
other means.'
FAIL: version-guard no-tags reason: no last-released wording: expected NOT to contain 'last released version', got 'plugin.json version edit refused: 1.2.3 -> 9.9.9.

The manifest version is the last released version. It is changed only by
'just release {patch|minor|major}', which validates state, bumps, commits,
tags, and pushes in one step. The release recipe also refuses if plugin.json
and the latest git tag disagree.

If the goal is to ship a release, invoke the recipe instead of editing this
file. Do not bypass this guard, modify the recipe, or alter version state by
other means.'
=== check-version (MARKETPLACE_DIR unset: skip) ===
=== check-version (marketplace.json missing: skip) ===
=== check-version (no entry: skip) ===
=== check-version (in sync: pass) ===
=== check-version (drift: fail) ===

3 failure(s)
```

(exit code 1, captured separately: `rc=1`)

Per-assertion attribution:

- **`never-released wording`**: FAILED on its assertion — the extracted reason
  does not contain `never been released`; today's SUT emits "The manifest
  version is the last released version." instead.
- **`will-publish wording`**: FAILED on its assertion — the extracted reason
  does not contain `will publish`; today's SUT has no such phrase.
- **`no last-released wording`**: FAILED on its assertion (the negative check) —
  the extracted reason *does* contain `last released version`, which is exactly
  the string this assertion rejects.

All three failures are `fail()` calls from a failed `[[ ]]` condition inside the
new `assert_contains`/`assert_not_contains` helpers — none are shell errors,
`set -e` exits, or `assert_deny` failures.

**Pre-existing scenarios**: all eight version-guard scenarios that ran before
the new one, plus all five `check-version` scenarios after it, produced no
`FAIL` line — confirmed unchanged and passing. The harness changes
(`unset $(git rev-parse --local-env-vars)`, the new `run_guard` signature with
its default second argument, the new fixture) are transparent to them.

**New fixture's `assert_deny`**: no `FAIL: version-guard no-tags exit code`,
`no deny decision`, `no permissionDecisionReason`, `no systemMessage`, or
`wrote to stderr` line appears — `assert_deny` passed in full for the
tagless-repo fixture. The deny decision itself is not new behaviour; only the
three wording assertions below it are red.

## Lint

```
$ bash -n tests/hook-test.sh   # syntax OK
$ shellcheck tests/hook-test.sh   # no output, clean
```

## Not done (out of scope for slice 1)

No change to `toolkit/version-guard.sh`. Slices 2–6 (tag listing, wording
branch, `GIT_DIR` env-injection use, listing-failure fallback wording, etc.) are
not implemented or pre-built here beyond the `run_guard` mechanism the brief
asked to build now.

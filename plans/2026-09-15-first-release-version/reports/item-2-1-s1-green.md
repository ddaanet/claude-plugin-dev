# Item 2.1, slice 1 — GREEN

Target: `toolkit/version-guard.sh`. Tests (`tests/hook-test.sh`) were already
written and reviewed; not modified.

## Implementation as landed

Two edits to `toolkit/version-guard.sh`, both after the existing deny gate at
the former `:78`
(`[[ -z "$proposed" || "$proposed" == "$current" ]] && exit 0`):

1. **Header comment (`:3-5` originally)** restated to cover both cases: the
   release recipe still owns version bumps in general, but the "desync from the
   latest tag" framing only applies once a tag exists — a plugin that has never
   released has no tag to desync from.

2. **The tag listing**, placed immediately after the deny gate, never before it
   — so it cannot turn a deny into an allow and never runs on an allow path:

   ```sh
   release_tags="$(git -C "$project" tag --list 'v*' --sort=-v:refname 2>/dev/null \
     | { grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || [ "$?" -eq 1 ]; })" || true
   ```

   - `git -C "$project"`, not a bare `git tag`: `$project` is the same
     `CLAUDE_PROJECT_DIR`-derived variable already computed at `:21`, not the
     payload `cwd`.
   - `2>/dev/null` on the `git -C` listing: on a `CLAUDE_PROJECT_DIR` that is
     not a repository at all (every existing `$proj` fixture in
     `tests/hook-test.sh`, and the common pre-first-release case), git's "not a
     git repository" is an expected outcome here rather than a diagnostic, and
     `tests/hook-test.sh`'s `assert_deny` asserts the hook's stderr stays empty.
     The pre-existing `$proj` scenarios are a live test of this.
   - The semver filter is `release.sh:269`'s `semver_tags` body, duplicated
     rather than sourced (`release.sh` runs its flow at top level and isn't
     written to be sourced; a shared helper would be a new shipped path for one
     `grep -E` line — the runbook says so explicitly). Same shape, including
     absorbing exactly `grep`'s status 1 via `|| [ "$?" -eq 1 ]`, matching
     `release.sh:269`'s own comment about why that distinction matters (an empty
     result is a value, a real grep error still propagates).
   - The accepted-bound comment sits beside the listing in the script: a
     `CLAUDE_PROJECT_DIR` that is not itself a repo but sits inside one lists
     the *enclosing* repo's tags (git walks up to find `.git`), which changes
     the wording below and never the deny decision already established above it.
   - **The trailing `|| true` was not in the original plan and was added during
     GREEN** after the first full-suite run showed all eight pre-existing
     `$proj` (non-repo) deny scenarios failing with rc=128 and no hook output at
     all. Root cause, confirmed with an isolated repro: with
     `set -euo pipefail`, a failed `git -C` (exit 128, "not a git repository")
     propagates through the pipe even though the `grep` stage already turns its
     own "no match" into success — bash's pipefail reports the right-most
     **non-zero** exit status among *all* stages, not just the last stage's own
     (possibly-zero) status, so it keeps scanning left past the successful grep
     stage and finds git's 128. That aborted the whole script under `set -e`
     before it ever reached the `jq` output. The `|| true` on the assignment
     absorbs exactly that, verified in isolation
     (`bash -c 'set -euo pipefail; release_tags="$(...)" || true; echo rc=$?'` →
     `rc=0`) and then against the full suite (below). A comment beside it in the
     script explains why it's needed rather than decorative.

3. **The two-way wording branch**:

   ```sh
   if [[ -z "$release_tags" ]]; then
     read -r -d '' agent_reason <<EOF || true
   plugin.json version edit refused: $current -> $proposed.

   This plugin has never been released -- no vX.Y.Z tag exists yet. The first
   release will publish whatever plugin.json holds when
   'just release {patch|minor|major}' runs; that recipe validates state,
   bumps, commits, tags, and pushes in one step.

   Do not bypass this guard, modify the recipe, or alter version state by
   other means.
   EOF
   else
     read -r -d '' agent_reason <<EOF || true
   plugin.json version edit refused: $current -> $proposed.

   The manifest version is the last released version. It is changed only by
   'just release {patch|minor|major}', which validates state, bumps, commits,
   tags, and pushes in one step. The release recipe also refuses if plugin.json
   and the latest git tag disagree.

   If the goal is to ship a release, invoke the recipe instead of editing this
   file. Do not bypass this guard, modify the recipe, or alter version state by
   other means.
   EOF
   fi
   ```

   The steady-state (`else`) branch is byte-identical to the pre-slice-1
   message. The initial-release branch:
   - contains `never been released` and `will publish` (phrase-exact per the
     dispatch);
   - never contains `last released version`, including negated — the phrase is
     avoided entirely rather than rephrased into a negation;
   - keeps the existing no-bypass sentence verbatim ("Do not bypass this guard,
     modify the recipe, or alter version state by other means.");
   - does not repeat `$proposed` after the opening line, and does not name the
     recipe as a route to reach the proposed version — it describes what the
     first release publishes in general terms, not a way to get to `9.9.9`. This
     isn't asserted by slice 1 (that's slice 2), but the dispatch flagged it as
     a defect to avoid shipping now.
   - `human_msg`/`systemMessage` construction is untouched and sits after the
     `if`/`fi`, unconditional — identical for both branches (slice 3's concern,
     not exercised here).

## Left out, on purpose

- **Clearing repo-local `GIT_*` variables** around the listing — not
  implemented. Slice 5 must be able to fail against this code; nothing in this
  diff touches `GIT_DIR`/`GIT_INDEX_FILE`/etc. near the listing.
- **Capturing a failed listing separately from an empty one** — not implemented.
  A failed `git -C` (non-repo case) folds into the same `release_tags=""` →
  initial-release branch as a genuinely-empty tag list. Slice 6 must be able to
  fail against this code; nothing here distinguishes the two.

## Verification

`bash -n`, `shellcheck`, both clean before and after the `|| true` fix.

Full suite, final run:

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
=== check-version (MARKETPLACE_DIR unset: skip) ===
=== check-version (marketplace.json missing: skip) ===
=== check-version (no entry: skip) ===
=== check-version (in sync: pass) ===
=== check-version (drift: fail) ===

all hook scenarios passed
EXIT=0
```

Zero failures, all fourteen scenarios (nine version-guard, five check-version)
pass, including the three new wording assertions and all eight pre-existing
version-guard scenarios (the `$proj`/non-repo listing- failure fallback and the
fixture's `assert_deny`, i.e. clean stderr).

`just precommit`: ran to completion, final line `ok`. Includes `bash -n`,
`shellcheck`, `_import-check`, `tests/docs-test.sh` (`docs ok`),
`tests/doc-sync-test.sh` (`doc sync ok`), `tests/dist-tree-test.sh`
(`dist tree ok`), `tests/update-plugin-dev-test.sh`
(`update-plugin-dev scenarios passed`), `tests/release-test.sh`
(`all release scenarios passed`), and `format-docs`.

## Commit

`df2c4c05e728403a406cf77798c662e26fc130c1` —
`✨ Item 2.1/1 — initial-release wording in the version-guard deny reason`

(gitmoji's commit-msg hook rewrote the `feat:` prefix to the emoji, as expected.
`.claude/handoff-task.md`, `.claude/handoff-todo.md`, and `memory` rode this
commit — they were already staged before this dispatch started, per the
dispatch's note that they were expected to.)

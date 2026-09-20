# Item 1.3 / Slice 2 — RED report

## What was written

Added one new scenario to `tests/self-release-test.sh`, inserted between the
`=== vnext on ancestry is not the latest tag ===` scenario (slice 1) and
`=== an unfinished release refuses a new one ===`:

```sh
echo "=== release tag off ancestry still triggers drift guard ==="
# v0.9.0 sits on a branch that never merged into main, so it is unreachable
# from HEAD -- yet it is still the latest RELEASE tag, and toolkit/VERSION
# (0.1.0, from v0.1.0's release) must be read as stale against it. Asking git
# for the nearest reachable tag instead makes v0.9.0 invisible, so the drift
# guard sees only the reachable v0.1.0, which matches, and the release
# proceeds -- the newer tag went unnoticed, not merely unranked.
new_sandbox
git -C "$repo" checkout -q -b abandoned
commit_in_repo abandoned.md "on a branch that never merged"
git -C "$repo" tag -a v0.9.0 -m "abandoned release attempt"
git -C "$repo" checkout -q main
git -C "$repo" branch -q -D abandoned
run minor
assert_eq "$rc" 1 "ancestry: exit status"
assert_contains "$out" "does not match latest tag (v0.9.0)" "ancestry: names off-ancestry tag"
```

Uses `new_sandbox` (leaves `v0.1.0` reachable, `toolkit/VERSION` at `0.1.0`,
satisfying `require_prior_release_published`) plus the existing `commit_in_repo`
helper on a throwaway branch that is deleted after tagging, so `v0.9.0` remains
a ref but is unreachable from `main`'s `HEAD`. No other scenario in the file was
touched; no fixture used by other scenarios (`new_sandbox`, `commit_in_repo`,
`block_push`, etc.) was modified.

## 1. Baseline run — must be green

Command:
`cd /Users/david/code/claude-plugin-dev && bash tests/self-release-test.sh`

```
=== happy path: minor bump publishes everything ===
=== bump arithmetic ===
=== vnext on ancestry is not the latest tag ===
=== release tag off ancestry still triggers drift guard ===
=== an unfinished release refuses a new one ===
=== resume finishes it ===
=== resume is idempotent ===
=== resume after later work on main ===
=== a partially published release still refuses a bump ===
=== resume refusals ===
=== never moves a published tag ===
=== preflight refusals ===
=== an unreadable origin refuses rather than proceeds ===
self-release.sh: ok
```

Green — the new test passes against the already-landed slice 1 fix (commit
`🐛 Item 1.3/1 — self-release lists and filters tags instead of git describe`).

## 2. Mutation applied

Saved a copy first
(`cp scripts/self-release.sh "$TMPDIR/self-release.sh.orig"`), then reverted
`release_preflight`'s tag determination to `git describe`:

```diff
-    tags=$(git tag --list 'v*' --sort=-v:refname) || die "git tag --list failed"
-    latest_tag=$(grep -m1 -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<< "$tags") || latest_tag=""
+    latest_tag=$(git describe --tags --abbrev=0 --match 'v*') || latest_tag=""
     latest_tag=${latest_tag#v}
```

## 3. Failing assertion output under the mutation

Command:
`cd /Users/david/code/claude-plugin-dev && bash tests/self-release-test.sh`

```
=== release tag off ancestry still triggers drift guard ===
FAIL: ancestry: exit status: expected '1', got '0'
FAIL: ancestry: names off-ancestry tag: output did not contain 'does not match latest tag (v0.9.0)'
  --- output ---
VERSION + tag: v0.2.0 created locally
dist tag dist-v0.2.0: created locally
To /tmp/claude-1000/tmp.D5P4JZzNWj/repo-origin.git
   cd5c918..01850aa  main -> main
branch main: pushed
To /tmp/claude-1000/tmp.D5P4JZzNWj/repo-origin.git
 * [new tag]         v0.2.0 -> v0.2.0
tag v0.2.0: pushed
To /tmp/claude-1000/tmp.D5P4JZzNWj/repo-origin.git
 * [new tag]         dist-v0.2.0 -> dist-v0.2.0
tag dist-v0.2.0: pushed
github release v0.2.0: created
Release v0.2.0 complete (consumers pull dist-v0.2.0)
  --------------
```

(Slice 1's `vnext` scenario also failed under the same mutation, as its own
report records — both scenarios fail under this one mutation, as the runbook
predicts.) Both failures are `assert_eq`/`assert_contains` value mismatches —
neither is an `ImportError`/`AttributeError`/`command not found` class error;
the captured `$out` shows the script ran a full release to completion instead of
refusing, confirming the drift guard was silently skipped under `describe`.

## 4. Restore confirmation

```
cd /Users/david/code/claude-plugin-dev && cp "$TMPDIR/self-release.sh.orig" scripts/self-release.sh && git diff --quiet -- scripts/self-release.sh && echo "RESTORE_OK: git diff --quiet exit 0"
RESTORE_OK: git diff --quiet exit 0
```

## 5. Post-restore run — closing green line

Command:
`cd /Users/david/code/claude-plugin-dev && bash tests/self-release-test.sh`

Closing line:

```
self-release.sh: ok
```

Full section list ran to completion, all thirteen `===` sections shown, no
failures.

## Scope confirmation

- `scripts/self-release.sh` — restored byte-for-byte (`git diff --quiet`
  confirmed exit 0); no lasting change.
- `tests/self-release-test.sh` — only the one new scenario above was added;
  slice 1's `vnext` scenario, the dist-tag-squatting comment, and all other
  scenarios (happy path, dist-split, clean-check exemptions, the ten refusals)
  are unmodified.
- Nothing was committed; the new test sits uncommitted in the working tree.

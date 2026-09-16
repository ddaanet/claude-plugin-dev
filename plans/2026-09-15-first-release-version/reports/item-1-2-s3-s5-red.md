# Item 1.2, slices 3-5 — RED report (batched)

| Slice | Passed on arrival | Discriminates its named mutation(s) |
|---|---|---|
| 3 — origin listing is version-sorted | yes | yes, all three mutations |
| 4 — probe precedes the drift check | yes | yes |
| 5 — failed listing refuses, capture rule | yes | yes, but see the finding below — the mutated run does not reach a clean "publish"; it crashes on a different, already-flagged pre-existing bug |

All three scenarios passed against unchanged `HEAD`, as the dispatch expected
(slice 1's GREEN already implemented the declared interface). Every named
mutation was applied, run, shown to fail the new scenario and nothing else, then
reverted from the pre-mutation copy at
`/tmp/claude-1000/item-1-2-s3-s5/release.sh.orig`, with
`git diff --stat toolkit/release.sh` verified empty after each restore.

## Slice 3 — the origin listing is version-sorted

### Scenario, added to `tests/release-test.sh`

```sh
echo "=== release: origin's listing is read version-sorted, not lexicographically ==="
new_sandbox "1.2.3"
lose_tag "$plugin"
for t in v1.9.0 v1.10.0 v1.11.0; do
    git -C "$plugin" tag "$t"
    git -C "$plugin" push -q origin "$t"
    lose_tag "$plugin" "$t"
done
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "origin-sort exit code"
assert_contains "$out" "v1.11.0" "origin-sort names the newest origin tag"
assert_not_contains "$out" "v1.10.0" "origin-sort does not name the second-newest origin tag"
assert_not_contains "$out" "v1.9.0" "origin-sort does not name the third-newest origin tag"
```

`new_sandbox "1.2.3"` seeds `v1.2.3`, pushed. `lose_tag "$plugin"` drops it
locally (origin keeps it). Three more semver tags are created, pushed, and
dropped locally, so the local clone carries no `v*` tag at all while origin
carries four (`v1.2.3`, `v1.9.0`, `v1.10.0`, `v1.11.0`) — forcing
`release_preflight` into the origin probe.

### Run 1 — unchanged `HEAD`

Full suite: exit 0, `all release scenarios passed`. This scenario's hint names
`v1.11.0` and neither `v1.10.0` nor `v1.9.0`.

### Run 2 — mutation: drop `--sort=-v:refname` from `origin_release_tags`

```diff
-    listing=$(git ls-remote --tags --sort=-v:refname origin) || return 1
+    listing=$(git ls-remote --tags origin) || return 1
```

```
FAIL: origin-sort names the newest origin tag: output did not contain 'v1.11.0'
  --- output ---
hint: origin already has release tags for this plugin — the newest is
      v1.10.0, missing from this clone. Run `git fetch --tags` to catch up,
FAIL: origin-sort does not name the second-newest origin tag: output contained 'v1.10.0'

2 failure(s)
```

Confirms the runbook's claim empirically on this box (git 2.47.3): without the
sort, `ls-remote`'s lexicographic order puts `v1.10.0` first (the wrong tag) —
the first line is wrong. Exactly 2 failures, both this scenario; no other
scenario moved. Restored; `git diff --stat toolkit/release.sh` empty.

### Run 3 — mutation: `sed -n '1p'` → `sed -n '$p'`

```diff
-            origin_newest=$(printf '%s\n' "$origin_tag_list" | sed -n '1p')
+            origin_newest=$(printf '%s\n' "$origin_tag_list" | sed -n '$p')
```

```
FAIL: origin-sort names the newest origin tag: output did not contain 'v1.11.0'
  --- output ---
hint: origin already has release tags for this plugin — the newest is
      v1.2.3, missing from this clone. Run `git fetch --tags` to catch up,

1 failure(s)
```

With the sort still in place, the last line of the sorted (newest-first) listing
is `v1.2.3` — the oldest, and also the wrong tag. Exactly 1 failure (the "does
not contain v1.10.0/v1.9.0" assertions still hold, since `v1.2.3` contains
neither). Restored; diff empty.

### Run 4 — mutation: both together

```diff
-    listing=$(git ls-remote --tags --sort=-v:refname origin) || return 1
+    listing=$(git ls-remote --tags origin) || return 1
@@
-            origin_newest=$(printf '%s\n' "$origin_tag_list" | sed -n '1p')
+            origin_newest=$(printf '%s\n' "$origin_tag_list" | sed -n '$p')
```

```
FAIL: origin-sort names the newest origin tag: output did not contain 'v1.11.0'
  --- output ---
hint: origin already has release tags for this plugin — the newest is
      v1.9.0, missing from this clone. Run `git fetch --tags` to catch up,
FAIL: origin-sort does not name the third-newest origin tag: output contained 'v1.9.0'

2 failure(s)
```

Without the sort, `ls-remote`'s lexicographic order is
`v1.10.0 v1.11.0 v1.2.3 v1.9.0`; the last line (`v1.9.0`) is also wrong —
confirming the runbook's "the first line and the last are both the wrong tag"
empirically, on this fixture, with this box's git. Exactly 2 failures. Restored;
diff empty.

**Slice 3 closes the recorded debt.** All three named mutations are caught by
this one scenario; none of them passed unnoticed.

## Slice 4 — the probe precedes the drift check

### Scenario, added to `tests/release-test.sh`

```sh
echo "=== release: the lost-tag probe runs before the version-drift check ==="
new_sandbox "1.2.3"
make_virgin "1.2.3"
jq '.version = "1.2.4"' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" commit -qam "hand-advance to 1.2.4"
git -C "$plugin" push -q origin main
git -C "$plugin" tag v1.2.4
git -C "$plugin" push -q origin v1.2.4
lose_tag "$plugin" v1.2.4
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "probe-before-drift exit code"
assert_contains "$out" "v1.2.4" "probe-before-drift names the lost origin tag"
assert_contains "$out" "git fetch --tags" "probe-before-drift names the fetch remedy"
assert_not_contains "$out" "version drift" "probe-before-drift must not read as a drift refusal"
assert_not_contains "$out" "just resume-release" "probe-before-drift must not offer the drift recovery command"
```

`make_virgin "1.2.3"` drops `v1.2.3` locally and on origin (a no-op re-seed at
the same manifest version, still pushes). The manifest is then hand-advanced to
`1.2.4`, committed, pushed; `v1.2.4` is tagged, pushed, then dropped locally.
Entry stays at `1.2.3` (seeded by `new_sandbox`). No bump argument.

### Run 1 — unchanged `HEAD`

Full suite: exit 0, `all release scenarios passed`.

### Run 2 — mutation: move the lost-tag probe block to after `check-version.sh`

Applied with a small Python script (verbatim block cut from its old location,
re-inserted directly after the `check-version.sh` call block; net diff is a pure
reorder, confirmed by `diff` showing the same 9-line block appearing after
instead of before):

```
FAIL: probe-before-drift names the lost origin tag: output did not contain 'v1.2.4'
  --- output ---
check-version: version drift — plugin.json=1.2.4 marketplace.json=1.2.3
  bump both to the same value before release.
FAIL: probe-before-drift names the fetch remedy: output did not contain 'git fetch --tags'
FAIL: probe-before-drift must not read as a drift refusal: output contained 'version drift'
FAIL: probe-before-drift must not offer the drift recovery command: output contained 'just resume-release'

4 failure(s)
```

Under the mutation, `check-version.sh` runs first, finds `plugin.json=1.2.4` vs
`marketplace.json=1.2.3`, and `release_preflight` dies on the drift path
(`fix the version drift above before releasing`, preceded by the
`just resume-release` hint) — never reaching the origin probe at all. Exactly 4
failures, all this scenario; no other scenario moved. Restored; diff empty.

## Slice 5 — a failed listing refuses, and the capture rule

### Scenarios, added to `tests/release-test.sh`

```sh
echo "=== release: a listing that fails on an unreachable origin URL refuses, saying nothing was done ==="
new_sandbox "1.2.3"
make_virgin "1.2.3"
git -C "$plugin" remote set-url origin "$sandbox/does-not-exist"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "unreachable-origin exit code"
assert_contains "$out" "could not verify this plugin's release history on origin" \
    "unreachable-origin names the unverifiable probe"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "unreachable-origin created no local tag"
assert_eq "$(cat "$GH_LOG")" "" "unreachable-origin must not call gh"

echo "=== release: a listing that fails with no origin remote at all refuses, saying nothing was done ==="
new_sandbox "1.2.3"
make_virgin "1.2.3"
git -C "$plugin" remote remove origin
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "no-origin exit code"
assert_contains "$out" "could not verify this plugin's release history on origin" \
    "no-origin names the unverifiable probe"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "no-origin created no local tag"
assert_eq "$(cat "$GH_LOG")" "" "no-origin must not call gh"
```

Both breakages happen after `make_virgin`, which pushes while origin is still
healthy. `new_sandbox "1.2.3"` seeds the marketplace entry, so
`marketplace_entry_exists=1` and `common_preflight` does not require an `origin`
remote to derive a `source` from — confirmed empirically (see below) that both
fixtures reach the origin probe rather than being refused earlier by
`common_preflight`.

### Run 1 — unchanged `HEAD`

Full suite: exit 0, `all release scenarios passed`. Both scenarios pass, each
naming the fixed substring
`could not verify this plugin's release history on origin`.

**Finding on fixture (b) (`git remote remove origin`):** confirmed via manual
`bash -x` trace against unchanged `HEAD` and via the passing assertions above
that `common_preflight` does **not** refuse this fixture at `:176-177` (the "no
entry → need origin to derive one" check) — that branch is only taken when
`marketplace_entry_exists=0`, and here the entry exists. The run reaches
`release_preflight`, `release_tags` (empty, locally tagless), then
`origin_release_tags`'s own `git ls-remote … origin` call, which fails because
there is no `origin` remote configured at all
(`fatal: 'origin' does not appear to be a git repository`), and dies there. So
(b) does reach the probe on the landed code, as the runbook expected — the
"entry is what lets (b) reach the probe" claim holds.

### Run 2 — mutation: capture rule — `origin_tag_list=$(origin_release_tags) || die …` → bare `[ -n "$(origin_release_tags)" ]`

```diff
-        local origin_tag_list origin_newest
-        origin_tag_list=$(origin_release_tags) \
-            || die "could not verify this plugin's release history on origin — nothing was done"
-        if [ -n "$origin_tag_list" ]; then
-            # First line, because origin_release_tags sorts newest first; sed
-            # and not `head -1`, for the SIGPIPE reason spelled out at the
-            # latest_tag read below. Neither printf nor sed can fail on an
-            # already-captured non-empty string, so the status check on
-            # origin_tag_list above is the only one this needs.
-            origin_newest=$(printf '%s\n' "$origin_tag_list" | sed -n '1p')
+        local origin_newest
+        if [ -n "$(origin_release_tags)" ]; then
+            origin_newest=$(origin_release_tags | sed -n '1p')
```

```
FAIL: unreachable-origin exit code: expected '1', got '128'
FAIL: unreachable-origin names the unverifiable probe: output did not contain 'could not verify this plugin's release history on origin'
  --- output ---
fatal: '/tmp/claude-1000/item-1-2-s3-s5/tmp.mO1RjkKi4d/does-not-exist' does not appear to be a git repository
fatal: Could not read from remote repository.
...
FAIL: unreachable-origin created no local tag: expected '', got 'v1.2.3'

FAIL: no-origin exit code: expected '1', got '128'
FAIL: no-origin names the unverifiable probe: output did not contain 'could not verify this plugin's release history on origin'
  --- output ---
fatal: 'origin' does not appear to be a git repository
...
FAIL: no-origin created no local tag: expected '', got 'v1.2.3'

6 failure(s)
```

Exactly 6 failures (3 per scenario — "must not call gh" does **not** fail under
this mutation, see the finding below); no other scenario moved. Restored; diff
empty.

**Finding — the mutated run does not cleanly "publish"; it crashes on a
separate, already-flagged bug.** Traced with `bash -x` against a manually
reproduced fixture (a): under the mutation, `[ -n "$(origin_release_tags)" ]`
discards the failed listing's status exactly as intended — the `if` is false,
`release_preflight` falls through to the `first_release=1` branch, and
`bump_commit_tag` does create a local `v1.2.3` tag (this is the "reads as
'origin has no tags either'" part, and it is what the "created no local tag"
assertion catches). But the run then does **not** reach a completed publish:
`push_branch` calls
`remote_head=$(git ls-remote origin "refs/heads/$branch" | cut -f1)` — a bare
pipeline assignment with no `||` guard — which fails against the same broken
origin under `set -o pipefail`, and `set -e` kills the whole script there with
the git-fatal message on stderr and exit status 128. `gh` is never called
(`GH_LOG` stays empty, so that assertion does not fail), and the release does
not actually publish end to end. This is the same pre-existing capture-rule gap
the item-1-2-slice-1 code review already flagged as out-of-scope at
`toolkit/release.sh:438,466,562` (`ls-remote | cut` with no status check) — this
mutation is the first fixture to actually trigger it, incidentally, as a side
effect of reaching `push_branch` at all. The scenario's three failing assertions
(exit code, message, tag-created) still correctly discriminate the named
mutation; the "and the run must publish" part of the dispatch's narrative does
not hold to completion on this fixture, and I'm reporting that rather than
forcing the assertions to match it.

## `bash -n` / shellcheck

```
$ bash -n tests/release-test.sh   # OK, no output
$ shellcheck tests/release-test.sh   # OK, no output
```

## State on exit

- `toolkit/release.sh` — **untouched.** `git diff --stat toolkit/release.sh` is
  empty after the final restore, verified again just before writing this report.
  Every mutation (3 for slice 3, 1 for slice 4, 1 for slice 5) was applied and
  reverted from a pre-mutation copy at
  `/tmp/claude-1000/item-1-2-s3-s5/release.sh.orig` (this shell's `$TMPDIR` was
  unset — the documented failure mode — so an explicit absolute scratch path was
  used; nothing was left in the repo root, confirmed with
  `git status --short --untracked-files=all`).
- `tests/release-test.sh` — **modified, uncommitted.** Five new scenarios added
  (one for slice 3, one for slice 4, two for slice 5), inserted after slice 2's
  uncommitted "hand-advanced" scenario and before "non-semver v tags are not
  releases". No existing scenario weakened or touched. `git status --short`
  shows only this file plus the pre-existing untracked `item-1-2-s2-red.md`
  report.
- **Nothing committed.**
- `bash tests/release-test.sh` against the unmodified tree — green,
  `all release scenarios passed`.
- `bash -n` and `shellcheck` on `tests/release-test.sh` — both clean.

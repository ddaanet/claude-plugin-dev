# Test review — Item 1.2, slice 1

**Scope:** `tests/release-test.sh`, the new
`=== resume hint names the tag already on origin ===` scenario, its `git` stub
and its fixture, plus
`plans/2026-09-18-deliverable-review-fixes/reports/item-1-2-s1-red.md`.
**Date:** 2026-09-20 **Mode:** review + fix

## Summary

The scenario was green against unchanged `toolkit/release.sh`, as slice 1's
control role requires, and the RED report's mutation proof that branch 1 is the
branch that fires is sound and reproduced here. But the fixture's green did not
depend on its own `git` stub: `new_sandbox` pushes a real `v1.2.3` to the
fixture origin, so `origin_release_tags` found the matching tag whether or not
the stub intercepted `ls-remote --tags`. Measured, not inferred — with the
stub's guard disabled the scenario stayed fully green. Since slice 2's entire
discrimination rests on the stub controlling the listing's size, a slice-1
control that cannot detect a dead stub is not a control. Fixed by deleting
origin's real copy of the tag, which makes branch 1 reachable only through the
stub.

**Overall assessment:** Ready.

## Issues Found

### Major Issues

1. **The scenario passed whether or not its `git` stub was live**
   - Location: `tests/release-test.sh`, scenario
     `=== resume hint names the tag already on origin ===`, the
     `new_sandbox "1.2.3"` fixture and the `ls-remote`/`--tags` stub guard.
   - Problem: `new_sandbox` ends with `git -C "$plugin" push -q origin v1.2.3`,
     so the fixture origin genuinely holds the matching tag. The scenario
     deleted it only from the local clone, leaving the real
     `git ls-remote --tags --sort=-v:refname origin` able to satisfy branch 1 on
     its own. Every assertion therefore held with the stub never consulted — the
     "fixture unreachable from the write path" shape, inverted: the stub was the
     write path and nothing pinned it. Proven by temporarily changing the stub's
     guard from `"ls-remote"` to `"ls-remote-DISABLED"` (so the stub delegated
     everything to the real binary) and re-running:

     ```
     === pipefail-stripped release_tags failure publishes nothing ===
     === resume hint names the tag already on origin ===

     all release scenarios passed
     ```

     Slice 2 sizes this same stub's post-filter listing to >=1 MB; a control
     that cannot tell the stub from the real origin cannot certify that listing
     is the one under test.
   - Fix: delete origin's copy too
     (`git -C "$plugin" push -q origin :refs/tags/v1.2.3`, the form
     `make_virgin` already uses). The stub then becomes the only source of an
     origin listing, and the scenario's existing assertions do the detecting.
   - **Status**: FIXED

### Minor Issues

1. **The hand-rolled local tag deletion bypasses `lose_tag`**
   - Location: same scenario, `git -C "$plugin" tag -d v1.2.3 >/dev/null`.
   - Note: `lose_tag` exists for exactly this state and its own comment names
     this item ("the 'lost tags' state Item 1.2's origin probe exists to catch …
     Used by slices 1-4"). Nine call sites use it; this one did not.
   - **Status**: FIXED — replaced with `lose_tag "$plugin"`.

2. **The stub emitted `v1.2.3` twice**
   - Location: same scenario, `seq 2 6` in the stub body.
   - Note: the loop's `n=3` iteration re-emitted the matching tag, so the
     slice's "matching tag first" property held partly by accident of the range
     rather than by construction, and the row count read as six distinct tags
     when it was five.
   - **Status**: FIXED — range moved to `seq 4 8`, past the matching tag, so
     `v1.2.3` appears exactly once and there are six distinct rows.

### Checked and clean (no finding)

- The stub intercepts `ls-remote` + `--tags` positionally and `exec`s the real
  binary otherwise. `grep -n ls-remote toolkit/release.sh` shows
  `origin_release_tags` holds the script's only `--tags` form; the three
  `git ls-remote origin <ref>` probes and every `git -C …` call fall through to
  the real binary. Same idiom as the two pipefail-stripped `tag --list`
  scenarios above it.
- No real `git tag` calls in the fixture — the listing is synthetic `printf`
  output, so the runbook's "~8000 real `git tag` calls costs minutes" warning
  does not apply.
- `assert_not_contains "$out" "just release"` is not satisfied by branch 1's own
  wording: branch 1 prints `just resume-release`, which holds no `just release`
  substring. Branches 2, 3 and 4 all print `just release`, so the absence
  discriminates against every wrong branch. Demonstrated by both mutation runs
  below, where it failed.
- Whitespace: `real_git="$(command -v git)"` is interpolated into the stub as a
  quoted `exec "$real_git" "$@"`, so a git path holding a space survives — the
  bound the scenario above it already states in its comment. No unquoted
  expansion and no word-splitting elsewhere in the fixture.
- Citation convention: the comment cites `resume_preflight` and quotes
  `git rev-parse -q --verify "refs/tags/$tag"`,
  `ls-remote --tags --sort=-v:refname origin` and the ladder's membership test.
  No `<script>.sh:<line>` anywhere.
- Item 1.1's two `pipefail`-stripped scenarios are untouched and passed on every
  run below. `git_wrapper_dir`, `real_git` and `saved_path` are reused names but
  this scenario is last in the file, and `PATH` is restored immediately after
  `run_in`.
- `bash -n` and `shellcheck -x` on `tests/release-test.sh`: both clean.

## Fixes Applied

- `tests/release-test.sh`, `=== resume hint names the tag already on origin ===`
  — `git -C "$plugin" tag -d v1.2.3 >/dev/null` replaced by `lose_tag "$plugin"`
  followed by `git -C "$plugin" push -q origin :refs/tags/v1.2.3`, so origin's
  real tag is gone and only the stub can supply an origin listing.
- Same scenario — stub loop range `seq 2 6` → `seq 4 8`, removing the duplicate
  `v1.2.3` row.
- Same scenario — comment extended with the two paragraphs stating why origin's
  real tag is deleted (what the ladder does without the stub, and the measured
  fact that leaving it made every assertion hold with the stub unconsulted) and
  why the loop range starts past the matching tag.

No change to `toolkit/release.sh`. Nothing committed.

## Verification runs

### Green, after the fixes, unchanged `toolkit/release.sh`

```
$ cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
...
=== the origin probes fail closed with pipefail stripped ===
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===
=== resume hint names the tag already on origin ===

all release scenarios passed
```

No `FAIL:` lines anywhere in the run; no other scenario broke.

### The stub is now load-bearing

Temporarily changed the stub's guard to `"ls-remote-DISABLED"` so it delegates
every call to the real binary, leaving the fixture otherwise intact:

```
=== resume hint names the tag already on origin ===
FAIL: resume hint names the tag already on origin: output did not contain 'origin already has v1.2.3'
  --- output ---
hint: no release was started at this version.
      run `just release` instead.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------
FAIL: resume hint names the tag already on origin remedy: output did not contain 'git fetch --tags'
  --- output ---
hint: no release was started at this version.
      run `just release` instead.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------
FAIL: resume hint names the tag already on origin must not advise a fresh release: output contained 'just release'
  --- output ---
hint: no release was started at this version.
      run `just release` instead.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------

3 failure(s)
```

Three of the five assertions now detect a dead stub. Before the fix this same
edit left the suite fully green. The test file was then restored from a copy
taken before the edit:

```
$ grep -c "ls-remote-DISABLED" tests/release-test.sh
0
$ diff -q "$TMPDIR/release-test.fixed.sh" tests/release-test.sh && echo "test file restored to fixed state"
test file restored to fixed state
```

### Branch 1 is the branch that fires — temporary `toolkit/release.sh` mutation

```
$ git diff --quiet -- toolkit/release.sh && echo "clean before mutation"
clean before mutation
```

```diff
-        if printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"; then
+        if printf '%s\n' "$origin_tag_list" | grep -qxF -- "TEMP-MUTATION-$tag"; then
```

```
=== resume hint names the tag already on origin ===
FAIL: resume hint names the tag already on origin: output did not contain 'origin already has v1.2.3'
  --- output ---
hint: origin has release tags, but none matching v1.2.3.
      run `git fetch --tags`, then run `just release <bump>`.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------
FAIL: resume hint names the tag already on origin must not advise a fresh release: output contained 'just release'
  --- output ---
hint: origin has release tags, but none matching v1.2.3.
      run `git fetch --tags`, then run `just release <bump>`.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------

8 failure(s)
```

The ladder is reached with a non-empty `$origin_tag_list` — it fell through to
branch 2 rather than to the empty-listing branches — and the scenario notices
that branch 1 did not fire. The remaining six failures are the three
pre-existing branch-1 scenarios the RED report already named, independent
corroboration that the mutated line is the one under test. Note the mutation run
shows branch 2 firing off the *stub's* listing, which is further evidence the
stub is live.

Restore, verified byte-for-byte:

```
$ git diff --quiet -- toolkit/release.sh && echo "RESTORED: toolkit/release.sh byte-for-byte clean (git diff --quiet exit 0)" || echo "DIRTY"
RESTORED: toolkit/release.sh byte-for-byte clean (git diff --quiet exit 0)
```

### Final state

```
$ bash tests/release-test.sh | tail -5
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===
=== resume hint names the tag already on origin ===

all release scenarios passed
$ git status --porcelain -- toolkit/release.sh tests/release-test.sh
 M tests/release-test.sh
$ bash -n tests/release-test.sh && echo "bash -n ok"
bash -n ok
$ shellcheck -x tests/release-test.sh && echo "shellcheck ok"
shellcheck ok
```

Only `tests/release-test.sh` is modified. Nothing was committed.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| N1, slice 1 acceptance: with a small origin listing the ladder is reached and branch 1 fires | Satisfied | Green run above; the `toolkit/release.sh` mutation run shows the ladder reached with a non-empty `$origin_tag_list` and the scenario red when branch 1 does not fire |
| Slice 1 is a meaningful control for slice 2 | Satisfied after fix | The stub-disabled run above; before the fix this held vacuously |

## Positive Observations

- The RED report is unusually honest about slice 1 being a control and states
  the no-red expectation up front rather than manufacturing a red.
- The stub reuses the file's established `git`-wrapper idiom verbatim — same
  positional match, same `exec "$real_git" "$@"` delegation, same
  `saved_path`/`export PATH` bracket — so a reader who has read the two
  scenarios above it reads this one for free.
- Synthetic `printf` rows rather than real tag creation, per the runbook's cost
  warning; the suite's wall time is unchanged.
- The comment carries the whole slice-1-is-a-control argument, so a future
  reader who finds it green does not read that as a missing red.

## Recommendations

Slice 2 inherits this fixture. It should keep origin's real tag deleted for the
same reason, and its own control should be the size of the post-filter
`$origin_tag_list`, measured in the test rather than assumed from the row count.

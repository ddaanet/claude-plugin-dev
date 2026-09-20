# Test review — Item 1.2, slice 2

**Scope:** `tests/release-test.sh`, the new
`=== resume hint names the tag already on origin at 1MB ===` scenario, its
`$sandbox/origin-tag-rows.sh` generator and post-filter size guard, plus
`plans/2026-09-18-deliverable-review-fixes/reports/item-1-2-s2-red.md`.
**Date:** 2026-09-20 **Mode:** review + fix

## Summary

The red is genuine and for the right reason. Re-run here, the scenario fails on
two assertions (not errors), and the branch it lands in is branch 2 — "origin
has release tags, but none matching v1.2.3" — so the ladder is reached with a
non-empty `$origin_tag_list` and the membership test returned non-zero. That is
N1 exactly. Applying the item's herestring Change in place turned the whole
suite green; `toolkit/release.sh` was restored byte-for-byte. The stub is
load-bearing (origin's real `v1.2.3` is deleted; disabling the stub moves the
output to branch 4), the size guard measures the *post-filter* list against the
≥1 MB bound with no downward "optimisation" from a local grep measurement, and
slice 1's committed scenario is untouched — the diff is pure addition.

Two minor fixes applied to the new scenario: the guard now absorbs grep's
no-match status the way `semver_tags` does, so a fixture that stopped matching
reports 0 bytes through the assertion instead of killing the suite under
`set -euo pipefail`; and the deliberate `$(seq …)` word split now states its
residual bound in the comment.

**Overall assessment:** Ready.

## Mechanical first check

### 1. The red, re-run here (foreground, ~60 s)

```
$ cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
...
=== resume hint names the tag already on origin ===
=== resume hint names the tag already on origin at 1MB ===
FAIL: resume hint names the tag already on origin at 1MB: output did not contain 'origin already has v1.2.3'
  --- output ---
hint: origin has release tags, but none matching v1.2.3.
      run `git fetch --tags`, then run `just release <bump>`.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------
FAIL: resume hint names the tag already on origin at 1MB must not advise a fresh release: output contained 'just release'
  --- output ---
hint: origin has release tags, but none matching v1.2.3.
      run `git fetch --tags`, then run `just release <bump>`.
error: no tag v1.2.3 for plugin.json version 1.2.3
  --------------

2 failure(s)
EXIT=1
```

Two failed assertions on wrong values, no ERROR, and `2 failure(s)` is the whole
run's total — no other scenario broke. Matches the RED report line for line.

### 2. The red is N1 and not something else

The printed hint is branch 2's (`elif [ -n "$origin_tag_list" ]` in
`resume_preflight`), which is reachable only with a non-empty listing: the stub
is live, the ladder is reached, and `grep -qxF -- "$tag"` returned non-zero on a
list whose first line *is* `v1.2.3`. Not an unreachable fixture (that lands in
branch 4 — see the stub-disabled run below), not a crash (exit code 1 and the
`gh` log assertions held).

### 3. Green under the item's Change

Applied in place at the ladder site, nothing else touched:

```diff
-        if printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"; then
+        if grep -qxF -- "$tag" <<<"$origin_tag_list"; then
```

```
=== resume hint names the tag already on origin ===
=== resume hint names the tag already on origin at 1MB ===

all release scenarios passed
EXIT=0
```

Restored from a copy taken before the edit:

```
$ git diff --quiet -- toolkit/release.sh && echo "toolkit/release.sh clean"
toolkit/release.sh clean
```

The tests were never relocated.

## Hunt for vacuous passes and fixture defects

### The size guard measures the post-filter list — verified

`origin_release_tags` ends with
`printf '%s\n' "$listing" | cut -f2 | sed 's|^refs/tags/||' | semver_tags`, and
`semver_tags` is `grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'` with a no-match
absorption. The guard replicates that pipeline verbatim over the same generator
and asserts `>= 1048576`. Measured independently with `/usr/bin/grep` (not the
session's ugrep-wrapping `grep` shell function):

```
$ … | cut -f2 | sed 's|^refs/tags/||' | /usr/bin/grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | wc -c
1088917
```

1088917 ≥ 1048576, and comparable to the runbook's own 1088895 for 100000 tags.
The bound was **not** optimised downward from a local measurement — the fixture
is the runbook's 100000 tags, 1.04x the ≥1 MB bound post-filter and ~6.2 MB raw,
nowhere near a memory or tmpfs concern. A shrink makes the guard assertion fail
with the byte count in its label.

### The stub is load-bearing — verified by disabling it

`new_sandbox`'s real `v1.2.3` is deleted from origin
(`git -C "$plugin" push -q origin :refs/tags/v1.2.3`), as slice 1's review
required. Temporarily changing this scenario's stub guard to
`"ls-remote-DISABLED"` so it delegates everything to the real binary:

```
=== resume hint names the tag already on origin at 1MB ===
FAIL: … : output did not contain 'origin already has v1.2.3'
  --- output ---
hint: no release was started at this version.
      run `just release` instead.
FAIL: … remedy: output did not contain 'git fetch --tags'
FAIL: … must not advise a fresh release: output contained 'just release'

3 failure(s)
```

Branch 4, three failures — a visibly different failure signature from the N1 red
(branch 2, two failures), so a dead stub cannot be mistaken for the defect. Test
file restored from a pre-edit copy (`diff -q` clean, zero `ls-remote-DISABLED`
occurrences).

### Checked and clean (no finding)

- Matching tag first, exactly once; the `seq 4 100003` range starts past it.
  Rows come from one `seq`-backed `printf` cycling its one remaining conversion
  — no real `git tag` calls, no shell loop.
- The generator lives in one file called by both the stub and the guard, so the
  measured list and the served list cannot drift.
- Slice 1's scenario is **not** refactored onto the generator and is not
  modified at all: `git diff -- tests/release-test.sh` is a single purely
  additive hunk after line 1609. Slice 1 still passes and still detects a dead
  stub (its own fixture and stub are byte-identical to the reviewed state).
- `$sandbox` and `$real_git` are interpolated into the heredocs inside double
  quotes, so a path holding a space survives; `\$1`/`\$@` are escaped so the
  stub's own parameters are not expanded at write time.
- The stub's `exit 0` after the generator does not hide a broken generator: an
  empty listing routes to branch 4 and fails three assertions loudly, and the
  guard runs the generator first anyway.
- Citation convention: the comments cite `resume_preflight`,
  `origin_release_tags` and `semver_tags` with quoted fragments
  (`printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"`,
  `cut -f2 | sed 's|^refs/tags/||'`). No `<script>.sh:<line>` anywhere.
- `bash -n` and `shellcheck -x` on `tests/release-test.sh`: both clean.
- RED report: its claims check out — the failure text, the 1088917 measurement,
  "slice 1 untouched", and `toolkit/release.sh` unmodified.

## Issues Found

### Minor Issues

1. **The size guard could kill the suite instead of reporting**
   - Location: `tests/release-test.sh`, `… at 1MB` scenario, the
     `post_filter_size=$(…)` capture.
   - Note: the pipeline ran a bare `grep -E` under the file's
     `set -euo pipefail`. A future fixture that matched nothing would make grep
     exit 1, fail the capture, and abort the suite at that line with no message
     — the opposite of the "loud on a shrink" property the guard's own comment
     claims.
   - **Status**: FIXED — wrapped as `{ grep -E … || [ "$?" -eq 1 ]; }`, the
     idiom `semver_tags` already uses for the same reason, so such a fixture
     reports 0 bytes through the assertion. Comment extended to say so.

2. **Deliberate whitespace split carried no stated bound**
   - Location: same scenario, the generator's
     `printf '…v1.2.%s\n' $(seq 4 100003)`.
   - Note: the unquoted command substitution is the mechanism, not a slip, but
     nothing said so or stated why it is safe.
   - **Status**: FIXED — comment now states the split is by design and safe for
     one reason: `seq` emits nothing but digits and newlines.

## Fixes Applied

- `tests/release-test.sh`, `… at 1MB` scenario — grep no-match absorption in the
  post-filter size guard, plus the comment clause explaining it.
- Same scenario — comment clause stating the residual bound on the `$(seq …)`
  word split.

No change to `toolkit/release.sh` (temporary Change applied and restored,
above). Nothing committed.

## Re-run after the fixes — red still holds, same reason

```
$ bash -n tests/release-test.sh && shellcheck -x tests/release-test.sh
bash -n ok
shellcheck ok
$ bash tests/release-test.sh
...
=== resume hint names the tag already on origin at 1MB ===
FAIL: … : output did not contain 'origin already has v1.2.3'
  --- output ---
hint: origin has release tags, but none matching v1.2.3.
      run `git fetch --tags`, then run `just release <bump>`.
FAIL: … must not advise a fresh release: output contained 'just release'

2 failure(s)
EXIT=1
$ git status --porcelain -- toolkit/ tests/
 M tests/release-test.sh
```

Same two assertions, same branch-2 output, guard assertion still silent
(passing).

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| N1 slice 2: at ≥1 MB post-filter, branch 1 fails to fire today | Satisfied | The red above lands in branch 2 with a non-empty listing |
| The fixture clears the ≥1 MB post-filter bound | Satisfied | Guard passes; 1088917 bytes measured with `/usr/bin/grep` |
| The test goes green under the herestring Change | Satisfied | Full-suite green run above; `release.sh` restored clean |

## Positive Observations

- The guard measures the list the ladder actually sees rather than the row
  count, which is what slice 1's review asked for, and embeds the measured size
  in its label.
- The single-generator-file choice removes the one way a stub and its guard can
  disagree about what was served.
- The comment carries the whole SIGPIPE/pipefail argument and the 5.7x sizing
  factor, so a reader meeting this fixture later does not have to re-derive the
  bound — the exact place a local grep measurement would have led someone wrong.

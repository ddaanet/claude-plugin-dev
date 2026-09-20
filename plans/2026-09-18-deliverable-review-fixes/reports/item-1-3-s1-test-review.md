# Item 1.3 / Slice 1 — test review

**Verdict: Ready.** The RED is genuine: three assertion failures, reproduced
verbatim, produced by `release_preflight`'s drift guard reading `vnext` as the
latest release. The fixture is exactly the shape the slice specifies, no other
scenario is disturbed, and the scenario turns green under the item's Change and
red again once it is reverted. One minor fix applied (an explanatory comment on
the scenario). No UNFIXABLE issues.

**Mode:** review + fix. **Scope:** `tests/self-release-test.sh` (new
`vnext on ancestry` scenario) and `plans/.../item-1-3-s1-red.md`.

## Mechanical first check — reproduced

```
=== vnext on ancestry is not the latest tag ===
FAIL: vnext: exit status: expected '0', got '1'
FAIL: vnext: local tag v0.2.0 missing
FAIL: vnext: no drift refusal: output contained 'does not match latest tag'
  --- output ---
hint: toolkit/VERSION holds the LAST released version. `just release` bumps from there.
      revert any manual VERSION bump and re-run.
error: toolkit/VERSION (0.1.0) does not match latest tag (vnext)
  --------------
...
3 self-release check(s) failed
EXIT=1
```

All three are `assert_eq`/`assert_tag`/`assert_not_contains` value mismatches.
None is a `command not found`, syntax or harness error: every later `=== … ===`
section ran, and the captured `$out` is a normal `die` message. No test PASSED
that should have failed, and no scenario other than the new one reports
anything. The RED report's evidence matches this run line for line.

## Fixture verified directly

A temporary probe inserted in place after `git -C "$repo" tag vnext` (removed
again; the file now carries only the comment fix below):

```
PROBE log:        cb4da35 work: work.md|4c3ec82 init|
PROBE HEAD tags:  vnext
PROBE HEAD~ tags: v0.1.0
PROBE all tags:   dist-v0.1.0 v0.1.0 vnext
PROBE describe:   vnext
PROBE VERSION:    0.1.0 dirty=[]
```

- `new_sandbox` leaves exactly one commit carrying `toolkit/VERSION` at `0.1.0`,
  tagged `v0.1.0`; the scenario adds **one** ordinary commit and tags **that**
  `vnext`. `v0.1.0` sits on `HEAD~`, `vnext` on `HEAD`. Nothing moves `v0.1.0`
  and no commit carries two tags of interest.
- The tree is clean (`dirty=[]`) and the branch is `main`, so
  `common_preflight`'s clean-tree, branch and VERSION-format checks all pass —
  the refusal cannot be one of theirs.
- The refusal is the drift guard and nothing downstream:
  `require_prior_release_published` is only reached past the guard, and the
  `v0.1.0` release is fully published by the fixture (both tags on origin, the
  `gh` stub's release file present), so it would pass anyway.
- `git describe --tags --abbrev=0 --match 'v*'` answers `vnext` — the nearest
  reachable tag of any name — which is precisely the failure mode N2 names.

## Change applied → green, then restored

Applied in place in `scripts/self-release.sh`, replacing the `git describe` line
in `release_preflight` with the capture-then-filter form
(`git tag --list 'v*' --sort=-v:refname` into a local, `sed -n` over the
captured value anchored to `^v[0-9]\+\.[0-9]\+\.[0-9]\+$`, first match taken,
`|| die` on the listing's own status):

```
=== vnext on ancestry is not the latest tag ===
...
self-release.sh: ok
EXIT=0
```

The whole suite passed, so the new scenario goes green under the item's Change
and no existing scenario regresses under it. Restored with
`git checkout -- scripts/self-release.sh`;
`git diff --quiet -- scripts/self-release.sh` exits `0` and
`git status --porcelain` for that path is empty. The tests were never relocated
— both runs used `bash tests/self-release-test.sh` from the repo root.

## Wrong-reason hunt

- **Does `run minor` really have to reach a release?** `assert_eq "$rc" 0` fails
  on every `die` in the script, so a zero status means the run got past the
  bump, the dist split, both pushes and the `gh` stub to the final `note`.
  `assert_tag v0.2.0 local` is not satisfiable another way: nothing in the
  fixture creates `v0.2.0`, and `bump_commit_tag` is the script's only writer of
  it, reachable only in release mode past both preflights. The pair pins the
  release.
- **Is the negative bare?**
  `assert_not_contains "$out" "does not match latest tag"` is paired with two
  positives over the same fixture, so deleting the guard entirely would not make
  the scenario vacuously pass — it would still have to reach a release.
- **Does it detect wrongness, not just absence?** Under the item's mutation
  (`git describe --tags --abbrev=0 --match 'v*'`, i.e. today's code) all three
  assertions fail, as the run above shows. The test reds on the forbidden
  implementation, not merely on missing code.
- **Fixture reachable from the write path?** The scenario drives the real script
  through `run`, against a repo built by the same `new_sandbox` and
  `commit_in_repo` helpers every other scenario uses. Nothing is hand-authored
  into a state the flow cannot produce.
- **Disturbance:** the scenario sits between `=== bump arithmetic ===` and
  `=== an unfinished release refuses a new one ===`, and the next scenario opens
  with its own `new_sandbox`. No helper was modified, so the four fixtures Item
  2.1 will strengthen are untouched and unpre-empted.
- **Whitespace safety:** every expansion in the added lines is quoted
  (`"$repo"`, `"$out"`, `"$rc"`); nothing splits on whitespace.
- **Citations:** the added comment names the enclosing function
  (`release_preflight`) and quotes no `file.sh:line`.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **Scenario carried no explanation of its crux**
   - Location: `tests/self-release-test.sh`, the
     `=== vnext on ancestry is not the latest tag ===` section
   - Note: the file's convention is a short comment wherever the fixture's point
     is not readable off the assertions (the dist-lineage squatter,
     `resume after later work on main`). Here the whole test turns on `vnext`
     sitting on `HEAD` ahead of `v0.1.0` and on what `git describe` answers,
     none of which the three assertions state.
   - **Status**: FIXED

## Fixes Applied

- `tests/self-release-test.sh`, above the scenario's `new_sandbox` — added a
  five-line comment stating the fixture's shape (`v0.1.0` on `HEAD~`, the
  non-release `vnext` on `HEAD`), what must therefore happen (drift guard quiet,
  bump goes through), and why only a listing-and-filtering `release_preflight`
  achieves it. No assertion, helper or other scenario was changed.

Re-run after the fix: identical three failures, still on assertions
(`3 self-release check(s) failed`, `EXIT=1`). `bash -n` and `shellcheck` on the
test file are clean.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| N2 (slice 1): a `vnext` tag on `HEAD` is not read as the latest release, and `run minor` reaches a release | Pinned by the test | Red today on all three assertions; green under the Change (`self-release.sh: ok`) |

## Positive Observations

- The scenario reuses `new_sandbox` and `commit_in_repo` unmodified, so it costs
  the suite nothing in shared-fixture risk.
- `assert_not_contains` on the refusal text pins the *reason* rather than only
  the outcome, so a future change that reaches a release for some other reason
  while the drift guard still misfires would not quietly satisfy it.
- The RED report's diagnosis (describe returning the nearest reachable tag, `v`
  stripped to leave `next`) is accurate and matches the probe.

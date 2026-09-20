# Item 1.3 / Slice 1 — RED report

## Command

```
cd /Users/david/code/claude-plugin-dev && bash tests/self-release-test.sh
```

## Evidence (verbatim)

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
```

Full suite tail:

```
=== resume refusals ===
=== never moves a published tag ===
=== preflight refusals ===
=== an unreadable origin refuses rather than proceeds ===
3 self-release check(s) failed
```

Exit status of the whole test script: `1` (the harness's own failure-count exit,
not a shell error — every subsequent `echo "===...` section in the file still
ran to completion after the three failures above, confirming the failure is on
assertions, not a crash).

All three failures are `assert_eq`/`assert_not_contains` value mismatches — none
is an `ImportError`/`AttributeError`/`command not found` class error, and the
captured `$out` block shows the script ran to a normal `die` exit with a
message, not a crash.

## What was written

Added one new scenario to `tests/self-release-test.sh`, inserted between the
`=== bump arithmetic ===` section and
`=== an unfinished release refuses a new one ===`:

```sh
echo "=== vnext on ancestry is not the latest tag ==="
new_sandbox
commit_in_repo work.md "ordinary work after 0.1.0"
git -C "$repo" tag vnext
run minor
assert_eq "$rc" 0 "vnext: exit status"
assert_tag v0.2.0 local "vnext"
assert_not_contains "$out" "does not match latest tag" "vnext: no drift refusal"
```

Uses `new_sandbox` (leaves `v0.1.0` on the sole commit, `toolkit/VERSION` at
`0.1.0`) plus the existing `commit_in_repo` helper to add one ordinary commit,
then tags that commit `vnext` — matching the slice's fixture description
verbatim: `v0.1.0` sits on `HEAD~`, `vnext` on `HEAD`. No other scenario in the
file was touched; no fixture used by other scenarios (`new_sandbox`,
`commit_in_repo`, `block_push`, etc.) was modified.

## Diagnosis

Against unchanged `scripts/self-release.sh`, `release_preflight` uses
`git describe --tags --abbrev=0 --match 'v*'`, which returns the nearest
reachable tag of any name — here `vnext`, since it sits directly on `HEAD` ahead
of `v0.1.0`. The drift guard then compares `toolkit/VERSION` (`0.1.0`) against
`latest_tag` stripped of its `v` prefix (`next`, since `vnext` starts with `v`),
and refuses with `does not match latest tag (vnext)` as observed. This is
exactly the slice's predicted failure mode.

## Scope confirmation

- `scripts/self-release.sh` — untouched.
- `tests/self-release-test.sh` — only the one new scenario above was added;
  slice 2's scenario, the dist-tag-squatting comment, and all other scenarios
  are unmodified.
- Nothing was committed; the new test sits uncommitted in the working tree.

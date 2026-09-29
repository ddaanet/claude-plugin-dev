# Item 1.1/4 GREEN

Run in session by the orchestrator. No dispatch was needed, because the slice
has nothing to implement. The committed `sync` already excludes `.git`
unanchored and `/dist/plugin/`, so both tests pass against it:
`a nested repo's .git stays out` and `sync never recurses into the copy`.

The evidence is mutation:

- RED's anchored `/.git` reds the nested-repo test.
- The test review's directory-only `.git/` reds it against the gitfile fixture.
- Dropping `/dist/plugin/` together with the ignore-list feed reds the recursion
  test.

The recursion test's residual (the ignore list alone also excludes the copy) is
the runbook's, and the test's comment states it.

`toolkit/dogfood.sh` is unchanged. `bash tests/dogfood-test.sh` prints
`all dogfood scenarios passed`.

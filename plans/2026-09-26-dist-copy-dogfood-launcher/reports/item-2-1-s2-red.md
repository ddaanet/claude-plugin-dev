# Item 2.1 slice 2 RED: an inherited variable is overwritten

Test added to `tests/dogfood-launcher-test.sh`: scenario "an inherited variable
is overwritten". It runs
`CLAUDE_CODE_PLUGIN_DIRS=/elsewhere/dist/plugin run_claude`, so the export is
scoped to that one call, and asserts the stub recorded exactly
`<consumer>/dist/plugin`.

Slice 1's shim already overwrites the variable, so the test passes against the
current SUT (expected). Discrimination is proved by mutation.

## Mutation proof

Test: `an inherited variable is overwritten`.

- Mutation in `toolkit/bin/claude` line 18: replaced
  `export CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin"` with
  `export CLAUDE_CODE_PLUGIN_DIRS="${CLAUDE_CODE_PLUGIN_DIRS:+$CLAUDE_CODE_PLUGIN_DIRS:}$root/dist/plugin"`.
- Suite output, red on the test's own assertion:
  `FAIL: an inherited variable is overwritten: expected '<sandbox>/my consumer/dist/plugin', got '/elsewhere/dist/plugin:<sandbox>/my consumer/dist/plugin'`
  then `1 failure(s)`.
- Restore: the same replacement with the two strings swapped.
  `grep -c 'PLUGIN_DIRS:+' toolkit/bin/claude` gave 0 hits;
  `git diff --quiet toolkit/bin/claude` succeeded (SUT identical to HEAD).
- Suite after restore: `all dogfood launcher scenarios passed`.

`bash -n` and `shellcheck` are clean on the suite. No commit.

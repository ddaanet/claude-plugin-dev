# Item 1.1/1 RED — the shim syncs only outside a dogfood session of its own repo

File: tests/dogfood-launcher-test.sh (toolkit/bin/claude untouched;
`git status toolkit` clean).

## Scenarios

1. "the shim syncs before exec" (existing, extended):
   `unset CLAUDE_CODE_PLUGIN_DIRS` explicit; added assertion that the exec'd
   claude sees the variable = copy.
2. "a variable equal to this copy skips the sync" (new): runs with
   `CLAUDE_CODE_PLUGIN_DIRS=$consumer/dist/plugin`; asserts rc 0, no `dist/`,
   stub saw copy `absent`, variable still = copy, stub pid = launch pid.
3. "an inherited variable is overwritten" (existing, extended): variable
   `/elsewhere/dist/plugin`; added assertions that the copy is present at exec
   and the manifest exists (sync ran), beside the existing override assertion.

## RED output (current shim, assertion failures only)

- Scenario 2 (reds, as required):
  - `FAIL: a variable equal to this copy skips the sync: no copy made: '.../my consumer/dist' exists`
  - `FAIL: a variable equal to this copy skips the sync: no copy as the next claude started: expected 'absent', got 'present'`
  - the exit-code, variable and pid assertions pass on the current shim (they
    hold under both behaviours).
- Scenarios 1 and 3: pass on the current shim (behaviour already present).

## Mutation proof (scenarios 1 and 3)

Mutation (one run per named scenario, identical string pair, in
toolkit/bin/claude): `    bash "$root/plugin-dev/dogfood.sh" sync` ->
`    : "$root/plugin-dev/dogfood.sh" sync` (shim never syncs). Restored by the
inverse exact replacement; after each, grep for the mutated text returned 0 hits
and the line showed original at line 19.

- Scenario 1 reds:
  `FAIL: the shim syncs before exec: the copy existed as the next claude started: expected 'present', got 'absent'`
  and `...: '.../dist/plugin/.claude-plugin/plugin.json' is not a regular file`.
- Scenario 3 reds:
  `FAIL: an inherited variable naming another path still syncs: expected 'present', got 'absent'`
  and `...: ...plugin.json' is not a regular file`.
- (Same mutation also reds the pre-existing failed-sync and 127 scenarios, 9
  failures total.)

Restore proven: after the final restore the suite shows only scenario 2's two
failures (the designed red), nothing else.

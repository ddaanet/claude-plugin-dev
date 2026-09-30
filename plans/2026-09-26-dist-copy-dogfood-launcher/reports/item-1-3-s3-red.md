# Item 1.3/3 RED: mismatches warn on both channels

Added three scenarios and one helper (`assert_session_warns`) to
tests/dogfood-test.sh, after the 1.3/2 scenarios and before
`unknown subcommand is usage`. `shellcheck` clean. No SUT change survives:
`git diff --quiet toolkit/dogfood.sh` is clean.

## Per-test output

The committed `session_start` already implements whole-entry matching, so all
three pass against it (suite: `all dogfood scenarios passed`). Each asserts exit
0, empty stderr, `.systemMessage` leading with ESC `[0m` and naming
`<root>/dist/plugin`, `hookEventName = "SessionStart"`, and `additionalContext`
naming `<root>/dist/plugin`.

- `session-start warns on another repo's copy`: entry `<other>/dist/plugin`, a
  second consumer fixture built and synced first, its copy asserted to exist.
- `session-start warns on /x<root>/dist/plugin`: a non-existent entry.
- `session-start warns on <root>/dist/plugin/skills`: the synced copy's `skills`
  directory, asserted to exist.

## Mutation proof

Each replaced the one-line anchor `[[ "$entry" == "$copy" ]] && exit 0` (occurs
once) and was restored by the inverse replacement; after each, a grep for the
mutant text gave no hit and `git diff --quiet toolkit/dogfood.sh` was clean. The
suite is green after the last restore.

- Test `session-start warns on another repo's copy`: replacement `== "$copy"` to
  `== */dist/plugin`. Red on stdout `''` for the systemMessage, hookEventName
  and additionalContext assertions of that test (the `/x` test reds too, as its
  entry also ends in `/dist/plugin`, and so does the 1.3/2 relative-entry test).
- Test `session-start warns on /x<root>/dist/plugin`: replacement `== "$copy"`
  to `== *"$copy"*` (substring). Red on the same three assertions of that test
  (the skills test and the 1.3/2 `plugin<LF>` test red too).
- Test `session-start warns on <root>/dist/plugin/skills`: replacement
  `== "$copy"` to `== "$copy"*` (prefix). Red on the same three assertions of
  that test alone among the 1.3/3 tests (the 1.3/2 `plugin<LF>` test reds too).

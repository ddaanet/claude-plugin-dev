# Item 1.2 slice 6 RED: leaf symlink

Added to tests/dogfood-test.sh after the last pre-tool scenario, plus a helper
`assert_denied_source` (exit 0, empty stderr, hookEventName, permissionDecision,
additionalContext naming `<root>/skills/demo/SKILL.md`). SUT untouched.
`bash -n` and `shellcheck` clean. Suite run in the foreground: 7 failures, all
in the three new tests; every pre-existing test passes.

## Per-test failures (unchanged SUT)

- pre-tool follows a symlink at the leaf into the copy (3 failures):
  - `hookEventName: .hookSpecificOutput.hookEventName == "PreToolUse" is not true over stdout ''`
  - `permissionDecision: ... == "deny" is not true over stdout ''`
  - `additionalContext names the source path: ... is not true over stdout ''`
- pre-tool follows a chain of leaf symlinks into the copy (same 3 failures,
  stdout '' as the guard allows it).
- pre-tool allows a leaf symlink out of the copy (1 failure):
  `prints nothing on stdout: expected '', got '{"hookSpecificOutput":{..."permissionDecision":"deny"...`
  (the unresolved leaf is spelled in the copy, so the current SUT denies it with
  source `<root>/skills/z.md`). Exit code and stderr assertions pass.

No mutation proof needed: every new test reds on its own assertion. Residual
(not tested, per slice): a dangling leaf link stays unfollowed.

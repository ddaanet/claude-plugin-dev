# Item 1.2/4 RED: physical spelling

Added two tests to tests/dogfood-test.sh, after the
`pre-tool allows a path outside the copy` block. `shellcheck` clean. No SUT
change survives (see the mutation proof).

## Per-test output

- `pre-tool denies a copy path through a symlinked repo`: red on its own
  assertions against the committed SUT (payload
  `$sandbox/link/dist/plugin/new/file.md`, allowed today, empty stdout):
  - `FAIL: ...: permissionDecision: .hookSpecificOutput.permissionDecision == "deny" is not true over stdout ''`
  - `FAIL: ...: additionalContext names the physical source path: ... is not true over stdout ''`
  - Exit code and stderr assertions pass (exit 0, empty stderr).
- `pre-tool invoked through the symlink denies a physical path`: passes against
  the committed SUT (`root_dir` already resolves with `pwd -P`). It runs
  `assert_denied`, which checks parsed fields, so an allow (empty stdout) fails
  it; proven below.

## Mutation proof

Test: `pre-tool invoked through the symlink denies a physical path`. Replacement
in toolkit/dogfood.sh (one contiguous two-line string, occurring once):
`pwd -P)" &&` / `(cd "$here/.." && pwd -P)` became `pwd)" &&` /
`(cd "$here/.." && pwd)`. Both `pwd -P` had to go: the second alone would still
canonicalise.

Result: root resolved logically to `$sandbox/link`, the physical payload was
allowed, and 7 assertions in that test failed on empty stdout, e.g.
`FAIL: pre-tool invoked through the symlink denies a physical path: permissionDecision: .hookSpecificOutput.permissionDecision == "deny" is not true over stdout ''`
(9 failures in total with the other test's 2).

Restored with the inverse replacement. `git diff --quiet toolkit/dogfood.sh`
clean; grep for the mutated text (`pwd)`) finds no hit; suite afterwards shows
only the 2 expected failures of the first test.

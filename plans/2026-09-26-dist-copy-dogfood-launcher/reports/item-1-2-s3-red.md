# Item 1.2/3 RED: paths outside the copy

Added `pre-tool allows a path outside the copy` to tests/dogfood-test.sh (a
labelled loop over three paths; each asserts exit 0, empty stdout, empty
stderr). The outside-repo path is `$sandbox/elsewhere/dist/plugin/x`, so it
contains `/dist/plugin/` and tests the anchoring. `bash -n` and `shellcheck`
clean. Suite: 3 new tests pass against the committed SUT (expected, no genuine
red for this slice: the committed prefix is already correct).

## Mutation proof

Exact replacements in toolkit/dogfood.sh, each restored by the swapped
replacement; final `git diff --quiet toolkit/dogfood.sh` clean, suite green.

- M1, drop the trailing slash (`"$root/$copy"*`):
  `FAIL: pre-tool allows a prefix-sharing sibling prints nothing on stdout: expected '', got '{"hookSpecificOutput"...deny...dist/plugin-old/x...'`
  (1 failure, only that test).
- M2, widen copy to `dist`:
  `FAIL: pre-tool allows a sibling of the copy prints nothing on stdout` and
  `... a prefix-sharing sibling ...` (dist/other and dist/plugin-old/x denied).
  The existing deny tests also red on their message assertions.
- M3, unanchored (`*"/$copy/"*`):
  `FAIL: pre-tool allows a path outside the repo prints nothing on stdout: expected '', got '{...deny...elsewhere/dist/plugin/x...'`
  (1 failure, only that test).

No mutation reds "a path outside the repo" except M3, and none reds "a sibling
of the copy" except M2, as expected.

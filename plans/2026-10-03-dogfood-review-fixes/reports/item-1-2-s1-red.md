# Item 1.2/1 RED: pre-tool never exits 2 on a jq failure

File: tests/dogfood-pre-tool-test.sh (toolkit/dogfood.sh untouched; SUT exists,
no stub needed). Chosen status: 1.

## Tests

1. "pre-tool fails loudly on a payload jq cannot read" — the exit-code check
   tightened from `!= 0` to exactly `1`. Output:
   `FAIL: pre-tool fails loudly on a payload jq cannot read exit code: expected '1', got '5'`
   (jq 1.7 parse-error status). The stdout-empty and stderr `jq: ` assertions
   pass.
2. New "pre-tool maps a jq exit of 2 to a non-blocking status" — a stub `jq` in
   `$sandbox/stub bin/` (space in the name) printing `jq: stub parse error` on
   stderr and exiting 2, put first on PATH for the run; the scenario first
   asserts `command -v jq` finds the stub (it does). Output:
   `FAIL: pre-tool maps a jq exit of 2 to a non-blocking status exit code: expected '1', got '2'`
   Stdout-empty and stderr-diagnostic assertions pass.

Both fail on the exit-code assertion, not on a missing symbol. Suite: 2
failures, all else green. shellcheck on the test file: clean.

## Mutation proof

None needed: no test passed vacuously.

## Addendum (test review)

A third test, "pre-tool maps a jq failure building the deny to a non-blocking
status", was added at test review: a GREEN mapping only the payload read passed
the two above. Its output against the unchanged SUT:
`FAIL: ... exit code: expected '1', got '2'`. Suite: 3 failures, all else green.
See `item-1-2-s1-test-review.md`.

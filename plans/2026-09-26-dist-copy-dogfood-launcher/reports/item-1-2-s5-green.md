# Item 1.2/5 GREEN

Run in session by the orchestrator: the implementation is one line. `pre_tool`
now opens with `command -v jq >/dev/null || exit 0`, ahead of `root_dir`, and
the comment above it says why the guard stands down in silence and where a
missing jq is reported instead (the `session-start` warning, Item 1.3/4).

The test review showed that a GREEN discarding jq's stderr
(`jq … 2>/dev/null && printf x)" || exit 0`) passes the suite as well, and that
it would also silence the documented failure on a payload jq cannot read. One
scenario was added to exclude it:

- `pre-tool fails loudly on a payload jq cannot read`: jq on PATH, stdin
  `not json` — exit non-zero, stdout empty, stderr contains `jq: `. Green
  against the guard.

## Mutation proof

Mutation: the `jq -j` capture in `pre_tool` became
`jq -j … 2>/dev/null && printf x)" || exit 0`. The suite reported 2 failures,
both from the new test:

- `FAIL: pre-tool fails loudly on a payload jq cannot read: exit code was 0`
- `FAIL: pre-tool fails loudly on a payload jq cannot read shows jq's error: output did not contain 'jq: '`

Restored by the inverse replacement. `grep -c '2>/dev/null && printf x'` finds 0
hits, and the suite prints `all dogfood scenarios passed`.

## Results

- `bash tests/dogfood-test.sh`: `all dogfood scenarios passed`.
- `shellcheck toolkit/dogfood.sh tests/dogfood-test.sh`: clean.

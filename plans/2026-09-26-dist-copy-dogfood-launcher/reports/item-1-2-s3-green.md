# Item 1.2/3 GREEN

Run in session by the orchestrator. No dispatch was needed, because the slice
has nothing to implement. 1.2/1's `pre_tool` already matches the quoted,
anchored prefix `"$root/$copy/"*`, so three allow tests pass against it: outside
the repo, a sibling of the copy, and a prefix-sharing sibling.

The evidence is mutation:

- RED's trailing-slash drop, the widening to `dist`, and the unanchored match
  each red their own test.
- The test review's own mutations red each test too. One of them takes the root
  from `CLAUDE_PROJECT_DIR`.

The details are in `item-1-2-s3-red.md` and `item-1-2-s3-test-review.md`.

`toolkit/dogfood.sh` is unchanged. `bash tests/dogfood-test.sh` prints
`all dogfood scenarios passed`.

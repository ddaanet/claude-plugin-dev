# Item 1.3/3 GREEN

Run in session by the orchestrator. No dispatch was needed, because the slice
has nothing to implement: 1.3/2's `session_start` already compares each entry
whole, so the three mismatch tests pass against it — another repo's real copy,
the non-existent `/x<root>/dist/plugin`, and the longer real
`<root>/dist/plugin/skills`.

The evidence is mutation:

- RED's suffix (`*/dist/plugin`), substring and prefix matchers each red their
  own test.
- The test review's own mutations red each test too: a structural "is a copy"
  check, a `*"$copy"` suffix, and "anything under the root".

The details are in `item-1-3-s3-red.md` and `item-1-3-s3-test-review.md`.

`toolkit/dogfood.sh` is unchanged. `bash tests/dogfood-test.sh` prints
`all dogfood scenarios passed`.

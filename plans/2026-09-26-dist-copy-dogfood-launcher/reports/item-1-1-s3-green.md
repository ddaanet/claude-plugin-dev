# Item 1.1/3 GREEN

Run in session by the orchestrator, with no dispatch, because there is nothing
to implement. The committed `sync` is NUL-delimited from end to end, so
`names with spaces survive` passes against it. The test review extended the
scenario to cover leading-space and newline names.

The evidence is two mutations, not a red:

- RED's `read -d ' '` reds the ignored-spaced-path absences.
- The test review's M1, an unquoted `printf` argument, reds them too, along with
  each added assertion.

The details are in `item-1-1-s3-red.md` and `item-1-1-s3-test-review.md`.

`toolkit/dogfood.sh` is unchanged. `bash tests/dogfood-test.sh` prints
`all dogfood scenarios passed`.

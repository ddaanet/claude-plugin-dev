# Item 1.1/7 GREEN

Run in session by the orchestrator. No dispatch was needed, because the slice
has nothing to implement. The committed `sync` runs rsync as a plain statement
under `set -e`, with stderr not redirected, so
`an rsync failure keeps its status and stderr` passes against it.

The evidence is mutation. RED's `|| exit 1`, `2>/dev/null` and the re-echoed
stderr each red their own assertion. The test review's `|| true`, `2>&1`, the
inserted probe call and `command -p rsync` do too. The details are in
`item-1-1-s7-red.md` and `item-1-1-s7-test-review.md`.

`toolkit/dogfood.sh` is unchanged. `bash tests/dogfood-test.sh` prints
`all dogfood scenarios passed`.

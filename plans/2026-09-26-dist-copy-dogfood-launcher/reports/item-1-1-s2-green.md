# Item 1.1/2 GREEN

Run in session by the orchestrator. No dispatch was needed, because the slice
has nothing to implement.

1.1/1's GREEN already implements decision 2's rsync with `--delete` and
`--delete-excluded`. All three deletion tests pass against it:

- `a committed deletion propagates`;
- `a tracked file deleted in the worktree does not fail sync`;
- `a file that becomes ignored leaves the copy`, added at test review.

Their evidence is mutation, not a red:

- RED's naive `--files-from` sync reds the first two.
- The test review's m1–m3 red the first two again, independently.
- m4 (dropping `--delete-excluded`) reds the third.

The details are in `item-1-1-s2-red.md` and `item-1-1-s2-test-review.md`.

`toolkit/dogfood.sh` is unchanged in this slice. `bash tests/dogfood-test.sh`
prints `all dogfood scenarios passed`. `just precommit` runs as the pre-commit
hook on the slice commit.

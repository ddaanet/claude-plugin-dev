# Item 1.1/2 RED report

Added to `tests/dogfood-test.sh` (before the usage test), reusing
`make_consumer`, `commit_all`, `run_dogfood`, `assert_*`:

- `a committed deletion propagates`: tracked `skills/demo/extra.md`; first sync
  asserts it is copied; `git rm` + commit; second sync exits 0, copy lacks it,
  sibling `SKILL.md` stays.
- `a tracked file deleted in the worktree does not fail sync`: same file; first
  sync copies it; `rm` uncommitted (asserts still tracked); second sync exits 0,
  empty stderr, copy lacks it, sibling stays.

`bash -n` and `shellcheck` on the suite: clean.

## Against the committed GREEN (rsync --delete sync)

Both pass; suite prints `all dogfood scenarios passed`.

## Mutation proof

Mutation (one exact-string replacement in `toolkit/dogfood.sh`, applied via
/tmp/claude/dogfood-build/mutate.py): the excludes-file build plus
`rsync -a --delete --delete-excluded --from0 --exclude-from=-` replaced by
`mkdir -p "$root/dist/plugin"` and
`git -C "$root" ls-files -z | rsync -a --from0 --files-from=- "$root/" "$root/dist/plugin/"`.
Suite then ran red, the only failures:

- `a committed deletion propagates` reds on its own assertion:
  `FAIL: a committed deletion propagates: '.../my consumer/dist/plugin/skills/demo/extra.md' exists`
  (the first-sync presence and exit-code assertions passed).
- `a tracked file deleted in the worktree does not fail sync` reds on its own
  assertions:
  - `exit code: expected '0', got '23'`
  - stderr:
    `rsync: [sender] link_stat ".../skills/demo/extra.md" failed: No such file or directory (2)`,
    code 23
  - `the copy lacks it: '.../extra.md' exists`

4 failures total, none from other tests. Both tests were reded by the same
single mutation in one run, not one run per test.

Restore: the same script with the two strings swapped.
`git diff --quiet toolkit/dogfood.sh` passes (byte-identical);
`grep -c -- '--files-from' toolkit/dogfood.sh` prints 0; suite green again.

Only `tests/dogfood-test.sh` is modified. Nothing committed.

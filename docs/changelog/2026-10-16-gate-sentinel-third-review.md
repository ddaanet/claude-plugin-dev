# 2026-10-16 — Gate sentinels: a third review, before release

The review of the second round's commit
([record](2026-10-16-gate-sentinel-review-fixes.md)) found one regression the
round introduced, one locale dependency, and three documentation errors.

- **A symlink lost its target's execute bit, and its target path was never
  hashed.** The second round recorded `l` for a link in place of the `x` or `-`
  of the file it points at, so `chmod -x` on a link's target went unseen. Nor
  did repointing a link move the hash when the new target held the same content,
  and a directory or dangling link has no content to compare. The manifest line
  now carries the output of `readlink` beside the mode, and the `-f` and `-x`
  tests follow the target as they did before the `l` mode.
- **The listing sorted under the caller's locale.** `sort -zu` orders, and
  decides which lines are equal, by the locale's collation. It runs under
  `LC_ALL=C` now. No test pins it: nothing in the fixtures produces two names a
  locale would call equal.
- **An exclude-only list was documented as subtracting from the whole
  repository.** Git resolves a pathspec against the directory the recipe runs
  in, so from `sub/` the list `':!docs'` covers the files below `sub/` only. The
  manual and the design node say so, and name `:/` and `:(top)` for the whole
  repository. The code is unchanged.
- **`run-bats.sh` does not support the options that change the output format.**
  `--formatter`, `-F`, `--count` and `--version` print no TAP, and the zero-test
  check from the second round turns them into a failure. The runner reads TAP,
  so the usage line, the manual and the migration note say that rather than that
  it takes the arguments `bats` takes.
- **The design node's coverage-rule sentence followed the wrong paragraph.** The
  memory it cites is about the declared inputs, and the second round's insertion
  had left it after the paragraph about `gate_cwd`. It sits after the rule
  again, and a list continuation that was neither indented nor reflowed is
  fixed.

Left as they were, deliberately: a bats run in which every test is skipped
counts as a pass, an empty `gate_builtins` array is not guarded against, and a
git failure on a pathspec is reported as "matches no file" beside git's own
message.

The symlink fix was written as failing assertions first, in
`tests/gates-inputs-test.sh`: a link's target losing its execute bit, a file
link repointed to an identical file, and a directory link repointed. Six
assertions failed before the change.

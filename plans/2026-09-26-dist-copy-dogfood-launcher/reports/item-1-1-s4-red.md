# Item 1.1/4 RED report

Added to tests/dogfood-test.sh (now 330 lines): `a nested repo's .git stays out`
and `sync never recurses into the copy`. Gitlink built with
`git update-index --add --cacheinfo 160000,<sha>,memory` after a real nested
repo commit (`git add memory` prints the embedded-repo hint block on
stdout/stderr of every run); the fixture asserts mode 160000. `bash -n` and
`shellcheck` clean.

## Against the committed SUT

Both tests pass (expected: slice 4 needs no new SUT behaviour); suite green.

## Mutation proof

Restored each time by applying the swapped replacement;
`git diff --quiet toolkit/dogfood.sh` true and suite green afterwards.

- Nested `.git`: `'.git'` -> `'/.git'` in the hard-exclude line. Red, one
  failure: `a nested repo's .git stays out: .../dist/plugin/memory/.git exists`.
  No other test fails, so the test is the sole detector.
- Recursion, dropping only `/dist/plugin/` from the hard excludes: suite stays
  green (the residual in the test's comment; the ignore list covers the copy).
- Recursion, dropping `/dist/plugin/` AND the ignore-list feed (loop body
  `printf '/%s\0' "$entry"` -> `: "$entry"`): red on
  `sync never recurses into the copy: .../dist/plugin/dist/plugin exists`. Other
  tests also fail under this combined mutation (ignored-file, deletion, spaces),
  so the recursion test is redded only together with the ignore-list mutation,
  and is not the sole detector there. A fixture variant with `/dist/plugin/`
  un-ignored would isolate it, but that contradicts slice 6's precondition, so
  none was added.

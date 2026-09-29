# Item 1.1/4 test review

Verdict: one wrong-reason gap found and fixed in the fixture. Both tests are now
evidence, and the suite is green against the committed SUT. `bash -n` and
`shellcheck` are clean. `tests/dogfood-test.sh` is 338 lines.

## Wrong-reason hunting

- **Gitlink fixture shape (fixed).** The RED fixture ran `git init` inside
  `memory/`, which gives it a `.git` *directory*. A real consumer mount has a
  `.git` *gitfile* instead: this repo's `memory/.git` is
  `gitdir: ../.git/modules/gitlore-memory`, and `memory/ddaanet/.git` is a
  gitfile too. With the exclude mutated to directory-only (`'.git'` ->
  `'.git/'`), the RED version of the suite stayed **green**, although that
  mutation would copy every real consumer's `memory/.git`. The run is in
  `/tmp/claude/dogfood-build/mut-gitslash-before.txt`.
- **Fix.** `memory/` is now built with
  `git init --separate-git-dir "$consumer/.git/modules/memory"`, which gives the
  real gitfile shape, still recorded as a 160000 gitlink. A new fixture
  assertion checks that `memory/.git` is a regular file. A second nested repo,
  `memory/tier/`, is a plain `git init` (the `.git` directory shape) at depth 2,
  like the `memory/ddaanet` tier. For both `memory` and `memory/tier`, the test
  asserts that `fact.md` is copied and `.git` is absent. The comment names both
  shapes and what each pairing guards against.
- **`memory/fact.md` presence:** asserted, both before and after the fix.
- **Recursion residual:** the comment states it as the runbook requires:
  `/dist/plugin/` is git-ignored, so the ignore list also excludes the copy, and
  dropping the hard exclude survives. I also checked whether two syncs leave an
  empty `dist/` inside the copy. They do not: git collapses the ignored `dist/`,
  and `find dist -name dist` returns only the top-level `dist`.

## Mutation proof (different from the RED report's)

Each mutation was an in-place edit of `toolkit/dogfood.sh`, restored by the
inverse exact-string edit.

| Mutation | Result |
|---|---|
| `'.git'` -> `'.git/'` (fixed suite) | 1 failure: `a nested repo's .git stays out: memory: '…/my consumer/dist/plugin/memory/.git' exists` |
| `'.git'` -> `'/.git' '/*/.git'` | 1 failure: `a nested repo's .git stays out: memory/tier: '…/dist/plugin/memory/tier/.git' exists` |
| `--exclude-from=-` -> `--include-from=-` | red on `sync never recurses into the copy: '…/dist/plugin/dist/plugin' exists`, 13 FAIL lines in total |

The recursion test is not the sole detector under the third mutation. That is
expected: because of the accepted residual, no single mutation that leaves the
ignore list intact can reach it.

After restoring: `git diff --quiet toolkit/dogfood.sh` passed, and
`bash tests/dogfood-test.sh` ended with `all dogfood scenarios passed` (rc 0).
The logs are in `/tmp/claude/dogfood-build/`.

## Findings for the lead

None outside this slice. Nothing was committed or staged.

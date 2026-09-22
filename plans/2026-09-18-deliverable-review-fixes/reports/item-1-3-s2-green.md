# Item 1.3 / slice 2 — GREEN report

**Written retroactively on 2026-09-22**, after the fact, to close the gap
`reports/tdd-audit.md` records as Minor 3: this slice committed without a GREEN
report, so its suite result rested on inference. Everything below is measured at
the slice commit on 2026-09-22, not recalled from the dispatch.

Mode: GREEN. Test-only slice — the second assertion group over the production
change Item 1.3 slice 1 (`07b7ae9`) landed in `scripts/self-release.sh`. Per
`item-1-3-s2-red.md` its red came from a named mutation (revert to
`git describe --tags --abbrev=0`), restored before the commit; there was no
implementation step here and nothing to sequence.

Commit: `6a77beab423c2f00b1df0d3e89bfd05040f44132`, subject
`✅ Item 1.3/2 — release tag off ancestry still triggers drift guard`.

## `git show --stat 6a77bea`

```
commit 6a77beab423c2f00b1df0d3e89bfd05040f44132
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 19:05:38 2026 +0200

    ✅ Item 1.3/2 — release tag off ancestry still triggers drift guard

 tests/self-release-test.sh | 27 +++++++++++++++++++++++++++
 1 file changed, 27 insertions(+)
```

One file, additions only. No production file — in particular no
`scripts/self-release.sh` hunk, so the mutation the RED report names is
confirmed absent from the commit. No `memory` gitlink, no `.claude/` path. The
scenario the diff adds is
`=== release tag off ancestry still triggers drift guard ===`.

## Suite result — measured at the commit, not inferred

The tree was exported with `git archive 6a77bea | tar -x -C "$TMPDIR/6a77bea"`
and the suite the commit touches run from inside that export:

```
$ cd "$TMPDIR/6a77bea" && bash tests/self-release-test.sh
...
=== never moves a published tag ===
=== preflight refusals ===
=== an unreadable origin refuses rather than proceeds ===
self-release.sh: ok
```

Exit code `0`. 13 `=== … ===` scenario lines, zero `FAIL` lines, and this
slice's own scenario printed exactly once. The suite runs from an exported tree
without the real `.git`: `tests/self-release-test.sh` builds its fixtures as
fresh repos under a temp dir and reaches `scripts/self-release.sh` through
`repo_root`, which it derives from `$0`, so nothing in it reads this repo's
history.

## What this report does not carry

The original dispatch's own `just precommit` run is not recoverable — it was not
written down, which is the gap being closed. What is established here is
narrower and measured: the suite the commit touches is green at that commit, and
the commit carries nothing beyond the test file. The pre-commit hook runs
`just precommit` unconditionally, so the gate did run; this report does not
quote its output, because reconstructing a run is not the same as having
recorded one.

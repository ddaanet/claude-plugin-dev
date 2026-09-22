# Item 1.1 / slice 2 — GREEN report

**Written retroactively on 2026-09-22**, after the fact, to close the gap
`reports/tdd-audit.md` records as Minor 3: this slice committed without a GREEN
report, so its suite result rested on inference. Everything below is measured at
the slice commit on 2026-09-22, not recalled from the dispatch.

Mode: GREEN. Test-only slice — the production change this slice's assertions
cover landed in Item 1.1 slice 1 (`b68cede`), so there was no implementation
step here and nothing to sequence.

Commit: `45891f894cf7387502dc3e72d9ec6dff08e13980`, subject
`✅ Item 1.1/2 — pipefail-stripped release_tags failure publishes nothing`.

## `git show --stat 45891f8`

```
commit 45891f894cf7387502dc3e72d9ec6dff08e13980
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 17:59:46 2026 +0200

    ✅ Item 1.1/2 — pipefail-stripped release_tags failure publishes nothing

 tests/release-test.sh | 59 +++++++++++++++++++++++++++++++++++++++++++++++++++
 1 file changed, 59 insertions(+)
```

One file, additions only. No production file, no `memory` gitlink, no `.claude/`
path. The scenario the diff adds is
`=== pipefail-stripped release_tags failure publishes nothing ===`.

## Suite result — measured at the commit, not inferred

The tree was exported with `git archive 45891f8 | tar -x -C "$TMPDIR/45891f8"`
and the suite the commit touches run from inside that export:

```
$ cd "$TMPDIR/45891f8" && bash tests/release-test.sh
...
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===

all release scenarios passed
```

Exit code `0`. 62 `=== … ===` scenario lines, zero `FAIL` lines, and this
slice's own scenario printed exactly once. The suite runs from an exported tree
without the real `.git`: `tests/release-test.sh` builds its fixtures as fresh
repos under a temp dir and reaches `toolkit/release.sh` through `repo_root`,
which it derives from `$0`, so nothing in it reads this repo's history.

## What this report does not carry

The original dispatch's own `just precommit` run is not recoverable — it was not
written down, which is the gap being closed. What is established here is
narrower and measured: the suite the commit touches is green at that commit, and
the commit carries nothing beyond the test file. The pre-commit hook runs
`just precommit` unconditionally, so the gate did run; this report does not
quote its output, because reconstructing a run is not the same as having
recorded one.

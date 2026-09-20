# Item 1.2 / slice 2 — GREEN report

Mode: GREEN. Final `bash tests/release-test.sh` closing line:

```
all release scenarios passed
```

`just precommit`: green (full foreground run, ending `ok`) — ran once
standalone before committing, then again automatically as the repo's
pre-commit hook during `git commit`; both green.

Commit hash: `a69c97f8ae83f6260b5bf2c7411554b88a9b955a`
(subject rewritten by the commit-msg hook: `🐛 Item 1.2/2 — resume hint
membership test drops its pipe`).

## Change applied

In `resume_preflight`'s hint ladder (`toolkit/release.sh`), replaced:

```sh
if printf '%s\n' "$origin_tag_list" | grep -qxF -- "$tag"; then
```

with:

```sh
if grep -qxF -- "$tag" <<<"$origin_tag_list"; then
```

and added a comment above it naming the mechanism (no EPIPE, so no
`pipefail` dependency) and the in-repo precedent, `toolkit/version-guard.sh`'s
tag filter (`grep -E '…' <<<"$listing"`). Only this one site changed; no
other line in `toolkit/release.sh` was touched.

## Order tests were made to pass

Only one test was red at dispatch start (two assertions within the same
scenario, per the RED report): `resume hint names the tag already on
origin at 1MB`. A single minimal edit — the herestring swap — made both
of its discriminating assertions pass simultaneously; there was no
second failing test to sequence against. Ran the full
`tests/release-test.sh` suite after the edit to confirm both assertions
now hold and nothing else regressed.

## Full suite run (excerpt, tail)

```
=== the origin probes fail closed with pipefail stripped ===
=== pipefail-stripped release_tags failure refuses ===
=== pipefail-stripped release_tags failure publishes nothing ===
=== resume hint names the tag already on origin ===
=== resume hint names the tag already on origin at 1MB ===

all release scenarios passed

real	0m59.054s
```

All 34 `release-test.sh` scenarios passed, including slice 1's committed
scenario and Item 1.1's `pipefail`-stripped scenarios — no regression.

## `just precommit` result

Full precommit ran clean: `rumdl` doc lint (pre-existing MD013 warnings
in unrelated report files only, none introduced by this change),
`shellcheck` on all toolkit/scripts scripts, `bash -n` on all test
files, `just _import-check`, then every suite —
`version-guard-test.sh`, `check-version-test.sh`, `release-test.sh`,
`self-release-test.sh`, `update-plugin-dev-test.sh`,
`dist-tree-test.sh`, `docs-test.sh`, `doc-sync-test.sh` — all green,
closing `ok`.

No new warnings were introduced by this dispatch's diff; the pre-existing
MD013 line-length notices belong to prior reports under `plans/`, out of
scope.

## `git show --stat HEAD`

```
commit a69c97f8ae83f6260b5bf2c7411554b88a9b955a
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 18:40:01 2026 +0200

    🐛 Item 1.2/2 — resume hint membership test drops its pipe

 tests/release-test.sh | 75 +++++++++++++++++++++++++++++++++++++++++++++++++++
 toolkit/release.sh    |  7 ++++-
 2 files changed, 81 insertions(+), 1 deletion(-)
```

Exactly the two named files rode along — no `memory` gitlink and no
`.claude/handoff-*.md` in this commit. Those files (`handoff-task.md`,
`handoff-todo.md`, the `memory` submodule pointer) remained staged/dirty
in the index exactly as they were before this dispatch, untouched by
`git commit -- toolkit/release.sh tests/release-test.sh`.

## Scope confirmation

- IN, touched: `toolkit/release.sh` (`resume_preflight`'s hint ladder
  membership test and its comment) and `tests/release-test.sh` (already
  standing from RED; no assertion in it was edited this dispatch).
- OUT, untouched: slice 1's committed scenario; Item 1.1's
  `pipefail`-stripped scenarios; `scripts/self-release.sh`;
  `tests/self-release-test.sh`; `tests/version-guard-test.sh`;
  `tests/update-plugin-dev-test.sh`; `docs/`; `CLAUDE.md`; `README.md`;
  `toolkit/README.md`; `justfile`.

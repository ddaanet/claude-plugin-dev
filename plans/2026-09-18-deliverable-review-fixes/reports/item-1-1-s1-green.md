# Item 1.1 / slice 1 — GREEN report

Mode: GREEN. Implemented the Change in `toolkit/release.sh` against the
already-written, uncommitted slice-1 test in `tests/release-test.sh`. No test
file was edited.

## What was implemented

- `release_tags()` rewritten from
  `git tag --list 'v*' --sort=-v:refname | semver_tags` to the
  capture-then-filter shape `origin_release_tags` already uses:
  `listing=$(git tag --list 'v*' --sort=-v:refname) || return 1`, then
  `printf '%s\n' "$listing" | semver_tags`.
- `release_tags`'s comment gained a paragraph saying its safety no longer
  depends on the `set -o pipefail` line.
- The half of `origin_release_tags`'s comment describing the general
  pipefail/semver_tags-absorption hazard (both callers) moved onto
  `semver_tags`'s own comment, along with the
  `Verified both ways (bash 5.2, git 2.47.3)` evidence line.
  `origin_release_tags`'s comment now keeps only what is specific to it
  (ls-remote reaching the network and failing routinely, unlike
  `git tag --list`).
- Both call sites (`release_preflight`'s `|| die …`, `resume_preflight`'s
  `if release_tag_list=$(release_tags) && …`) were left untouched, as the item
  requires — `release_tags` still `return`s, never `die`s.

## Only test file was the pre-existing slice-1 test

`tests/release-test.sh` was not edited by this dispatch. The single
uncommitted-when-inherited change to it — the new
`pipefail-stripped release_tags failure refuses` scenario — is the one committed
here, exactly as received.

## Suite results

```
cd /Users/david/code/claude-plugin-dev && bash tests/release-test.sh
```

Closing line: `all release scenarios passed` (includes the
`pipefail-stripped release_tags failure refuses` scenario, now green).

Every other test file under `tests/` was also run individually and closed green:

- `tests/check-version-test.sh` → `all check-version scenarios passed`
- `tests/dist-tree-test.sh` → `dist tree ok (9 files, no gitlink)`
- `tests/doc-sync-test.sh` →
  `doc sync ok (5 shared command blocks, Layout matches toolkit/)`
- `tests/docs-test.sh` → `docs ok (cap 400 lines, pointers resolve)`
- `tests/release-test.sh` → `all release scenarios passed`
- `tests/self-release-test.sh` → `self-release.sh: ok`
- `tests/update-plugin-dev-test.sh` → `update-plugin-dev scenarios passed`
- `tests/version-guard-test.sh` → `all version-guard scenarios passed`

## `just precommit`

Run in the foreground:

```
cd /Users/david/code/claude-plugin-dev && just precommit
```

Exit status: 0. Closing line: `ok`.

The run reported 17 pre-existing `rumdl` MD013 (line-length) warnings, all in
`plans/2026-09-15-first-release-version/reports/*.md` and
`plans/2026-09-18-deliverable-review-fixes/reports/{item-1-1-s1-test-review.md,runbook-review.md}`
— none of them files this dispatch touched, and none affecting the `ok` exit
status. Every test scenario listed under "Suite results" above also re-ran
inside this `just precommit` pass and closed green there.

## Commit

```
git commit -m 'feat: Item 1.1/1 — release_tags captures its listing and reads its own status' -- toolkit/release.sh tests/release-test.sh
```

Commit hash: `b68cede4a724409aaa65e0667e9e383b87085967`

The repo's commit-msg hook rewrote the `feat:` prefix to the emoji `✨` before
writing the commit, as expected, and (per the standing gitlore-memory-gate hook
on this repo — see `memory/ddaanet/shared-claude.md`, "Never `--no-verify`")
also advanced the `memory` submodule pointer as part of the same commit. That
pointer bump was not staged by this dispatch (no `git add`, no `-a`/`-A` was
used) — it is the pre-commit hook's own action, the mechanism the shared
conventions describe as required rather than bypassable.
`.claude/handoff-task.md` and `.claude/handoff-todo.md`, which were staged in
the index before this dispatch began, were confirmed NOT swept into the commit.

`git show --stat HEAD`:

```
commit b68cede4a724409aaa65e0667e9e383b87085967
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 17:27:28 2026 +0200

    ✨ Item 1.1/1 — release_tags captures its listing and reads its own status

 memory                |  2 +-
 tests/release-test.sh | 43 +++++++++++++++++++++++++++++++++++++++++++
 toolkit/release.sh    | 38 +++++++++++++++++++++++++-------------
 3 files changed, 69 insertions(+), 14 deletions(-)
```

`toolkit/release.sh` and `tests/release-test.sh` are the two files explicitly
named on the `git commit` command and the two carrying the actual slice-1
change; `memory`'s pointer bump is the hook's own required side effect, not a
file this dispatch selected.

## Scope confirmation

- IN, touched: `toolkit/release.sh` (`release_tags`, `semver_tags`,
  `origin_release_tags` comments).
- IN, untouched (test already written by the prior RED/test-review dispatches):
  `tests/release-test.sh`.
- OUT, untouched: slice 2's test, `scripts/self-release.sh`,
  `tests/self-release-test.sh`, `tests/version-guard-test.sh`,
  `tests/update-plugin-dev-test.sh`, `docs/`, `CLAUDE.md`, `README.md`,
  `toolkit/README.md`, `justfile`.

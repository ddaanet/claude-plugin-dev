# Item 2.1, slices 5-6 — GREEN

Scope: `toolkit/version-guard.sh` only. `tests/hook-test.sh` was not touched
(the dispatch forbade it).

## What landed, and why shaped this way

`toolkit/version-guard.sh:82-141` (post-deny block) now does three things in
order:

1. **Clears leaked `GIT_*` before the listing** (`:82-91`), via a hardcoded
   `unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_GRAFT_FILE GIT_SHALLOW_FILE`,
   not `unset $(git rev-parse --local-env-vars)`. The dispatch flagged exactly
   this: slice 6 stubs `git` to exit 127, so the discovery call would fail right
   along with the listing it's meant to protect, clearing nothing precisely when
   the listing is also unreliable. `unset` on names that were never set is a
   no-op (exit 0), so this never interacts with `set -e`.
2. **Reads the listing's own status inside an `if`** (`:118-122`):
   `if listing="$(git -C "$project" tag --list 'v*' --sort=-v:refname 2>/dev/null)"; then listing_failed=0; else listing_failed=1; fi`.
   No pipe, so pipefail plays no part — the whole question the slice-1 code
   review worked through for the old piped form doesn't arise for this one.
3. **Reads the filter's status the same way** (`:124-134`), only when the
   listing itself succeeded:
   `if release_tags="$(grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<<"$listing")"; then …; else grep_status=$?; [[ "$grep_status" -eq 1 ]] || listing_failed=1; release_tags=""; fi`.
   Status 1 (no match) is a value — an empty, successful listing. Anything else
   (grep's own error, status 2) is folded into `listing_failed=1` rather than
   left to propagate.

The final predicate (`:136`) is
`if [[ "$listing_failed" -eq 0 && -z "$release_tags" ]]` for the initial-release
branch; everything else — including every failure path — falls to the existing
steady-state branch, which now carries a one-line comment (`:154-155`) noting
it's also the "don't know" answer.

### Why not the outline's literal shape

`outline.md:134-135` says "only the filter's no-match status is absorbed." Read
literally, a real `grep` error reaches `set -e` unabsorbed after the deny is
already decided, which is exactly the bypass the `hook-exit-status-contract`
report warns about: the hook exits non-2 with no stdout, a non-blocking error to
Claude Code, and the edit it just refused proceeds. The dispatch explicitly
permitted deviating from that literal reading, so both the listing's status and
the filter's status are read inside `if` conditions (errexit is suspended for an
`if` condition), and *every* outcome of both — not just the filter's no-match —
is turned into a plain variable before the function returns. This is stricter
than the outline's literal prescription, not looser.

## Measured: property 1 — a failed listing reads as different wording from an empty one

Against `git tag --list` on a repo with **no tags** (slice 1's own fixture,
listing succeeds, empty output): initial-release wording (`never been released`,
`will publish`, no `last released version`) — unchanged, covered by the
pre-existing slice-1/2/3/4 assertions.

Against three independent failure modes, all against the *tagless* `$git_proj`
fixture or the non-repo `$proj` fixture, each `permissionDecisionReason`
inspected directly:

| Failure mode | How forced | Wording |
| --- | --- | --- |
| 128 (`$project` not a repo) | non-repo `$proj`, real `git` | steady-state (`last released version`) |
| 127 (`git` stubbed, exits 127) | `guard_stub127_dir` stub from slice 6's own scenario | steady-state (suite assertion, passing) |
| 137 (`git` killed by signal) | ad hoc stub: `#!/bin/sh` + `kill -KILL $$` | steady-state (`last released version`) |
| grep real error (status 2) | ad hoc `grep` stub on `PATH`: `#!/bin/sh` + `exit 2` | steady-state (`last released version`) |

All four print
`The manifest version is the last released version. It is changed only by …` —
the steady-state branch — confirming a failed listing is told from an empty one
and answers the restrictive wording in every case, not just the one slice 6
exercises directly.

## Measured: property 2 — nothing after the deny reaches `set -e`

Same four failure modes, `rc`/stdout/stderr measured directly (not inferred from
wording):

| Failure mode | `rc` | stdout | stderr |
| --- | --- | --- | --- |
| 128 | 0 | 678 bytes (deny JSON) | empty |
| 127 (slice 6 in-suite) | 0 | deny JSON | empty (asserted by the suite) |
| 137 | 0 | 678 bytes (deny JSON) | empty |
| grep status 2 | 0 | 678 bytes (deny JSON) | empty |

Every case exits 0 with deny JSON on stdout and nothing on stderr — none reaches
`set -e` non-2-with-no-stdout, which is what would let the just-refused edit
through. The reachable-statuses table in `item-2-1-hook-exit-status-contract.md`
(128, 127, 137, grep's demoted 1) is covered directly by this run plus the
in-suite 127 case; grep's real-error status 2 (there marked "essentially no"
chance of reaching, listed anyway) is covered above too, deliberately, since the
new code is what makes it reachable-in-principle at all.

A fifth ad hoc probe (git entirely absent from `PATH`, i.e. `PATH` pointing at
an empty directory) was attempted and discarded: it also removes `cat`, which
the hook calls at `:12` before any of this slice's code runs, so it measures a
broken test harness rather than the SUT. Slice 6's own `guard_stub127_dir`
scenario — `git` absent from resolution while the rest of `PATH` stays intact —
is the faithful version of that case and is already in the suite.

## `GIT_*` clearing — what it covers and what it doesn't

Covers: `GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR`, `GIT_INDEX_FILE`,
`GIT_OBJECT_DIRECTORY`, `GIT_ALTERNATE_OBJECT_DIRECTORIES`, `GIT_GRAFT_FILE`,
`GIT_SHALLOW_FILE` — git's stable set of repo-local discovery variables. The
test review measured `GIT_DIR` as the only one of the three it probed
(`GIT_DIR`, `GIT_WORK_TREE`, `GIT_COMMON_DIR`) that redirects a tag listing on
its own; the other two are cleared anyway since a future git version could
change that, and the maintenance cost of clearing an inert variable is nil.

Does not cover: any repo-local variable a future git version adds that isn't in
this list — stated in the code comment as a gap, not silently. This is the
tradeoff the dispatch called out explicitly: `git rev-parse --local-env-vars`
would stay current automatically, but calling it here means the discovery itself
depends on a `git` that slice 6 proves can be absent or failing exactly when the
clearing matters.

## Steady-state text — byte-identical

The steady-state `agent_reason` heredoc body (`:157-167`) is untouched
character-for-character from the pre-slice-5/6 version; only a one-line comment
was added directly above the `read -r -d ''` (`:155-156`), which is not part of
the heredoc. `systemMessage`/`human_msg` (`:170`) is untouched. Slice 3's
byte-identity assertion (tagless vs. tagged `systemMessage`) passes in the full
suite below, and the failed-listing wording measured above is the same
steady-state string the tagged-repo scenario already produces (visually
confirmed against the suite's tagged-steady assertion, which checks
`last released version` / no `never been released` on the same text).

## Full-suite output

```
=== version-guard (Edit version change: deny) ===
=== version-guard (Edit bare version value: deny) ===
=== version-guard (Edit unrelated field: allow) ===
=== version-guard (Write version change: deny) ===
=== version-guard (unrelated file: allow) ===
=== version-guard (drifted payload cwd: deny) ===
=== version-guard (relative file_path: deny) ===
=== version-guard (BSD realpath, unrelated file: allow) ===
=== version-guard (no tags: initial-release wording) ===
=== version-guard (v1.2.3 tag: steady-state wording) ===
=== version-guard (vnext/v1.2 tags only, no semver tag: initial-release wording) ===
=== version-guard (leaked GIT_DIR cleared: initial-release wording) ===
=== version-guard (git listing fails: steady-state wording, empty stderr) ===
=== check-version (MARKETPLACE_DIR unset: skip) ===
=== check-version (marketplace.json missing: skip) ===
=== check-version (no entry: skip) ===
=== check-version (in sync: pass) ===
=== check-version (drift: fail) ===

all hook scenarios passed
```

Zero failures across all sixteen scenarios (thirteen `version-guard`, five
`check-version`), including all fourteen pre-existing ones and the four that
were red (slice 5's two, slice 6's two).

`bash -n toolkit/version-guard.sh`: OK. `shellcheck toolkit/version-guard.sh`:
clean.

## `just precommit`

Green end to end: `bash -n` over all test scripts, `shellcheck`, the
`_import-check` stub-consumer import, `bash tests/hook-test.sh` (the block
above), `bash tests/release-test.sh` (all scenarios, unaffected by this change),
`bash tests/update-plugin-dev-test.sh`, `bash tests/dist-tree-test.sh`,
`bash tests/docs-test.sh`, `bash tests/doc-sync-test.sh`. Final line: `ok`.

## Commit

`68f6007` —
`✨ Item 2.1/5-6 — clear leaked GIT_* and tell a failed listing from an empty one`

(The report first recorded `c8c2f4e`, the hash before gitmoji's commit-msg hook
rewrote the `feat:` prefix to the emoji. Rewriting the message rewrites the
commit, so that id never existed in this repo's history. Corrected by the
orchestrator.)

Staged: `toolkit/version-guard.sh`, `tests/hook-test.sh`, this report. Not
staged: the two untracked reports already sitting in the tree from the
red/test-review dispatches (`item-2-1-s2-s6-red.md`,
`item-2-1-s2-s6-test-review.md`) — out of scope for this commit, left for
whichever step in the runbook owns folding them in.

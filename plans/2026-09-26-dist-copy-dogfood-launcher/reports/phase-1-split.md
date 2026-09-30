# Phase 1 split: tests/dogfood-test.sh into four suites

`tests/dogfood-test.sh` (920 lines) is removed with `git rm`. Its scenarios now
live in four self-contained suites, each with its own header, cleanup trap, and
only the harness helpers it calls.

| Suite | Lines | Holds |
| --- | --- | --- |
| `tests/dogfood-sync-test.sh` | 340 | copy behaviour (9 scenarios: tracked file, ignored and `.git`, root, both deletions, becomes-ignored, spaces, nested repo, no recursion) and `unknown subcommand is usage` |
| `tests/dogfood-sync-refusal-test.sh` | 219 | pattern-character abort, the two refusals, git failure, rsync failure |
| `tests/dogfood-pre-tool-test.sh` | 374 | every pre-tool scenario |
| `tests/dogfood-session-start-test.sh` | 309 | every session-start scenario |

The sync suite alone would have been about 440 lines, so the second split at the
refusal boundary was taken. `justfile` `precommit` lists the four on the
`bash -n` line and runs them one per line in the order sync, sync-refusal,
pre-tool, session-start.

Choices: `assert_contains` is in sync, sync-refusal and pre-tool (the usage,
git-failure and bad-payload scenarios); `make_decoy` only in sync; `assert_file`
only in sync and sync-refusal; `unset CLAUDE_CODE_PLUGIN_DIRS` and its comment
only in the session-start suite, the only one that reads it. The sync-refusal
suite carries `# shellcheck disable=SC2034` above `run_dogfood`, since no
scenario there reads `$out`.

## Proofs

1. Scenario-name set: `diff` of the sorted `echo "=== ..."` headers, old file
   (`git show HEAD:tests/dogfood-test.sh`) against the four new suites, is empty
   (printed `HEADERS-SAME`).
2. Assertion call sites (`assert_*`, `fail`, `jq_holds`, `assert_denied*`,
   `assert_session_warns` at line start): old 177, new 186. The +9 is all helper
   bodies copied: the `fail` line inside `assert_eq`, `assert_contains`,
   `assert_file`, `assert_absent` was 4 in the old file and is 4 (sync) + 4
   (refusal) + 3 (pre-tool, no `assert_file`) + 1 (session-start, `assert_eq`
   only) = 12, so +8; the `fail` inside `jq_holds` is copied into pre-tool and
   session-start, +1. Scenario bodies are unchanged.
3. Each suite passed alone from the repo root, in the foreground, ending
   `all dogfood sync scenarios passed`, `... sync refusal ...`,
   `... pre-tool ...`, `... session-start ...`. Each also passed from `/tmp` by
   absolute path (the old suite `cd`s to the repo root from `$0`, so it already
   supported that; preserved).
4. `bash -n` and `shellcheck` clean on all four.
5. `just format-docs` then `just precommit` in the foreground: exit 0, ending
   `ok`.

## Grep for the old filename

`git grep -n 'dogfood-test\.sh'` after the change. `justfile` no longer has a
hit (it was the only stale hit in scope, fixed). Hits by file:

| Path | Hits | Classification |
| --- | --- | --- |
| `plans/2026-09-26-dist-copy-dogfood-launcher/runbook.md:78,82,143,188,390` | 5 | stale: live runbook text (78 projection, 82 Item 1.1 "new suite", 143 Item 1.2, 188 Item 1.3, 390 Item 3.6 "Quality gate paragraph names `dogfood-test.sh`"); orchestrator |
| `plans/2026-09-26-dist-copy-dogfood-launcher/outline.md:205` | 1 | stale-ish: outline's Item 1.1 "new suite `tests/dogfood-test.sh`"; the outline is a plan, orchestrator decides |
| `.claude/handoff-todo.md:3` | 1 | stale: the pending split note, now done; orchestrator |
| `reports/outline-review.md:163`, `reports/runbook-review.md:192,270`, `reports/runbook-simplification.md:23` | 4 | accurate-historical: review records of the plan as then written |
| `reports/item-1-1-s*`, `item-1-2-s*`, `item-1-3-s*` (red, green, test-review, code-review) | many | accurate-historical: per-slice write-time records of the suite as it was then |

Not edited: anything in `plans/`, `docs/`, `CLAUDE.md`, READMEs. CLAUDE.md's
Quality gate list names no dogfood suite (no hit), and `tests/dist-tree-test.sh`
does not list tests.

## Orchestrator follow-up: stale hits resolved

The orchestrator ran the whole-tree grep (`git grep -n 'dogfood-test'`, which
also matches the name without `.sh`) again after the runbook and outline edits.
Every hit is classified below against where the tests now live.

| Path | Classification | Resolution |
| --- | --- | --- |
| `justfile` | was stale | fixed in the split commit; no hit remains |
| `runbook.md` Phase 1 preamble, Items 1.1, 1.2, 1.3, 3.6 | were stale | revised: the preamble records the split and names the four suites, and each item names its own suite; Item 3.6's Quality gate list now names the four dogfood suites and `dogfood-launcher-test.sh`; the one remaining hit, preamble line 78, is accurate because it names the old file as what was split |
| `outline.md` items 1, 2 and 5 | were stale | revised: the outline is the design input every later dispatch reads, so it names the four suites; item 5's "two new suites" is now "new suites" |
| `.claude/handoff-todo.md:3` | stale | an open decision in the handoff task frame, now settled by my human partner; left to the coordinator, which owns that file |
| `reports/item-1-*-s*-*.md`, `outline-review.md`, `runbook-review.md`, `runbook-simplification.md`, this report | accurate-historical | dated write-time records of the suite as it then was; never revised |
| `CLAUDE.md`, `docs/`, `README.md`, `toolkit/`, `tests/` | no hit | CLAUDE.md's Quality gate list does not yet name the dogfood suites; Item 3.6 adds them |

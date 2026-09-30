# Review: Phase 2 checkpoint — the shim and the hook wiring

**Scope**: `git diff faef572 HEAD` over `toolkit/bin/claude`,
`toolkit/install.sh`, `tests/dogfood-launcher-test.sh`, `tests/install-test.sh`,
`tests/update-plugin-dev-test.sh`, `tests/dist-tree-test.sh`, `justfile`,
`CLAUDE.md` (the 2.1/1 Layout bullet), and the runbook and outline edits that
named the new suite. Phase 1's `toolkit/dogfood.sh` was read for the calls Phase
2 makes into it. Phase 3's items are out of scope. **Date**: 2026-09-30
**Mode**: review + fix

## Summary

Items 2.1 and 2.2 each conform to their runbook `Interfaces:` lines, and the
boundary split is faithful. The phase-level gap was composition. Each item's
suite pinned its own half of a contract: the literal hook commands, the
subcommand names, the exported variable. Nothing ran the halves together. Also,
install.sh's step-3 error branch was unexercised, including the `pipefail`
dependency that keeps it from writing an empty file over a consumer's
`settings.json`. Four fixes were applied, with six mutations proving the new
assertions red. `just precommit` is green.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Step 3's error branch was untested, including the `pipefail` dependency
   that makes it fail closed**
   - Location: `toolkit/install.sh:158-167`; `tests/install-test.sh`
   - Problem: No suite reached
     `could not wire the hooks into … — nothing written.` (flagged by the 2.2/1
     code review). The gap was wider than that review's suggested fixture
     showed. With an object where the first stage's array belongs
     (`.hooks.PreToolUse`), the first `add_hook` fails, and the two stages
     behind it read empty input and exit 0. So only `pipefail` routes the
     failure to the error branch. Without it the pipeline reports success, `cmp`
     differs, and the empty output is written over the consumer's file. The
     review's `.hooks.SessionStart` fixture fails only in the last stage, so it
     cannot detect a lost `pipefail`.
   - Fix: New scenario
     `install.sh: a settings.json it cannot wire is left as it was`.
     `plugin-dev/` is pre-created so no vendoring runs. The fixture is
     `{"hooks": {"PreToolUse": {"matcher": "Bash"}}}`. The scenario asserts a
     non-zero exit, the error line, and a byte-identical file (`cmp`).
   - Mutation proof:
     - M3 `set +o pipefail` before step 3 → 3 FAILs (`reported success`, the
       message missing, `was rewritten`). Restored by inverse edit;
       `git diff --quiet toolkit/install.sh` clean.
     - M4 `exit 1` removed from the error branch →
       `an unwirable settings.json was rewritten`. Restored; clean.
   - **Status**: FIXED

2. **Nothing ran the hook commands install.sh writes against dogfood.sh**
   - Location: `tests/install-test.sh`, existing-settings scenario
   - Problem: install-test pinned the command strings as literals copied from
     the runbook. The dogfood suites pinned the subcommands `dogfood.sh`
     accepts. No test executed a written command, through a shell, with a
     `CLAUDE_PROJECT_DIR` holding a space. That is the path Claude Code takes at
     hook-fire time. If `dogfood.sh`'s subcommand names drifted, install-test
     would stay green while every consumer's hooks exited 2 with a usage line.
     The same holds for a quoting change that still passed the `"${…}"`
     substring check.
   - Fix: The scenario now reads each dogfood command back from the
     `settings.json` install.sh wrote. It runs the command with `sh -c`, with
     `CLAUDE_PROJECT_DIR="$sandbox/my consumer"`, over a copy of
     `toolkit/dogfood.sh`, and asserts:
     - the pre-tool command exits 0 with a deny for a copy path;
     - the session-start command exits 0 with
       `does not load <physical root>/dist/plugin`.

     A missing command falls back to `false`, so the check cannot pass vacuously
     on an empty `sh -c`.
   - Mutation proof:
     - M1 unquoted `pretool_cmd` →
       `the written pre-tool command runs: exit code: expected '0', got '127'`,
       plus the missing deny. The existing quoting assertions redden too.
     - M2 `dogfood.sh`'s case renamed to `pretool`/`sessionstart` → 4 FAILs, all
       in the new assertions (exit 2, output missing). Before this fix,
       install-test was green under this mutation.
     - Both restored by inverse edit; `git diff --quiet` clean.
   - **Status**: FIXED

### Minor Issues

1. **The shim's export and session-start's comparison were only transitively
   matched**
   - Location: `tests/dogfood-launcher-test.sh`, scenario
     `the shim exports the copy`
   - Note: The launcher suite pins the export as `<physical root>/dist/plugin`.
     The session-start suite pins silence for that value. No test fed one to the
     other. The fix feeds the recorded value to `dogfood.sh session-start`,
     reached through the scenario's symlinked spelling and from its foreign
     launch directory, and expects silence. It pairs that with
     `/elsewhere/dist/plugin`, which must warn, so the silence cannot pass
     vacuously.
   - Mutation proof:
     - M5: the shim exports the relative `dist/plugin` →
       `session-start takes the copy the shim exported: expected ''` (the
       warning JSON), beside the existing export assertions.
     - M6: session-start never warns (`exit 0` after the loop) →
       `another repo's copy is not rejected`.
     - Both restored; clean.
   - **Status**: FIXED

2. **The outline and runbook still called the split out of scope after it was
   done**
   - Location: `outline.md` item 4 (the "406 lines … separate cleanup, not this
     job's" paragraph); `runbook.md` Item 2.2 ("Out of scope: moving
     install.sh's scenarios into their own suite")
   - Note: The split had already edited both files to name
     `tests/install-test.sh`. The unchanged sentences beside those edits
     contradicted them. Both now say the scenarios were built in
     `update-plugin-dev-test.sh` and moved out at the Phase 2 boundary, citing
     `reports/phase-2-split.md`. The runbook stays at 399 lines after
     `format-docs`.
   - **Status**: FIXED

## Fixes Applied

- `tests/install-test.sh`:
  - existing-settings scenario: `run_hook` and four assertions that run the
    written dogfood commands through `sh -c` with a spaced `CLAUDE_PROJECT_DIR`
    (Major 2);
  - new scenario `install.sh: a settings.json it cannot wire is left as it was`
    (Major 1);
  - the file is 395 lines.
- `tests/dogfood-launcher-test.sh`, scenario `the shim exports the copy`: a
  `session_start` helper, plus an accept/reject pair on the exported value
  (Minor 1). The file is 344 lines.
- `plans/2026-09-26-dist-copy-dogfood-launcher/outline.md` item 4 and
  `runbook.md` Item 2.2: the stale out-of-scope sentences are rewritten (Minor
  2).
- No production file changed. Every mutation was reverted by inverse edit, and
  `git diff --quiet` is clean on `toolkit/install.sh`, `toolkit/dogfood.sh` and
  `toolkit/bin/claude`.

## Checked, no finding

- **Shim vs Item 2.1 Interfaces.**
  - `<root>` is the physical `<shim dir>/../..`, captured with an `x` shield, so
    a trailing newline survives. This is the Phase 1 defect class, absent here.
  - `sync` runs first, and `set -e` passes its status through without an exec.
  - Then come the export, the `CDPATH` unset, and `-ef` stripping with empty
    entries tested as `./claude`.
  - With no next `claude`: exit 127 and the one stderr line.
- **install.sh vs Item 2.2 Interfaces.**
  - Both commands match byte for byte.
  - "Present" is a command match under the event, whatever the matcher.
    SessionStart carries no `matcher` key.
  - version-guard keeps its unquoted spelling.
  - The header's step 3 and the `changed` line name all three hooks.
- **End-to-end composition.**
  - The hook commands never rely on `CLAUDE_PROJECT_DIR` for the root, because
    `dogfood.sh` finds it from its own location. The variable only locates the
    script, and the quotes carry a spaced path through `sh` (now tested).
  - The shim's export is physical and absolute, and `dist/plugin` exists by
    export time (sync's `mkdir -p`), so session-start's physical comparison
    matches (now tested).
- **Portability.**
  - The shim uses only bash 3.2 constructs (`[[ -ef ]]`, parameter expansion)
    and no GNU flags.
  - The new test code uses `env VAR= …`, `sh -c`, `<<<` in a bash suite, and
    `pwd -P`. `sh` is dash here, so the quoting check runs under a strict POSIX
    shell.
- **shellcheck.** Clean on all touched scripts (the `precommit` shellcheck line
  covers `toolkit/bin/claude`).
- **Split faithfulness.**
  - Both suites carry their own harness and read and run alone.
  - The `justfile` wiring names `install-test.sh` on the `bash -n` line and on
    its own run line.
  - Stale cross-references are left for Item 3.6 (`CLAUDE.md` Quality gate).
- **dist-tree mode check.** `git ls-files -s` reads the index, which is the
  commit's index under the pre-commit hook. That is the intended target, and
  `subtree split` preserves the mode into the dist tag.

## Deferred Items

The following items were identified but are out of scope:

- **`CLAUDE.md` Quality gate list does not yet name `install-test.sh` or
  `dogfood-launcher-test.sh`**. Reason: Item 3.6 (Scope OUT).
- **`CLAUDE.md` Conventions bullet on `hook_cmd` quoting does not cover the two
  dogfood commands**. Reason: Item 3.6 (Scope OUT).

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D4 sync only on promotion | Satisfied | shim syncs once before exec; install.sh wires no `PostToolUse` |
| D6 copy guard wired | Satisfied | `PreToolUse` `Write\|Edit\|NotebookEdit` → pre-tool; the written command runs the guard (new test) |
| D7 session-start wired | Satisfied | `SessionStart`, no matcher; the written command runs the check (new test) |
| D8 loud sync failure at launch | Satisfied | `a failed sync aborts the launch` |
| D9 the shim | Satisfied | Item 2.1 scenarios, plus the export accepted by session-start (new test) |
| D11 install.sh wiring | Satisfied | any-matcher idempotency, quoting, fail-closed error branch (new test) |

## Gate

`just precommit` exit 0, ending `ok`. The passing checks were:

- `whitespace`, `format-docs`, `shellcheck`, `bash -n`, and `_import-check`;
- the suites `version-guard`, `check-version`, `release`, `self-release`,
  `update-plugin-dev`, `install`, `dist-tree`, `docs`, `doc-sync`, `citation`,
  `dogfood-sync`, `dogfood-sync-refusal`, `dogfood-pre-tool`,
  `dogfood-session-start` and `dogfood-launcher`.

## Positive Observations

- The shim's `path_without` prefixes each kept entry with a colon and strips the
  first one. That keeps a leading empty entry without special-casing it.
- The pipeline refactor removed the stub-writing fallback. The hazard its old
  comment warned about is now impossible by construction, not just guarded.
- The launcher suite's `no next claude` scenario asserts both lookups (with the
  shim, and with what the shim leaves) before reading the 127, so the exit code
  cannot come from the wrong cause.

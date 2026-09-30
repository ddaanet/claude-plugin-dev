# Review: Phase 1 checkpoint — `toolkit/dogfood.sh` and its four suites

**Scope**: Phase 1 as a whole (Items 1.1, 1.2 including slice 1.2/6, 1.3), the
split of `tests/dogfood-test.sh` into four suites, the `justfile` precommit
wiring, and 1.1/1's gate bookkeeping (`tests/dist-tree-test.sh`, the `CLAUDE.md`
Layout bullet). Diff base `fd16ae65f4b2`. **Date**: 2026-09-30 **Mode**:
review + fix. This is not the final checkpoint.

## Summary

The three subcommands share `root_dir` and `physical_path` consistently, the
comments above each function are true after the later slices, and the split lost
and duplicated nothing. One real defect crossed all three subcommands: the root
went through a bare `$(...)` capture, so a repo whose name ends in a newline
lost that newline. `sync` refused, `session-start` warned wrongly, and
`pre-tool` silently allowed an edit into the copy. This was the one place the
newline safety used elsewhere in the script was missing. It is fixed, with a red
then green test in each suite. The runbook Interfaces for 1.1 and 1.2 did not
match the exit statuses and are corrected.

**Overall Assessment**: Ready

## Issues Found

### Major Issues

1. **The root lost a trailing newline in every subcommand**
   - Location: `toolkit/dogfood.sh` `root_dir` and its three callers.
   - Problem: `root="$(root_dir)"`, and `pwd -P` inside it, both strip trailing
     newlines. Everywhere else the script shields a captured path with an `x`
     (the payload path, `physical_path`, `readlink -f`), so the root was the
     inconsistent case. This was probed before fixing, with a consumer at
     `…/repo<LF>`:
     - `sync` refused with `…/repo/.claude-plugin/plugin.json not found`;
     - `pre-tool` exited 0 with empty stdout for an edit into
       `…/repo<LF>/dist/plugin/…`, so the guard did not fire;
     - `session-start` warned while `CLAUDE_CODE_PLUGIN_DIRS` named the copy.
   - Fix: `root_dir` now prints `$PWD` after `cd -P` with no trailing newline.
     The `dirname` capture is shielded with `x`, and `?x` also drops dirname's
     own newline. Each caller shields its capture:
     `root="$(root_dir && printf x)"; root="${root%x}"`. The chaining that stops
     a failed step from falling through to `/` is kept.
   - Tests: one scenario per affected suite, each built by `mv`-ing the
     fixture's consumer to a name ending in `$'\n'`:
     - `sync keeps a root whose name ends in a newline` (sync suite);
     - `pre-tool denies an edit into the copy of a root ending in a newline`
       (pre-tool suite, through the full `assert_denied`);
     - `session-start matches the copy of a root ending in a newline`
       (session-start suite).

     All three were red against HEAD's script: sync with 2 failures, including
     `expected '0', got '1'`; pre-tool with 7 failures, stdout `''`;
     session-start with 1 failure, where the warning object was printed. All
     three are green after the fix. Relative invocation
     (`bash plugin-dev/dogfood.sh sync` from the root, `CDPATH=/tmp`) was also
     probed green.
   - **Status**: FIXED

2. **Item 1.2's Interface said `pre-tool` exits 0 always**
   - Location: `runbook.md`, Item 1.2 Interfaces.
   - Problem: the code exits non-zero, by design, on a payload jq cannot read
     and on a directory it cannot enter. The function comment says so, and the
     suite pins it (`pre-tool fails loudly on a payload jq cannot read`). Phase
     2 builds on these Interfaces.
   - Fix: "exit 0 per verdict; non-zero on an unreadable payload or an
     unenterable directory".
   - **Status**: FIXED

### Minor Issues

1. **Item 1.1's Interfaces omitted the git-failure contract**
   - Location: `runbook.md`, Item 1.1 Interfaces.
   - Note: `require_ignored_copy` and the `ls-files` pipeline both exit with
     git's own status and stderr, before rsync runs and without touching `dist/`
     (slice 1.1/6 tests this). Added as one Interface line.
   - **Status**: FIXED

2. **The script header left out `session-start`'s jq warning and exit contract**
   - Location: `toolkit/dogfood.sh` header.
   - Note: the header said only "warn when this session does not load …". It now
     adds "or when jq is missing; exit 0, empty stdout when silent", matching
     `pre-tool`'s line.
   - **Status**: FIXED

3. **The `physical_path` comment said "from the first missing name on"**
   - Location: `toolkit/dogfood.sh`, the `physical_path` comment.
   - Note: the code switches to the as-spelled tail at the first name that is
     not an existing directory. An existing file leaf is kept as spelled too,
     and `pre_tool` depends on that when it applies `readlink -f` to a leaf
     link. The comment is reworded to say this.
   - **Status**: FIXED

4. **The `unset CDPATH` comment cited a capture shape that no longer exists**
   - Location: `toolkit/dogfood.sh:15`.
   - Note: after the `root_dir` rewrite, no `$(cd … && pwd -P)` remains. The
     unset is still needed, because `root_dir`'s `cd -P -- "plugin-dev/.."` is
     relative when the script is invoked by a relative path. The comment now
     names that reason.
   - **Status**: FIXED

5. **Dead `$out` in the refusal suite, silenced by a shellcheck disable**
   - Location: `tests/dogfood-sync-refusal-test.sh`, `run_dogfood`.
   - Note: rather than disable SC2034 for a variable no scenario read, the
     pattern-character, no-manifest and not-ignored refusals now assert empty
     stdout, which is part of `sync`'s Interface (no stdout). The disable is
     removed.
   - **Status**: FIXED

6. **A blank line was missing between two helpers in the session-start suite**
   - Location: `tests/dogfood-session-start-test.sh`, between `jq_holds` and
     `run_session_start`. This was left over from the split.
   - **Status**: FIXED

## Fixes Applied

- `toolkit/dogfood.sh`:
  - `root_dir` is newline-safe;
  - its three callers shield their captures;
  - the header documents `session-start`'s jq warning and exit contract;
  - the `physical_path` comment is reworded;
  - the `CDPATH` comment names the current reason.
- `tests/dogfood-sync-test.sh`: new scenario
  `sync keeps a root whose name ends in a newline`.
- `tests/dogfood-pre-tool-test.sh`: new scenario
  `pre-tool denies an edit into the copy of a root ending in a newline`.
- `tests/dogfood-session-start-test.sh`:
  - new scenario `session-start matches the copy of a root ending in a newline`;
  - blank line between the two helpers.
- `tests/dogfood-sync-refusal-test.sh`: the refusals assert empty stdout, and
  the SC2034 disable is dropped.
- `plans/…/runbook.md`: Item 1.1 gains a git-failure Interface line, and Item
  1.2's exit-status Interface is corrected. The runbook is now 399 lines, 1
  under the 400 cap. Any Phase 2 or 3 revision to it will need a line found
  elsewhere, or a split.

## Cross-slice checks (review focus)

- **Shared helpers:** all three subcommands take the root from `root_dir` and
  nothing else. None reads `CLAUDE_PROJECT_DIR` or the payload `cwd`, and the
  suites pin this with a decoy root and a foreign `cwd`. `pre-tool` and
  `session-start` both resolve through `physical_path`, the same resolver.
  `session-start` guards it with `-d`/`-x` and uses `|| continue`, so an
  unenterable entry prints no `cd` error.
- **Function comments:** checked line by line against the code after slices
  1.2/4–6 and 1.3/2–4. The `pre_tool` comment is accurate, covering:
  - the leaf `readlink -f`, including chains;
  - dangling, looping or unenterable leaf links, which are compared as spelled;
  - non-zero on an unreadable payload or an unenterable directory;
  - silence without jq.

  The `session_start` comment is accurate, covering whole-entry comparison,
  resolution only for absolute enterable entries, and slash stripping. The
  `sync_copy` comment is accurate on pipefail, SIGPIPE and the pattern-character
  refusal. The two exceptions were the `physical_path` wording and the `CDPATH`
  note, both fixed above.
- **Interfaces against code:**
  - 1.1 now matches.
  - 1.2 now matches.
  - 1.3 matches: exit 0, stdin not read, one object on a warning, and a static
    object without jq.
- **The split:** the scenario bodies of the old 920-line `tests/dogfood-test.sh`
  (at `b0ede63^`) were diffed as a sorted multiset against the four new suites.
  There are 41 scenario headers on each side, and the only lines that differ are
  helper definitions that moved into each suite's harness. Nothing was lost or
  duplicated. Each suite runs alone, from its own harness copy, with no dead
  helper after the `$out` fix above. `CLAUDE_CODE_PLUGIN_DIRS` is unset only in
  the session-start suite, the only one that reads it.
- **Whitespace and newlines:** the script handles NUL-delimited ignore lists,
  whole-entry `:` splitting and parameter-expansion path walking, and every
  captured path is `x`-shielded now that the root is too. One bound remains: the
  script directory's own name is taken from `dirname` and is shielded, but the
  vendored directory is always `plugin-dev`.
- **Portability (bash 3.2, BSD):** nothing is bash-4-only:
  - `read -r -d ''`, `printf '%s\0'` and `+=` are all in 3.2;
  - no `mapfile`, associative arrays or `${,,}` are used;
  - `mktemp` with an explicit template, `dirname`, `readlink -fn --` (accepted)
    and `git`/`jq -j` behave the same on macOS.

  The suites use no `timeout`, `sed -i`, `stat` or `date -d`. The rsync flags
  under openrsync remain the outline's stated macOS risk, which runs on a
  consumer and is not a Phase 1 fix.
- **Gate bookkeeping for Phase 2:** in place:
  - `dist-tree-test.sh` lists `dogfood.sh`;
  - `doc-sync-test.sh` passes with the new Layout bullet;
  - `precommit` shellchecks `toolkit/dogfood.sh`, runs `bash -n` on all four
    suites, and runs them.

  Phase 2's 2.1/1 adds `bin/claude` the same way.

## Deferred Items

- **The `CLAUDE.md` Layout bullet for `toolkit/dogfood.sh` describes only
  `sync`.** Reason: the runbook's "Two gates" section gives Item 3.6 every
  `CLAUDE.md` edit beyond the gate-forced bullet, including bringing that bullet
  to its neighbours' shape. The bullet is accurate as far as it goes and passes
  `doc-sync-test.sh`.

## Verification

- Every dogfood suite was run alone in the foreground, and all four passed:
  `all dogfood {sync,sync refusal,pre-tool,session-start} scenarios passed`.
- `shellcheck toolkit/dogfood.sh tests/dogfood-*.sh` is clean.
- `just precommit` exits 0 and ends in `ok`. The run includes whitespace,
  format-docs, `_import-check` and every suite, as well as docs (cap 400, with
  the runbook at 399), doc sync and citations.
- Suite sizes are all under the 400-line cap:

  | File | Lines |
  |---|---|
  | `tests/dogfood-sync-test.sh` | 351 |
  | `tests/dogfood-sync-refusal-test.sh` | 221 |
  | `tests/dogfood-pre-tool-test.sh` | 384 |
  | `tests/dogfood-session-start-test.sh` | 323 |
  | `toolkit/dogfood.sh` | 254 |

## Positive Observations

- Each negative has a paired positive over the same fixture: the jq-less
  controls, the decoy roots, and the sentinel plus new-file check that proves
  rsync never ran.
- Failure is loud where it should be: the jq-presence guard is kept separate
  from jq's error, and git's and rsync's statuses and stderr pass through
  unredirected.
- The comments are thorough and, apart from the two noted above, still exactly
  true after six rounds of rewriting.

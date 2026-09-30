# Review: Item 2.1 slice 1 — test review (RED)

**Scope**: `tests/dogfood-launcher-test.sh` (new, untracked), the RED report
`reports/item-2-1-s1-red.md`, and the inert stub `toolkit/bin/claude` (for stub
completion only). **Date**: 2026-09-30 **Mode**: review + fix

## Summary

The RED run was valid. All four tests failed on an assertion, none passed and
none errored, and the stub needed no completion. The problem was that three of
the four tests would also have passed for a wrong shim once the exec worked. I
wrote a candidate shim from the slice's Interfaces and ran a mutation matrix
against it. Before the fixes, three wrong shims passed the whole suite: one that
forks instead of exec'ing, one that syncs after the next claude runs, and one
that resolves `<root>` logically. A shim that takes `<root>` from the launch
directory also passed. All of these are now caught. The suite is still red
against the inert stub, with 6 assertion failures across the 4 tests.

**Overall Assessment**: Ready

## Mechanical first check

`bash tests/dogfood-launcher-test.sh` was run in the foreground against the
inert stub (`#!/usr/bin/env bash` / `exit 0`, mode 755).

- Before the fixes: 4 FAIL, each on its own assertion, exit 1, none PASSED, none
  ERROR. This matches the RED report.
- After the fixes: 6 FAIL, exit 1. Each test fails only on its assertions:

| Test | Assertions failing (inert stub) |
|---|---|
| the shim execs the next claude with argv intact | argv `<stub did not record argv>`; pid `<stub did not record pid>` |
| the shim syncs before exec | copy at launch `<stub did not record copy>`; `dist/plugin/.claude-plugin/plugin.json` not a regular file |
| the shim exports the copy | `<stub did not record plugin_dirs>` |
| the shim unsets CDPATH | `<stub did not record cdpath>` |

`bash -n` and `shellcheck` are clean. The file is 192 lines.

## Issues Found

### Major Issues

1. **`syncs before exec` did not check the order**
   - Location: `tests/dogfood-launcher-test.sh`, the "syncs before exec"
     scenario.
   - Problem: the test only checked that the copy existed after the run. A shim
     that runs `claude "$@"` and then syncs passed the whole suite (proven with
     the candidate mutation). The copy the next claude loads would be stale on
     every launch.
   - Fix: the stub now records whether
     `<root>/dist/plugin/.claude-plugin/plugin.json` existed when it started.
     The test asserts `present`. It also asserts first that the fixture starts
     with no `dist/`, so the check cannot be satisfied by the fixture's initial
     state. The existing regular-file assertion stays.
   - **Status**: FIXED. The sync-after mutation now reds with `absent`, and the
     never-sync mutation reds on both assertions.

2. **`execs the next claude` did not check for exec**
   - Location: the argv scenario.
   - Problem: a shim that runs `claude "$@"; exit 0` as a child passed. Its argv
     and exit status were both identical to an exec.
   - Fix: the stub records `$$`. `run_claude` exposes `$launch_pid`, the pid the
     launch subshell `exec`s `claude` as. The test asserts they are equal. Both
     shebangs are `#!/usr/bin/env bash`, and `env` execs in place, so a real
     exec chain keeps the pid.
   - **Status**: FIXED. The fork mutation reds (`expected '338', got '357'`).

3. **`exports the copy` did not check that `<root>` is physical**
   - Location: the export scenario.
   - Problem: `$sandbox` is already `pwd -P`, and the shim was reached through
     its physical PATH entry, so a logical `cd … && pwd` root printed the same
     string. The mutation passed.
   - Fix: this scenario reaches the shim through `$sandbox/link` → `$consumer`
     (`$shim_dir="$sandbox/link/plugin-dev/bin"`) and asserts the physical
     `$consumer/dist/plugin`.
   - **Status**: FIXED. The logical-root mutation reds with
     `got '…/link/dist/plugin'`.

4. **`exports the copy` accepted a `<root>` taken from the launch directory**
   - Location: the export scenario.
   - Problem: the fixture launches from `$consumer`, so `root="$PWD"` and
     `git rev-parse --show-toplevel` both passed. Slice 4 launches from
     `<root>/skills/demo`, which catches `$PWD` but not `--show-toplevel`. No
     slice in the runbook would have caught a shim that asks git for the root.
     The interface pins `<root>` to the shim's physical `<shim dir>/../..`.
   - Fix: `make_consumer` sets a new `$launch_dir` (default `$consumer`), and
     `run_claude` `cd`s into it. The export scenario launches from
     `$sandbox/elsewhere`, a directory outside the consumer. Slice 4 can set
     `launch_dir` to `skills/demo` with no new plumbing.
   - **Status**: FIXED. Both the `$PWD` and the `--show-toplevel` mutations red.

5. **The runner's `CLAUDE_CODE_PLUGIN_DIRS` leaked into the run**
   - Location: the suite prologue.
   - Problem: a suite run from a dogfood session inherited that session's value.
     So whether a shim that appends to the variable passed depended on the
     runner's environment, not on the code. Checking overwrite is slice 2's job,
     which needs a known starting state.
   - Fix: the prologue runs `unset CLAUDE_CODE_PLUGIN_DIRS`, with a comment that
     a scenario wanting an inherited value exports one itself. Slice 2 can still
     do that with `CLAUDE_CODE_PLUGIN_DIRS=/elsewhere/dist/plugin run_claude`,
     or an `export` inside its scenario.
   - **Status**: FIXED. The candidate passes with and without the variable set
     in the runner.

### Minor Issues

1. **Unjustified `2>/dev/null` in the watchdog**
   - Location: `run_claude`.
   - Problem: three redirects were unjustified (`no-stderr-suppression`):
     - `wait "$watcher" 2>/dev/null` hid nothing. I probed it: a non-interactive
       `wait` on a killed job prints nothing.
     - `kill "$watcher" 2>/dev/null` hid the "No such process" error, which
       happens only when the watchdog has already fired.
     - The watcher's blanket `>/dev/null 2>&1` also hid its own `kill "$pid"`
       error.
   - Fix:
     - The watcher is now killed only when it has not fired, so that `kill`
       needs no redirect.
     - `wait` loses its redirect.
     - The redirect is narrowed to `sleep 10 >/dev/null 2>&1`, with the reason
       inline: killing the watcher orphans the sleep, and the orphan must not
       hold the caller's pipe open for 10 s.
     - `$pid` is renamed `$launch_pid` and made global for issue 2.
   - **Status**: FIXED.

2. **Stub fields and the doc comment**
   - Location: the `make_consumer` doc comment.
   - Note: rewritten as a variable list naming every field the stub records,
     including the new `pid` and `copy`, plus `$shim_dir` and `$launch_dir`.
   - **Status**: FIXED.

## Wrong-reason hunting — per question asked

- **argv, `$*` / unquoted `$@`**: caught. The results are `--foo a b|` and
  `--foo|a|b|` against `--foo|a b|`. A dropped argv records `|`.
- **syncs before exec, for a shim that execs first and never syncs**: caught, on
  both the copy-at-launch assertion and the regular-file assertion. The
  sync-after-run shim is caught only by the copy-at-launch assertion added in
  major issue 1.
- **exports, non-physical `<root>`**: now caught (major issue 3). `<root>` in
  the assertion is `$sandbox/my consumer`, with `$sandbox` taken from `pwd -P`.
- **CDPATH set empty rather than unset**: caught (`got ''`), because the stub
  reads `${CDPATH-<unset>}`, with no colon. A shim that leaves CDPATH alone is
  caught too (`got '/tmp'`), which proves the `/tmp` input reaches the stub.
- **Watchdog on a hang**: proven. With the stub mutated to `sleep 30`, each of
  the four tests failed with `the launcher ran past the 10 s watchdog`. The
  suite finished in 40.3 s, so neither the orphaned `sleep 30` nor the orphaned
  watcher sleep held the output pipe.
- **Sync's preconditions**: satisfied. The candidate shim runs the real
  `dogfood.sh sync` on the fixture and all four tests pass. The fixture has the
  manifest, `/dist/plugin/` git-ignored and committed, and a git repo.
- **Environment leak**: `CLAUDE_CODE_PLUGIN_DIRS` fixed (major issue 5);
  `CDPATH` and `git rev-parse --local-env-vars` were already unset; the stub
  comes ahead of the runner's PATH, so a real `claude` on it cannot be reached.
- **Whitespace, `my consumer`**: the space sits in a PATH entry, in the stub's
  embedded paths (inside double quotes in the heredoc) and in the `cd`. All pass
  with the candidate.
- **Harness**: a self-contained copy. `fail`, `assert_eq`, `assert_file` and
  `assert_absent` are copied from `dogfood-sync-test.sh`, and `assert_absent` is
  now used. `recorded`, `commit_all` and `run_claude` are all called. The `pwd`
  and `path` stub fields are unread in slice 1, but they belong to the shared
  stub fixture for slices 3 and 4.

## Mutation matrix (candidate shim from the slice Interfaces)

These are scratch runs only. Each mutation was written over `toolkit/bin/claude`
in place, and the original was restored by copying back the saved file. The
restore was checked with `cmp` against the saved copy (identical), sha256
`fb99eae9…1048e5` (unchanged) and mode 755.

| Candidate | Result |
|---|---|
| per Interfaces (`-ef` strip, `cd -P`/`pwd -P` root, `exec claude "$@"`) | all pass |
| same, runner has `CLAUDE_CODE_PLUGIN_DIRS` set | all pass |
| `claude "$@"; exit 0` (fork) | red: pid |
| no sync | red: copy at launch, regular file |
| sync after running claude | red: pid, copy at launch |
| logical root (`cd`/`pwd`) | red: exports |
| `root=$(git rev-parse --show-toplevel)` | red: exports |
| `root=$PWD` | red: exports |
| `exec claude "$*"` / `exec claude $@` | red: argv |
| `export CDPATH=` / CDPATH untouched | red: CDPATH |
| no export | red: exports (`<unset>`) |
| strip by name (`$e == dirname $self`) | all pass (intended) |
| `sleep 30` (hang) | red: watchdog in each test |

The last row but one shows that the symlinked PATH spelling does not bring slice
3 forward. `$0` carries the PATH entry's own spelling, so even a name-compare
strip removes it. Only a strip against the physical directory would loop, and
the watchdog would bound that.

## Fixes Applied

All in `tests/dogfood-launcher-test.sh`:

- prologue: `unset CLAUDE_CODE_PLUGIN_DIRS`, with a reason.
- harness: `assert_absent` copied from `dogfood-sync-test.sh`.
- `make_consumer`:
  - sets `$shim_dir` and `$launch_dir`;
  - the stub records `copy` (manifest present at start) and `pid` (`$$`);
  - doc comment rewritten.
- `run_claude`:
  - PATH uses `$shim_dir`, and the `cd` uses `$launch_dir`;
  - exposes `$launch_pid`;
  - watchdog redirects narrowed and justified as described in minor issue 1.
- argv scenario: adds the pid assertion.
- sync scenario: asserts the fixture has no `dist/` before the run, and that the
  copy was present when the next claude started.
- export scenario: reaches the shim through the `$sandbox/link` spelling and
  launches from `$sandbox/elsewhere`, with a comment saying why.

`toolkit/bin/claude`: no change. It is byte-identical to its state before the
review.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D4 sync on promotion (launch through the shim) | Covered | syncs before exec: copy present when the next claude starts |
| D8 loud sync failure | Not in slice 1 | slice 5 |
| D9 shim: root from its own location, sync, export, unset CDPATH, exec | Covered for slice 1 | argv plus pid, export (physical, launch-dir independent), CDPATH |

## Recommendations

- Slice 4 can set `launch_dir="$consumer/skills/demo"` instead of adding its own
  plumbing.
- Slice 2 exports its inherited value inside the scenario (or as an env prefix
  on `run_claude`). The suite-level unset is there to keep that test's starting
  state known.

# Deliverable review, Layer 1: code and tests

Job: `plans/2026-10-05-dogfood-drop-auto-sync`. Baseline: `outline.md`. Range:
`e444427^..4a1aad6`.

Scope: `toolkit/bin/claude`, `toolkit/install.sh` (the Next steps output),
`tests/dogfood-launcher-test.sh`, `tests/install-test.sh`, and the
assertion-helper change in ten more suites.

## Method

- Read the full range diff of every listed file, plus the current shim and
  launcher suite.
- Ran these suites in the foreground at HEAD. Each exited 0 with no `FAIL` line:
  `dogfood-launcher`, `install`, `check-version`, `citation`, `dist-tree`,
  `dogfood-pre-tool`, `dogfood-sync-refusal`, `dogfood-sync`, `version-guard`,
  `update-plugin-dev`, `self-release` and `release`.
- `shellcheck toolkit/bin/claude toolkit/install.sh tests/*.sh` is clean.
- Ran 16 shim mutants against a scratch copy of the launcher suite under
  `$TMPDIR/mut`, and one `install.sh` mutant under `$TMPDIR/mut2`. Results are
  below.
- Probed the shim directly with roots holding a space, a trailing newline, glob
  characters, a backslash and a leading dash, under `$TMPDIR/wsprobe`.

## Critical

None.

## Major

### 1. Nothing tests the order of the copy check and the 127 check

- **Location:** the checks are `toolkit/bin/claude:22-25` and `:29-32`. The
  scenarios that should pin the order are
  `tests/dogfood-launcher-test.sh:195-207` (missing copy) and `:333-349` (no
  next claude).
- **Axis:** test coverage and specificity.
- **What is specified:** the outline's decision 2 says "The check comes before
  the PATH strip". The build summary and this review's brief settle the
  consequence: with no copy *and* no other `claude`, exit 1 wins over 127.
- **What is tested:** the missing-copy scenario always has the stub on PATH, and
  the 127 scenario always has a copy. No scenario has both missing.
- **Probe:** mutant `order` moves the copy check below the `command -v claude`
  check. All 11 scenarios still pass (rc 0).
- **Failure scenario:**
  1. A later edit groups the pre-exec checks and puts the copy check last.
  2. A consumer on a fresh clone has no copy and no real `claude` on PATH
     outside the shim, for example a CI image or a new machine.
  3. They get `dogfood: no other claude on PATH` with exit 127 and go looking
     for a `claude` install. The remedy they need is `just dogfood`.
  4. The suite stays green.
- **The shipped code is correct.** A direct probe with neither a copy nor
  another `claude` exits 1 with the copy line. Only the guard against regression
  is missing.
- **Fix:** add one scenario. Remove the copy and set `path_exact` to the shim
  directory plus a `bash`/`dirname` tools directory, as the 127 scenario does.
  Assert rc 1, one stderr line naming `just dogfood`, and the absence of
  `dogfood: no other claude on PATH`.

## Minor

### 1. `-d` versus `-e` is not distinguished by any scenario

- **Location:** the check is `toolkit/bin/claude:22`. The scenario is
  `tests/dogfood-launcher-test.sh:195-207`, whose only negative case is
  `rm -r "$consumer/dist"`.
- **Axis:** test coverage, on a robustness edge case.
- **What is specified:** the outline says the shim refuses "When
  `<root>/dist/plugin` is not a directory".
- **Probe:** mutant `e_test` swaps `-d` for `-e`. Every scenario passes.
- **Failure scenario:**
  1. `dist/plugin` exists as a regular file. A stray redirect or a botched
     hand-copy can leave one.
  2. Under the mutant, the shim launches `claude` with `CLAUDE_CODE_PLUGIN_DIRS`
     naming a file.
  3. `session-start` compares an entry that cannot be entered "as spelled". That
     entry equals `<root>/dist/plugin`, so `session-start` stays silent too.
  4. The session runs with no plugin loaded, and nothing says so.
- **Fix:** a sub-case that creates `dist/plugin` as a file and asserts the same
  refusal.

## Verified clean

### Conformance

- The shim keeps everything outline decision 1 lists:
  - physical root resolution (`cd -P`);
  - the export of `CLAUDE_CODE_PLUGIN_DIRS=<root>/dist/plugin` over any
    inherited value;
  - the PATH strip;
  - exit 127 with its one line;
  - `exec claude "$@"`.
- The skip and the sync-failure path are gone with no leftovers. Nothing in
  `toolkit/bin/claude` calls `dogfood.sh` or reads the inherited variable.
- The missing-copy refusal matches decision 2:
  - one `dogfood:` line naming `just dogfood`;
  - exit 1;
  - placed before the export and the strip.
- Work item 1 is complete:
  - the fixture starts with a copy (`make_consumer` ends in
    `mkdir -p dist/plugin`);
  - both new scenarios exist;
  - all six named scenarios are dropped;
  - the 127 scenario's tool list is trimmed to `bash dirname`, the only external
    commands the shim runs.
- `install-test` asserts that the install output names `just dogfood`.
- The red evidence exists: `reports/red-launcher.txt` holds 9 `FAIL` lines, and
  `reports/red-install.txt` holds 1.

### Stale wording

No comment, test name or message describes launch-time syncing, the skip, or the
sync-failure path. Searched:

- the shim header;
- the launcher suite: all comments, the scenario titles and the
  `make_consumer`/`run_claude` docs;
- the comment in `install-test.sh`;
- `install.sh`'s header and echoes;
- `dogfood.sh`'s header and `session_start` comment;
- `release.just`'s `dogfood` doc line.

The new shim header's claim that `dogfood.sh` resolves its root physically
holds: `root_dir` uses `cd -P` (`toolkit/dogfood.sh:251-254`). So does the claim
that the hooks compare physical spellings: `session_start` resolves each entry
with `physical_path`.

### Tests red when their behaviour breaks

| Mutant | Scenario that reds |
|---|---|
| `sync` (sync before the check) | "does not sync, unset" and "missing copy" |
| `sync_after` (sync after the check) | "does not sync" (both forms) and the 127 scenario |
| `skip` (the old 0.9.0 condition) | "does not sync, unset" and "missing copy" |
| `nocheck` | "missing copy" |
| `mkdir` (create the copy instead of refusing) | "missing copy" |
| `exit2` | "missing copy" |
| `msg` (no `just dogfood`) | "missing copy" |
| `stdout` (message on stdout) | "missing copy" |
| `two_lines` | "missing copy" |
| `pwd` (check `$PWD/dist/plugin`) | "a subdirectory launch" and "from plugin-dev/bin" |
| `logical` (`cd` without `-P`) | "the shim exports the copy" |
| `keep_inherited` | "an inherited variable is overwritten" |
| `nostrip` | the watchdog |
| `exec_child` | the pid assertion |
| `install.sh` without step 4 | "install.sh's next steps create the copy" |

The fixture still vendors `dogfood.sh` and makes a syncable git repo. That is
what turns a reintroduced sync into a visible manifest instead of only a
non-zero exit, so it is not excess.

### Whitespace and odd paths in the shim

For each of these roots, the refusal and the export were both checked:

- `a b`
- a trailing newline
- `g[l]ob*`
- a backslash
- `-dash`

Each refused with exit 1 and the exact path when the copy was missing, and
exported the exact copy path when it was present. The `printf x` sentinel keeps
a trailing newline. The `-d` test and the message are quoted, and the message
starts with `dogfood:`, so a leading dash in the root is harmless.

### The here-string change

- **Complete.** No pipeline into `grep -q`, `grep -m`, `head`, `sed …q` or an
  early-exiting `awk` remains in `tests/` outside comments. The remaining pipes
  end in readers that consume all their input: `jq -e`, `grep -c`, `grep -o`,
  `grep -v`, `tr`, `sed`, and the `awk` in `doc-sync-test.sh`. Multi-line
  pipelines were checked as well.
- **Comments that still quote the pipe.** Two comments in
  `tests/release-test.sh:1602,1656` quote the old pipe. They describe
  `toolkit/release.sh`'s former ladder, which now uses a here-string at
  `release.sh:601`. These comments were outside the change and are left as is.
- **Semantics preserved.**
  - The patterns are still BRE, without `-F`.
  - `echo "$out" |` and `<<<"$out"` both end the input in a newline.
  - `printf '%s' |` differs only for an empty haystack. No `assert_contains` or
    `assert_not_contains` call has a needle that matches an empty line. A `$`
    anchor (`": pushed$"`, `self-release-test.sh:320-321`) matches the same as
    before, because grep treats an unterminated last line as a line.
- **The gitlink checks.** They capture first with `local x; x="$(git …)"` on two
  lines, so a failing `git` now aborts under `set -e` and is no longer masked by
  `local`.

### Prior review's dispositions

- **Major 1 (the skip's premise).** Moot as the build summary says. The shim
  header carries no skip rationale and no claim that the strip keeps agents off
  the shim.
- The prior review's other findings are about docs. They fall to Layer 2.

### `install.sh` step 4

- Printed under the same `changed` branch as steps 1-3. No quoting or backtick
  hazard: these are `echo` lines, not the unquoted heredoc.
- It follows step 3, which sets up the PATH that step 4's launch needs.

## Considered and dropped

- **No scenario sets the inherited variable to exactly the copy.** The old
  skip's case is now covered only by the list form. A sync conditioned on
  *equality* would slip through. That inverts the old condition and is
  contrived, so it is not raised.
- **A root containing `:`.** It splits `CLAUDE_CODE_PLUGIN_DIRS` into two
  entries. This predates the range, and the variable's format imposes it.
- **A root containing a newline.** It makes the refusal two physical lines, not
  one. The path is absurd, and the root is still printed exactly.
- **The launcher suite's header.** It says the suite tests "what it hands the
  next claude", and the refusal hands nothing. Too small to raise.
- **Step 4 says "launch claude from the repo root".** The shim resolves the root
  from its own location, so any directory where direnv has put `plugin-dev/bin`
  on PATH works. The wording matches `session-start`'s remedy and the project
  voice. Not an error.
- **Historical `Item 1.2`/`N1` comments in `release-test.sh`.** These were
  outside the range.

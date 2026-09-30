# Review: Item 2.1 slice 4 — test review (RED, mutation-proven)

**Scope**: the two new scenarios in `tests/dogfood-launcher-test.sh`
(`git diff`), and the RED report `reports/item-2-1-s4-red.md`.
`toolkit/bin/claude` was touched only by mutations. Each one was restored by the
inverse exact-string replacement. **Date**: 2026-09-30 **Mode**: review + fix

## Summary

Both tests are real evidence. Each reds on its own assertion under a mutation of
my own that differs from the RED report's. The RED report's claims hold. One
defect is fixed: the plugin-dev/bin test's expected PATH was not robust to the
runner's PATH. When the runner's PATH held an empty or `.` entry, the test
redded against a correct shim. From `plugin-dev/bin`, such an entry names the
shim too, and the shim rightly drops it. The subdirectory test adds nothing
against a `git rev-parse --show-toplevel` root. A git-first hybrid passes the
whole suite. The fix for that belongs to slice 1's scenario, so it is recorded
below as out of scope, with a verified one-line fix.

**Overall Assessment**: Ready

## Mechanical check

The suite was run in the foreground against the HEAD SUT.

- Before the fix, with this runner's PATH: green, about 1.7 s.
- Before the fix, with the runner's PATH varied (`$PATH:`, `$PATH::`,
  `.:$PATH`): 1 FAIL each, in
  `a launch from plugin-dev/bin drops the empty entry`. The expected value kept
  the runner's empty or `.` entry; the recorded one had it dropped. With a
  duplicated `/usr/bin:/usr/bin` tail it was green.
- After the fix: green under all six variants (as-is, `$PATH:`, `$PATH::`,
  `.:$PATH`, duplicated tail, `:$PATH`). `bash -n` and `shellcheck` are clean.
  The suite is 285 lines.

### Mutation proofs, reproduced with different mutations

A scratch script made each mutation as one exact-string replacement, asserting a
single match. The swapped replacement reverted it. After each restore:

- a `grep -c` for the mutation text printed `0`;
- `git diff --quiet toolkit/bin/claude` exited 0.

The final suite run is green.

| # | Mutation | Target test | Result |
|---|---|---|---|
| M1 | `export CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin"` → `"$PWD/dist/plugin"` (sync is correct, export follows the launch directory) | subdirectory: the copy | red, `got '<sb>/my consumer/skills/demo/dist/plugin'`; the stub ran. Also reds `the shim exports the copy` (`got '<sb>/elsewhere/dist/plugin'`). |
| M2 | `bash "$root/plugin-dev/dogfood.sh" sync` → `cd -- "$root" && bash plugin-dev/dogfood.sh sync` (cd to the root to sync, never back) | subdirectory: did not change directory | red, `expected '…/skills/demo', got '<sb>/my consumer'`. It also reds the plugin-dev/bin test: after the `cd`, the empty entry is `<root>/claude`, not the shim, so it is kept (`got ':<sb>/stub:…'`). That is a side effect of the mutation. |
| M3 | `[[ "${entry:-.}/claude" -ef "$1" ]]` → `[[ -n "$entry" && "$entry/claude" -ef "$1" ]]` (the naive "skip empty entries" guard) | plugin-dev/bin drops the empty entry | red on all three assertions: the watchdog fired, `rec/path is not a regular file`, `got '<stub did not record path>'`. No other scenario reds. |

M1 reds the subdirectory copy assertion with a real wrong value, where the RED
report's mutation 1 only got the not-ran marker. The assertion therefore
compares values, not just whether the stub ran.

## Wrong-reason hunting

- **Is the recorded `$PWD` compared with the physical spelling?** Yes.
  `$sandbox` is `pwd -P`, so `$consumer` and
  `launch_dir="$consumer/skills/demo"` are physical. `run_claude`'s logical `cd`
  and bash's inherited `$PWD` therefore give the same string in the shim and in
  the stub. A macOS `/var` → `/private/var` symlink cannot make it flaky. As a
  result the test does not tell a logical `$PWD` apart from a physicalised one:
  a shim that ends with `cd -P .` would pass. No requirement states the logical
  spelling, so this is left unpinned.
- **Would a `git rev-parse --show-toplevel` root pass it?** Yes. From
  `<root>/skills/demo`, git's toplevel is the physical `<root>`. On that axis
  the subdirectory test adds nothing. What it adds is the `$PWD` assertion: M2
  and RED's mutation 2 red only there. Its copy assertion overlaps slice 1's
  launch from `$sandbox/elsewhere`, which catches `root=$PWD` too (M1, RED's
  mutation 1). Probes against the whole suite:
  - A pure `git rev-parse --show-toplevel` root reds only
    `the shim exports the copy`, because `elsewhere` is not a repo and the shim
    exits. Slice 1's review covered this case.
  - A git-first hybrid passes every scenario: git's toplevel when there is one,
    otherwise the shim's `../..`. See Major issue 2.
- **Is the plugin-dev/bin expected PATH exact and robust to the runner's PATH?**
  It was exact but not robust, and is now fixed (Major issue 1). The expected
  value is `"$stubdir:$runner_path"`, an exact string. `$runner_path` is the
  runner's PATH with only its absolute entries kept, and it is the same value
  the launch appends. An absolute entry can never be `-ef` the shim, since the
  sandbox is fresh, so every one of them must survive in order. Duplicates
  survive too, and the duplicated-tail variant proves it. The leading empty
  entry of `path_head` is the only one the test's claim is about.
- **Does the watchdog clean up?** Under M3 the shim re-execs itself through
  `./claude` in one pid, which is `$launch_pid`. The watchdog kills it and
  `wait "$watcher"` reaps the watcher that fired. After the run, `pgrep -af` for
  the sandbox path found no leftover shim, `dogfood.sh` or rsync process.
  `run_claude` clears `$sandbox/killed` on entry, and each scenario gets a fresh
  sandbox, so a fired watchdog cannot leak into a later scenario. This is the
  last scenario anyway.
- **Are `path_head` and `launch_dir` scoped per scenario?** Yes. `make_consumer`
  resets both (`launch_dir="$consumer"`, `path_head=""`), and both new
  scenarios, like every other one, start with it. The fix's
  `PATH="$runner_path"` is a prefix assignment on the function call, so it lasts
  only for `run_claude`. `runner_path`, `rest` and `entry` are suite-level
  scratch, in the same style as `left`/`stubs`/`entries` in the slice-3
  scenario, and no later scenario reads them.
- **Other shapes checked.**
  - Birth state: the prologue unsets `CLAUDE_CODE_PLUGIN_DIRS`, and the fixture
    has no `dist/`. The copy value can only come from the shim.
  - A bare negative: the plugin-dev/bin test pairs "the stub ran" with an exact
    PATH, not a "no empty entry" check.
  - Its counterpart `the shim keeps the rest of PATH as spelled` is the positive
    over the same `path_head`, differing only in the launch directory. The two
    together pin "drop an empty entry exactly when it names the shim".

## Issues Found

### Critical Issues

None.

### Major Issues

1. **The plugin-dev/bin test redded against a correct shim on some runners**
   - Location: `tests/dogfood-launcher-test.sh`,
     `a launch from plugin-dev/bin drops the empty entry`.
   - Problem: the expected value was `"$stubdir:$PATH"`, taken from the runner's
     PATH as it was. Launched from `plugin-dev/bin`, any empty or relative
     runner entry that resolves there (``, `.`) names the shim too. The shim
     drops it, as the interface requires ("every PATH entry whose `claude` is
     `-ef` itself"). A runner with a trailing `:` or a `.` on PATH saw a false
     red. Reproduced with `$PATH:`, `$PATH::` and `.:$PATH`.
   - Fix: the scenario builds `$runner_path` from the runner's absolute entries
     only, launches with `PATH="$runner_path" run_claude`, and expects
     `"$stubdir:$runner_path"`. A comment says why.
   - **Status**: FIXED. Green under all six runner-PATH variants. M3 and RED's
     mutation 3 still red it.

2. **No scenario rules out a git-first `<root>`**
   - Location: `the shim exports the copy` (slice 1), where
     `launch_dir="$sandbox/elsewhere"`.
   - Problem: take git's toplevel when the launch directory is in a repo,
     otherwise the shim's `../..`. That shim passes the whole suite. From
     `skills/demo` it gets the right root; from `elsewhere`, which is not a
     repo, it falls back. The interface pins `<root>` to the shim's physical
     `../..` alone.
   - Suggestion: add `git init -q "$sandbox/elsewhere"` after the `mkdir` in
     that scenario. I verified this on a scratch copy of the suite, since
     deleted. HEAD stays green, and the hybrid reds `the shim exports the copy`
     (`got '<stub did not record plugin_dirs>'`). The scenario's comment would
     then say "launched from outside the consumer, inside another repo".
   - **Status**: OUT-OF-SCOPE. It is slice 1's scenario, and this review's scope
     IN is the two new ones. The subdirectory test cannot catch the hybrid
     without making a nested repo inside the consumer, which would change what
     the sync copies. For the orchestrator to apply, or to fold into the slice 4
     code review.

### Minor Issues

None.

## Fixes Applied

- `tests/dogfood-launcher-test.sh`, plugin-dev/bin scenario:
  - `$runner_path` is built from the runner's absolute PATH entries, with the
    same `rest`/`${rest%%:*}` split the shim uses, and so whitespace-safe;
  - the launch is `PATH="$runner_path" run_claude`;
  - the expected value is `"$stubdir:$runner_path"`;
  - the comment gives the reason;
  - the SC2031 disable moves to the line that now reads the suite's own `PATH`.

`toolkit/bin/claude` is unchanged: `git diff --quiet` exits 0.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D4 / D8: `<root>` from the shim's location; the copy is exported from any launch directory | Covered for slice 4 | subdirectory copy assertion (M1, RED 1); the git-first hybrid gap is Major issue 2 |
| The launch directory is preserved | Covered | subdirectory `$PWD` assertion (M2, RED 2) |
| D9: an empty entry that names the shim is dropped, the rest kept as spelled | Covered | plugin-dev/bin test (M3, RED 3) paired with slice 3's keep-as-spelled test |

## Positive Observations

- The RED report's mutations are specific, and its claims about which other
  scenarios red matched what I saw.
- The plugin-dev/bin scenario reuses `path_head` and `launch_dir` with no new
  harness plumbing, as slice 1's review had set up for.

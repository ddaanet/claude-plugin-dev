# Review: Item 1.1/2 code review — a failed sync at launch says claude was not started

**Scope**: `toolkit/bin/claude` as changed by e77ca7d: the failed-sync path and
the header comment. Tests, docs and `toolkit/dogfood.sh` were not under review.
**Date**: 2026-10-03 **Mode**: review + fix

## Summary

The GREEN keeps the sync's status with `|| status=$?`, prints one `dogfood:`
line after the sync's own stderr, and exits with that status. The skip condition
from slice 1 is unchanged. The logic is correct under `set -euo pipefail`, and
it runs on bash 3.2. The one finding is that the line's wording did not match
the other `dogfood:` messages. That is fixed.

**Overall Assessment**: Ready

## Checks against the dispatch

- **The exit status is the sync's own.** `bash … sync || status=$?` captures the
  script's exit status. `exit "$status"` passes it through unchanged. The rsync
  scenario pins this with status 23, and the mutated-SUT run below confirms that
  pin is live.
- **How it interacts with `set -euo pipefail`.**
  - A command on the left of `||` is exempt from errexit, so a failing sync
    reaches the handler and does not kill the shim silently.
  - `local status=0` has no command substitution, so it cannot mask a status
    (SC2155 does not apply).
  - `local` inside the `if` is valid anywhere in a function body, bash 3.2
    included, and it scopes `status` to the branch that uses it.
  - No pipeline is involved.
- **bash 3.2 / macOS.** `((status != 0))`, `local`, `${VAR-}` and `[[ ]]` all
  exist in bash 3.2. The change adds no external command.
- **Ctrl-C during sync.** Bash's wait-and-cooperative-exit kills the shim with
  SIGINT before the handler runs, so no line is printed. That is the correct
  outcome for an interrupt the user started. Nothing is lost.
- **Wording, for both readers.**
  - For a human at a terminal, the line names the outcome (claude was not
    started) below the sync's own reason.
  - For an agent that ran `claude`, the line is purely descriptive. It names no
    flag, no path and no alternative launch route, so there is no escape hatch
    to read as an instruction to bypass the sync.
- **The header comment.** It reads in this order: what the shim does, what a
  failure does, when the sync is skipped, how `<root>` is found. That is one
  coherent description. The new sentence is accurate: the sync's stderr is not
  captured, the shim's line comes after it, and the status is the sync's.

## Issues Found

### Minor Issues

1. **The line used a different style from the other `dogfood:` messages**
   - Location: `toolkit/bin/claude`, failed-sync branch.
   - Note: the line was `` dogfood: sync failed, so `claude` was not started ``,
     with backtick-quoted `claude`, produced by escaped backticks inside double
     quotes. Every other `dogfood:` message spells claude bare: the shim's own
     `dogfood: no other claude on PATH`, and `dogfood.sh`'s
     `… launch claude through …`. Backticks are markdown, but this line goes to
     a terminal. They also forced escaping, the shellcheck SC2016 detour the
     GREEN report mentions.
   - Fix: the line is now a single-quoted literal,
     `dogfood: sync failed, so claude was not started`. The suite's
     `not_started_re` accepts `claude` delimited by whitespace, so both failure
     scenarios still pin the line.
   - **Status**: FIXED

## Mutated-SUT run

The shim was mutated once, in place, by exact string replacement:
`exit "$status"` became `exit 1`. This is the plausible wrong implementation
that drops the sync's status. Result of `bash tests/dogfood-launcher-test.sh`
against it: **red**, 1 failure.

    FAIL: a failed rsync keeps its status: the shim exits with rsync's status: expected '23', got '1'

The shim was restored by the inverse exact replacement, and
`git diff --stat -- toolkit/bin/claude` was empty afterwards. The run came
before the wording fix.

## Fixes Applied

- `toolkit/bin/claude`, failed-sync branch: the echo is now
  `'dogfood: sync failed, so claude was not started'`. It is single-quoted,
  without backticks, to match the other `dogfood:` messages.

Verification after the fix:

- `bash tests/dogfood-launcher-test.sh`: all scenarios passed.
- `shellcheck toolkit/bin/claude`: clean.
- `just precommit`: green, exit 0. No intermittent suite failure appeared.

## Requirements Validation

| Requirement (outline m3) | Status | Evidence |
|---|---|---|
| one `dogfood:` line saying `claude` was not started | Satisfied | the failed-sync branch prints one line |
| keeping the sync's own stderr | Satisfied | the sync's stderr is not redirected; the shim's line follows it |
| a non-zero exit | Satisfied, as the sync's own status | `exit "$status"`; the rsync scenario pins 23 |
| claude not started | Satisfied | `exit` comes before `exec` |

## Positive Observations

- The GREEN captures the status in the `||` form rather than `if ! …`, which
  would have reset `$?` to 0.
- The change is minimal: the slice-1 skip condition and the exec path are
  untouched.

## Recommendations

None in scope. The test-review report already noted that the launcher suite is
over the 400-line soft cap. That is for the m12 move and later slices.

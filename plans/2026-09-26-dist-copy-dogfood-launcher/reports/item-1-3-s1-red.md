# Item 1.3/1 RED

SUT: `session-start` routed in `main`, `session_start` is an empty function
(exit 0, no output); header comment lists it. Tests added to
tests/dogfood-test.sh before "unknown subcommand is usage". `shellcheck` clean.
Both runs use `</dev/null` for stdin. The silent test sets
`CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin"` as a prefix on `run_dogfood` (a
scratch check confirmed a function-call prefix reaches the child); the warn test
runs `unset CLAUDE_CODE_PLUGIN_DIRS` first. Suite total: 4 failure(s), all
`fail` assertions, no harness error.

## session-start warns when the variable is unset (4 assertions fail)
- stdout is one JSON object: not true over stdout ''
- systemMessage leads with ESC[0m and names the copy: not true over stdout ''
- hookEventName == "SessionStart": not true over stdout ''
- additionalContext names the copy: not true over stdout ''
- exit code 0 and empty stderr pass (the stub exits 0 silently).

## session-start is silent on the copy (passes against the stub)
Negative test: the inert stub's silence satisfies it (exit 0, empty stdout,
empty stderr), so it is not red here. Its discrimination is unproved until a
GREEN that always warns reds it; that mutation is owed at the later slice.

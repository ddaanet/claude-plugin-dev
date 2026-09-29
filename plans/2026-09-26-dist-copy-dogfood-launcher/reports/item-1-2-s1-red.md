# Item 1.2/1 RED

Added to tests/dogfood-test.sh (before "unknown subcommand is usage"): helper
`run_pre_tool` (jq-built payload on stdin) and two scenarios. `bash -n` and
`shellcheck` clean. SUT untouched; `pre-tool` answers usage, exit 2. Every
failure is an assertion (`fail`), not a harness error.

## pre-tool denies an Edit into the copy (7 assertions fail)
- exit code: expected '0', got '2'
- stderr empty: got 'usage: dogfood.sh sync|pre-tool|session-start'
- hookEventName: expected 'PreToolUse', got ''
- permissionDecision: expected 'deny', got ''
- reason contains denied path; additionalContext contains source path;
  systemMessage contains dist/plugin: output empty
- "systemMessage is one line" passes vacuously on empty output; it only bites
  once the object exists.

## pre-tool allows a source edit (2 assertions fail)
- exit code: expected '0', got '2'
- stderr empty: got the usage line
- stdout empty passes already (usage goes to stderr); exit code and stderr carry
  the red.

Suite total: 9 failure(s).

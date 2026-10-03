# Item 1.2/1 GREEN: pre-tool maps a jq failure to a non-blocking status

Change: `pre_tool` in toolkit/dogfood.sh. Both jq calls now end `|| exit 1`: the
payload read (`path="$(jq ... && printf x)" || exit 1`; under `set -e` the bare
assignment would exit with jq's own status) and the deny build
(`jq -nc ... || exit 1`). jq's stderr is untouched. The header comment states
the exit-1 mapping and why (exit 2 blocks a PreToolUse tool call; jq 1.6 exits 2
on a parse error). `sync` and `session-start` untouched.

## Order made to pass (tests in tests/dogfood-pre-tool-test.sh)

1. "pre-tool fails loudly on a payload jq cannot read" and "pre-tool maps a jq
   exit of 2 to a non-blocking status" — both fixed by the payload-read mapping.
2. "pre-tool maps a jq failure building the deny to a non-blocking status" —
   fixed by the deny-build mapping.

## Results

- `bash tests/dogfood-pre-tool-test.sh`: all scenarios passed.
- `just precommit`: green (full suite, no flake, no warnings reported).

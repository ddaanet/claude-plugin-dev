# Item 1.3/4 GREEN

Run in session by the orchestrator: the implementation is one guard.
`session_start` now opens with `command -v jq >/dev/null`; on a miss it prints
one static object with `printf` and exits 0. The object is single-quoted JSON
text whose `\u001b[0m` is a JSON escape, not a raw byte, and it carries
`.systemMessage` only: only the human can install jq. The check runs before
`root_dir` and the entry loop, so the copy check is skipped, as the Interfaces
line and the `(names-the-copy)` run require. jq's stderr is never redirected.
The comment above `session_start` states the jq-less branch.

## Order made to pass

1. `(unset)`: red on exit 127 and `jq: command not found`; green once the guard
   prints the static object.
2. `(names-the-copy)`: red on empty stdout, since the copy loop ran without jq
   and went silent; green with the same guard, which runs before the loop.

## Results

- `bash tests/dogfood-test.sh`: `all dogfood scenarios passed`.
- `shellcheck toolkit/dogfood.sh`: clean.
- `PATH=/nonexistent bash toolkit/dogfood.sh session-start | jq -c .` parses to
  the one-key object.

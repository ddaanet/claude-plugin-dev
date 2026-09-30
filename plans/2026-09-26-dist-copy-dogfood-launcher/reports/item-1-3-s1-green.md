# Item 1.3/1 GREEN

Implemented `session_start` in toolkit/dogfood.sh, one test at a time.

## Order made to pass

1. `session-start warns when the variable is unset` (was red on 4 assertions):
   `session_start` takes `<root>` from `root_dir`, builds one object with
   `jq -nc --arg`: `.systemMessage` opens with `\u001b[0m` and names
   `<root>/dist/plugin` plus the remedy (launch through `plugin-dev/bin/claude`
   from the repo root); `.hookSpecificOutput` carries `hookEventName` and an
   `additionalContext` stating as fact that the session does not load the copy.
   First attempt broke shellcheck (an apostrophe inside the single-quoted jq
   program); reworded, no logic change.
2. `session-start is silent on the copy`: stayed green. The whole-string
   equality guard (`CLAUDE_CODE_PLUGIN_DIRS == <root>/dist/plugin`) exits 0
   silently; its discrimination is now real, since the function warns otherwise.

Out of scope and absent: splitting on `:`, entry normalisation, the jq-less
object, no `command -v jq`.

## Results

- `bash tests/dogfood-test.sh`: all dogfood scenarios passed.
- `shellcheck toolkit/dogfood.sh`: clean.
- `just lint`: no such recipe in this repo's justfile; `just precommit` runs in
  the commit hook (shellcheck, bash -n, all tests).

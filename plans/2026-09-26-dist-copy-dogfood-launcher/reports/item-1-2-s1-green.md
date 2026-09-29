# Item 1.2/1 GREEN

Added a `pre-tool` subcommand to `toolkit/dogfood.sh`: reads
`.tool_input.file_path` with jq, denies a path under `<root>/dist/plugin/`
(string compared as given against the physical `<root>`), otherwise exits 0 with
no output. The deny object is built with `jq --arg`: verdict on
`permissionDecisionReason` (names the path, no escape hatch), the source path on
`additionalContext`, one line on `systemMessage`. Header comment and usage
updated.

- `tests/dogfood-test.sh`: all scenarios pass, including both new pre-tool ones.
- `just format-docs` ran; `just precommit` green (full suite, first run). No
  intermittent failures in release-test or version-guard-test.
- Out of scope, not implemented: notebook_path, sibling-prefix/outside cases,
  symlink resolution, no-jq path, session-start.

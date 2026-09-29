# Item 1.2/2 GREEN

Run in session by the orchestrator. The change is one jq expression, too small
to dispatch. `pre_tool` now reads the edited path as
`.tool_input.file_path // .tool_input.notebook_path // ""`, the Interfaces'
expression, with a comment on why: NotebookEdit names its target
`notebook_path`.

`pre-tool denies a NotebookEdit into the copy` passes, and so does the rest of
`bash tests/dogfood-test.sh` (`all dogfood scenarios passed`). `shellcheck` is
clean. `just precommit` runs as the pre-commit hook on the slice commit.

# Item 1.2/2 RED

Edited only tests/dogfood-test.sh (515 lines). `bash -n` and `shellcheck` clean.

Refactor: `run_pre_tool <tool> <field> <path>` (payload via jq); 1.2/1's deny
assertions moved unchanged into `assert_denied <label> <root>`, used by both the
Edit and the NotebookEdit test.

Result: the 1.2/1 Edit test and all other scenarios pass. The new
`pre-tool denies a NotebookEdit into the copy` fails on its assertions (empty
stdout, since committed `pre-tool` reads only `.tool_input.file_path`; exit code
and stderr assertions pass):

```
=== pre-tool denies a NotebookEdit into the copy ===
FAIL: deny stdout is one JSON object: ... is not true over stdout ''
FAIL: deny hookEventName: ... is not true over stdout ''
FAIL: deny permissionDecision: ... is not true over stdout ''
FAIL: deny reason names the denied path: ... is not true over stdout ''
FAIL: deny additionalContext names the source path: ... is not true over stdout ''
FAIL: deny systemMessage names the copy: ... is not true over stdout ''
FAIL: deny systemMessage is one line: ... is not true over stdout ''
7 failure(s)
```

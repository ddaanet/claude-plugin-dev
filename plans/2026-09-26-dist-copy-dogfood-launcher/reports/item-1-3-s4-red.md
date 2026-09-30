# Item 1.3/4 RED: a missing jq on systemMessage only

Added to tests/dogfood-test.sh, after the 1.3/3 scenarios: the scenario
`session-start reports a missing jq on systemMessage only`. `shellcheck` clean.
toolkit/dogfood.sh is untouched. `make_jqless_bin` is reused as is; it holds
every command `session-start` needs (`bash`, `dirname`, `mkdir`, `cat`).

The payload is built with the real jq before the PATH narrows; stdout is read
with the suite's own jq after the run. The precondition (`command -v jq` fails
under the jq-less PATH) passes.

The scenario runs twice, labelled `(unset)` and `(names-the-copy)`. The second
pins the Interfaces line "the copy check is skipped" (outline decision 7: the
message is static, so the check that needs jq is not run): with the variable
naming `<root>/dist/plugin`, where the check would be silent, the static object
still appears. The variable is exported only for that run and unset after.

Each run asserts exit 0, empty stderr, stdout one JSON object, `.systemMessage`
a string starting with ESC `[0m`, containing `jq`, and `.hookSpecificOutput`
absent.

## Per-test output (against the committed SUT)

10 failures, all from this scenario; every other scenario passes.

- `(unset)`:
  - `FAIL: ... (unset) exit code: expected '0', got '127'`
  - `FAIL: ... (unset) prints nothing on stderr: expected '', got '.../dogfood.sh: line 144: jq: command not found'`
  - `FAIL: ... (unset): stdout is one JSON object: ... is not true over stdout ''`
  - `FAIL: ... (unset): systemMessage opens with an ANSI reset: ... over stdout ''`
  - `FAIL: ... (unset): systemMessage names jq: ... over stdout ''`
  - `FAIL: ... (unset): hookSpecificOutput is absent: ... over stdout ''`
- `(names-the-copy)`: the script exits 0 silently (the copy is named), so exit
  code and stderr pass and the four stdout checks red on empty stdout:
  - `FAIL: ... (names-the-copy): stdout is one JSON object: ... over stdout ''`
  - `FAIL: ... (names-the-copy): systemMessage opens with an ANSI reset: ...`
  - `FAIL: ... (names-the-copy): systemMessage names jq: ...`
  - `FAIL: ... (names-the-copy): hookSpecificOutput is absent: ...`

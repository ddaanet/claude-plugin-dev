# Item 2.2 slice 1 RED

Added to `tests/update-plugin-dev-test.sh`, lines 369-387, inside scenario
"install.sh: wires into an existing settings.json without replacing it", after
the version-guard assertion. SUT (`toolkit/install.sh`) untouched.

Assertions (jq with `--arg`, exact command-string comparison):

- `install adds the pre-tool hook once` - count of PreToolUse entries with
  matcher `Write|Edit|NotebookEdit` holding the exact pre-tool command.
- `install adds the session-start hook once` - count of SessionStart entries
  with no `matcher` key holding the exact session-start command.
- `the commands quote the project dir` - "pre,session" counts of the exact
  literal-`"${CLAUDE_PROJECT_DIR}"` commands across all entries; expects `1,1`.

Run: `bash tests/update-plugin-dev-test.sh` (shellcheck clean).

```
FAIL: install adds the pre-tool hook once: expected '1', got '0'
FAIL: install adds the session-start hook once: expected '1', got '0'
FAIL: the commands quote the project dir: expected '1,1', got '0,0'
3 failure(s)
```

All three are count mismatches (0 vs 1), not jq errors (jq runs on a valid
settings.json; the install's exit-code assertion passed). Every pre-existing
assertion still passes; no other FAIL lines.

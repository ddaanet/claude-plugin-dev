# Item 2.2/5 RED — a fresh settings.json carries all three hooks

Test file: tests/update-plugin-dev-test.sh, scenario
`install.sh: no ref resolves the newest dist tag`. Added: an anchor that the
fixture has no settings.json before install, then two assertions after the first
install. shellcheck clean. SUT untouched.

## Run: bash tests/update-plugin-dev-test.sh (2 failures, both new)

- `a fresh settings.json carries version-guard and the pre-tool hook under PreToolUse`
  FAIL on assertion: expected `Write|Edit=<vg>` +
  `Write|Edit|NotebookEdit=<pre-tool>`, got only
  `Write|Edit=bash ${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh`. The
  version-guard half matches; the pre-tool entry is absent.
- `a fresh settings.json carries the session-start hook with no matcher` FAIL on
  assertion: expected `none=<session-start cmd>`, got `''`.
- Anchor (no settings.json before install): passes.
- Every other assertion in the suite passes.

## Mutation proof

None needed: both new assertions red against the current SUT.

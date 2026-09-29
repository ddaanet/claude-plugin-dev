# Item 1.1/1 RED

Files: `tests/dogfood-test.sh` (new), `toolkit/dogfood.sh` (inert stub,
`exit 0`). `bash -n` and `shellcheck` clean on both. Nothing committed;
`tests/dist-tree-test.sh`, `CLAUDE.md`, `justfile` untouched.

Fixture: `make_consumer` (sandbox with `my consumer` repo, plugin.json,
`.gitignore` `/dist/plugin/`, tracked `skills/demo/SKILL.md`, vendored
`plugin-dev/dogfood.sh`), `commit_all`, `run_dogfood` (cwd = `$sandbox`,
`CLAUDE_PROJECT_DIR` = `$sandbox/elsewhere`; sets `rc`, `out`, `err`).

Each test fails on an assertion; the harness ran all four to completion (12
failures, exit 1).

- `sync copies a tracked file`: FAILS on the regular-file assertion and on `cmp`
  (no copy made).
- `sync leaves out an ignored file and .git`: FAILS on "the copy exists"
  precondition (`skills/demo/SKILL.md` absent); the two absence assertions pass
  vacuously on the stub and become live once GREEN copies.
- `sync resolves the root from its own location`: FAILS on the regular-file
  assertion at `<consumer>/dist/plugin/`; the cwd/`CLAUDE_PROJECT_DIR` absence
  checks pass vacuously.
- `unknown subcommand is usage`: FAILS on exit code (expected 2, got 0) and on
  stderr naming `sync`, `pre-tool`, `session-start`, for both `bogus` and no
  argument.

## Output

```text
=== sync copies a tracked file ===
FAIL: sync copies a tracked file: '$TMPDIR/my consumer/dist/plugin/skills/demo/SKILL.md' is not a regular file
FAIL: sync copies a tracked file: copy bytes differ from the source
=== sync leaves out an ignored file and .git ===
FAIL: sync leaves out an ignored file: the copy exists: '$TMPDIR/my consumer/dist/plugin/skills/demo/SKILL.md' is not a regular file
=== sync resolves the root from its own location ===
FAIL: sync resolves the root from its own location: '$TMPDIR/my consumer/dist/plugin/skills/demo/SKILL.md' is not a regular file
=== unknown subcommand is usage ===
FAIL: unknown subcommand exit code: expected '2', got '0'
FAIL: unknown subcommand usage names sync: output did not contain 'sync'
  --- output ---

  --------------
FAIL: unknown subcommand usage names pre-tool: output did not contain 'pre-tool'
  --- output ---

  --------------
FAIL: unknown subcommand usage names session-start: output did not contain 'session-start'
  --- output ---

  --------------
FAIL: no subcommand exit code: expected '2', got '0'
FAIL: no subcommand usage names sync: output did not contain 'sync'
  --- output ---

  --------------
FAIL: no subcommand usage names pre-tool: output did not contain 'pre-tool'
  --- output ---

  --------------
FAIL: no subcommand usage names session-start: output did not contain 'session-start'
  --- output ---

  --------------

12 failure(s)
```

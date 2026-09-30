# Item 1.3/2 GREEN: session-start matches any entry naming the copy

## Order made to pass

1. `session-start matches the copy among several entries`: split
   `CLAUDE_CODE_PLUGIN_DIRS` on `:` by parameter expansion (no word splitting,
   so the space in the root survives), compare each entry whole.
2. `session-start matches the copy with a trailing slash`: an entry that is an
   existing directory is resolved with `cd -- … && pwd -P`, guarded by
   `[[ -d ]]`; any other entry has trailing slashes stripped.
3. `session-start matches the copy through a symlink`: covered by the same
   resolution.

The implementation was written in one edit; the three tests were then run
together, all passing. No test file was edited.

## Results

- `bash tests/dogfood-test.sh`: all scenarios passed, including the 1.3/1 tests.
- `shellcheck toolkit/dogfood.sh`: clean.
- Comment above `session_start` restated: whole-entry match, physical resolution
  of existing directories, literal compare otherwise.

## Precommit

The commit hook runs `just precommit`; its warnings, if any, are not addressed
here.

# Item 1.1/6 GREEN

`toolkit/dogfood.sh`: `sync_copy` now calls two new helpers before mktemp, the
trap or any write.

- `require_manifest`: refuses unless `<root>/.claude-plugin/plugin.json` is a
  file. One `dogfood:` line naming the path, exit 1.
- `require_ignored_copy`: `git -C "$root" check-ignore -q dist/plugin/`
  (trailing slash). Status 0 passes, 1 refuses with a line naming
  `/dist/plugin/`, any other status (128) exits with that status and git's own
  stderr, so a git error is not read as "not ignored".

## Results

- `tests/dogfood-test.sh`: all scenarios pass, including both new refusals and
  the already-green git-failure test.
- `just format-docs`: ran; `just precommit` (unsandboxed): green through
  `dogfood-test.sh`, no intermittent failures.
- `tests/dogfood-test.sh` is over the 400-line cap (split decision at end of
  Phase 1, per the RED report).

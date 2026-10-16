# 2026-10-16 — The dogfood shim sets its variable and PATH unconditionally

A review of the previous day's change, which made the shim append the copy's
`bin/` to PATH only when the copy existed, found the probing was not needed and
the no-copy handling in the wrong place. This entry supersedes the probing
described in [the shim-on-PATH entry](2026-10-16-dogfood-shim-plugin-bin.md);
that entry stays as written.

## What changed

- `toolkit/bin/claude` exports `CLAUDE_CODE_PLUGIN_DIRS=<root>/dist/plugin` and
  appends `<root>/dist/plugin/bin` to the PATH it execs `claude` with, both
  unconditionally, copy or no copy. A PATH entry that names a missing directory
  is inert, so neither the copy nor `bin/` is probed. The walk that skipped an
  entry already on PATH is gone, since a repeat is inert too; a nested launch
  carries the entry twice, which is kept. The one remaining walk strips the
  shim's own entries. The ordering is unchanged: the append follows the strip
  and the check for another `claude`, so the 127 path is as before.
- The shim is silent. It no longer warns about a missing copy, and no longer
  leaves an inherited variable as it came. The facts behind that were probed on
  CC 2.1.301: claude starts cleanly with a plugin directory that does not exist
  (exit 0, answer on stdout, empty stderr, one load error under `/plugin`), and
  a headless `/reload-plugins` after the directory was created loaded it, 16
  plugins and one error before, 17 and none after. So the first `just dogfood`
  of a running session needs `/reload-plugins` and no relaunch. The interactive
  `/reload-plugins` was not run.
- `dogfood.sh session-start` carries the warning the shim dropped. It used to
  exit as soon as an entry of `CLAUDE_CODE_PLUGIN_DIRS` named the copy, before
  its no-copy check, so a shim session with no copy, or with a regular file at
  `dist/plugin`, got no warning. After a match it now tests that the copy is a
  directory, and if not tells the user to run `just dogfood` and then
  `/reload-plugins`, with no relaunch. The agent gets the fact and no command.
- The user-facing messages no longer name `plugin-dev/bin/claude`. The user's
  control is `direnv allow`, which loads `.envrc` and puts the shim first on
  PATH, and then launching `claude`. A session that does not load the copy is
  told to run `just dogfood` if there is no copy, then `direnv allow` in the
  plugin root and relaunch `claude`. The manual's setup section still says where
  the shim lives.
- Tests: the exec suite pins a silent launch with no copy that exports the path
  and replaces an inherited value. `tests/dogfood-session-start-test.sh` pins
  the matched-entry no-copy message for an absent copy and for a regular file at
  `dist/plugin`, and the new wording. The session-start suite outgrew the
  400-line cap and its warning scenarios moved to
  `tests/dogfood-session-warn-test.sh`.
- `toolkit/docs/dogfood.md`, `toolkit/README.md`, `docs/references/dogfood.md`,
  `docs/references/dogfood-sync.md`, `docs/design.md` and the CLAUDE.md layout
  bullet describe the above in the present tense.

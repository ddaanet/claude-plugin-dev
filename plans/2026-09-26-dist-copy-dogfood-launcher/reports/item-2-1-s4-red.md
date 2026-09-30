# Item 2.1 slice 4 RED

Two tests added to `tests/dogfood-launcher-test.sh`. The SUT already has the
behaviour, so both pass against HEAD and each is proved by mutation. The SUT is
identical to HEAD at the end (`git diff --quiet toolkit/bin/claude` succeeds).

## Tests

- `a subdirectory launch resolves the root`: launch_dir `<root>/skills/demo`;
  asserts the recorded `CLAUDE_CODE_PLUGIN_DIRS` is `<root>/dist/plugin` and the
  recorded `$PWD` is `<root>/skills/demo`.
- `a launch from plugin-dev/bin drops the empty entry`: launch_dir
  `<root>/plugin-dev/bin`, `path_head=":$shim_dir:$stubdir"`; asserts the stub
  ran and its recorded PATH is exactly `$stubdir:$PATH` (no leading empty
  entry).

Against HEAD: suite green; `bash -n` and `shellcheck` clean.

## Mutation proof

Each mutation was a `sed` exact replacement in `toolkit/bin/claude`, restored by
the inverse replacement; after each, grep for the mutation text gave 0 hits and
`git diff --quiet toolkit/bin/claude` succeeded; the final suite run is green.

1. Root from the launch directory. `cd -P -- "$here/../.."` to
   `cd -P -- "$PWD"`. Reds `a subdirectory launch resolves the root: the copy`
   (expected `<root>/dist/plugin`, got `<stub did not record plugin_dirs>`) and
   `...: the shim did not change directory` (`<stub did not record pwd>`). It
   also reds `the shim exports the copy` and the plugin-dev/bin test, since the
   sync fails without `<root>`.
2. Directory change before exec. `exec claude "$@"` to
   `cd "$root" && exec claude "$@"`. Reds only
   `a subdirectory launch resolves the root: the shim did not change directory`
   (expected `.../my consumer/skills/demo`, got `.../my consumer`).
3. Empty entry kept. `[[ "${entry:-.}/claude" -ef "$1" ]]` to
   `[[ "$entry/claude" -ef "$1" ]]`. Reds
   `a launch from plugin-dev/bin drops the empty entry`: watchdog kill
   (`the launcher ran past the 10 s watchdog`), the stub never ran
   (`rec/path is not a regular file`), and the PATH assertion got
   `<stub did not record path>`. No other scenario reds.

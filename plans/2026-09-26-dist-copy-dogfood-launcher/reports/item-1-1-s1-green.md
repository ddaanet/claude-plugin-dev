# Item 1.1/1 GREEN

`toolkit/dogfood.sh` implements `sync` (decision 2's pipeline: NUL-separated,
`/`-anchored ignore list from
`git ls-files -z -o -i --exclude-standard --directory`, hard excludes `.git` and
`/dist/plugin/`, `rsync -a --delete --delete-excluded --from0 --exclude-from=-`)
and the usage path (exit 2, stderr naming `sync`, `pre-tool`, `session-start`).
Root is the `pwd -P` parent of the script's directory. rsync's stderr is not
redirected. Bash 3.2 and BSD safe: a `while read -d ''` loop, no `sed -z`,
`readlink -f` or `mapfile`.

Gate bookkeeping: `dogfood.sh` in `tests/dist-tree-test.sh`'s `expected`;
`CLAUDE.md` Layout bullet; `justfile` `precommit` gained `shellcheck` on
`toolkit/dogfood.sh`, `bash -n` on `tests/dogfood-test.sh`, and
`bash tests/dogfood-test.sh`.

`bash tests/dogfood-test.sh`: all four scenarios pass.

## Mutation proof

Each mutation an exact string replacement in `toolkit/dogfood.sh`, restored by
the inverse replacement, restore asserted equal to the original in the same
script, and grep confirmed each original line present once afterwards.

- Drop the `.git` hard exclude (`printf '%s\0' '.git' '/dist/plugin/'` to
  `printf '%s\0' '/dist/plugin/'`): red,
  `FAIL: sync leaves out .git: '…/dist/plugin/.git' exists`. Restored: green.
- Drop the ignore-list feed (`--directory |` to `--directory | head -c 0 |`):
  red, 5 failures including
  `FAIL: sync leaves out an ignored file: '…/dist/plugin/build.log' exists`; the
  exit-code failures are 141 (SIGPIPE from the truncated pipe), a side effect of
  the mutation form. Restored: green.

## Gate

`just precommit` green (ok) after staging the new files: `dist-tree-test.sh`
reads the index, so it fails until `toolkit/dogfood.sh` is `git add`ed. No
`release-test.sh` or `version-guard-test.sh` failure occurred.

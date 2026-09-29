# Item 1.1/1 code review

Scope: `toolkit/dogfood.sh`, the `tests/dist-tree-test.sh` entry, the
`CLAUDE.md` Layout bullet and the `justfile` `precommit` lines in the HEAD
commit. `tests/dogfood-test.sh` content and later slices' features are out of
scope.

## Findings

### Major — a git failure ran rsync on an empty exclude list (fixed)

The ignore list reached rsync through a pipe:
`{ git ls-files … | while …; printf '.git' '/dist/plugin/'; } | rsync …`. When
`git ls-files` fails, `set -e` inside the group's subshell exits it before the
hard excludes are printed. rsync keeps running on the partial list, which is
empty. pipefail does surface git's 128, but only after rsync has finished.

Reproduced on a root with no repository: two syncs exit 128 each, and the copy
nests into itself as `dist/plugin/dist/plugin/dist/plugin`. In a real repo where
git fails for another reason, such as `safe.directory` ownership, the same path
would also copy `.git` and every ignored file.

Fix: the list is now written in full to a `mktemp` file under `$TMPDIR` by
`git … | while … >"$excludes"`. That pipeline is a top-level statement, so
pipefail and `set -e` stop the script on a git failure before `mkdir` and before
rsync. The hard excludes are then appended, and rsync reads the file through
stdin (`--exclude-from=- <"$excludes"`), so D2's flag set is unchanged. An
`EXIT` trap removes the file. `excludes` is deliberately global, with a comment
saying why: under `set -u`, a `local` would be unset by the time the trap fires
after a normal return. `mkdir -p` moved below the list build, so a failed list
leaves `dist/` untouched, the way the Interfaces require refusals to.

Verified after the fix:

- On a root with no repository, sync exits 128 with git's own message, creates
  no `dist/` and leaves no temp file.
- A stub `rsync` that exits 23 makes sync exit 23, with the stub's stderr line
  shown once.
- A real sync exits 0 with empty stdout and leaves no temp file.
- `TMPDIR` holding a space works.
- A relative invocation with `CDPATH` set works.

This also shapes slice 1.1/5: the pattern-character check has to see the whole
list before rsync starts, and the list now exists as a file at that point.

### Minor — `root_dir` could resolve to `/` (fixed)

`root_dir` runs inside `$(…)`, where bash turns errexit off. If the first
`cd "$(dirname …)"` failed, `here` came out empty, and `(cd "/.." && pwd -P)`
printed `/`. The function still returned 0, so `sync` would have mirrored `/`
into `/dist/plugin/` with `--delete`. That needs an unreadable or vanished
script directory, which is unlikely, but the cost would be catastrophic. The two
steps are now chained with `&&`, so a failed `cd` fails the call, and the
caller's `root="$(root_dir)"` assignment then aborts under `set -e`. The
two-step physical resolution is kept on purpose. A single logical `cd dir/..`
would take the lexical parent of a symlinked `plugin-dev/` rather than the
physical parent the Interfaces specify.

### Minor — `unset CDPATH` was scoped to one subshell (fixed)

It sat inside `root_dir`, so it only reached that command-substitution subshell.
It now sits at script level beside `set -euo pipefail`, where it also covers the
`cd`/`pwd -P` resolution that 1.2 `pre-tool` adds.

## Checked, no change

- **rsync status reaches the caller unaltered.** Before the fix, pipefail
  already passed the rightmost non-zero status, which is rsync's. After the fix
  rsync is a plain statement under `set -e`. The `EXIT` trap's `rm -f` does not
  change the exit status.
- **Portability to bash 3.2 and BSD.** The script uses `read -r -d ''`,
  `printf '\0'` and `mktemp` with an explicit template, which BSD requires. It
  avoids `sed -z`, `readlink -f`, `mapfile` and `wait` on a process
  substitution. Whether macOS rsync handles `--from0` is the outline's own open
  risk and is not reviewable here.
- **Whitespace and NUL safety.** The pipeline is NUL-delimited from end to end.
  Every entry is anchored with a leading `/`, so no entry can start with `#`,
  `;`, `+ ` or `- ` and be read as a comment or a rule prefix by
  `--exclude-from`.
- **Layout convention.** `main` comes first, then `usage`, `sync_copy` and
  `root_dir` in call order. `main "$@"` is last.
- **Comment accuracy.** The header is accurate. The `sync_copy` comment was
  extended to cover the list-first order and the exit status. The `root_dir`
  comment now states the errexit reason.
- **Bookkeeping.** The `dist-tree-test.sh` entry is in alphabetical order. The
  `justfile` lines add shellcheck for the script, `bash -n` for the suite and
  the suite run itself. The `CLAUDE.md` bullet is correct for this slice, and
  Item 3.6 owns its final shape.

## Recommendation (out of scope, not applied)

`tests/dogfood-test.sh` has no case for a git failure. A later test or slice
could pin it: a fixture root that is not a git repo should make sync exit
non-zero, with no `dist/` created. The pre-fix code creates `dist/` and nests
the copy inside itself, so such a test would be red against it.

No mutation run was made. The fix was verified by the direct probes above.

## Gates

- `bash tests/dogfood-test.sh`: all four scenarios passed.
- `just precommit`, run unsandboxed: exit 0. It covered shellcheck, `bash -n`,
  `_import-check`, and the version-guard, check-version, release, self-release,
  update-plugin-dev, dist-tree, docs, doc-sync, citation and dogfood suites.

## Refactor flagged

None.

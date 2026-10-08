# Review fixes: dogfood 0.9.2

Fixed M1, M2, m1, m2, m4 and m5 (6 of 6). `toolkit/dogfood.sh` is unchanged
(`git diff --stat -- toolkit/dogfood.sh` prints nothing; `cmp` against the saved
original is identical). Red outputs: `reports/red-review-fixes.txt`.

## M1: uninitialised-submodule guard (tests/dogfood-sync-test.sh)

New scenario "an uninitialised submodule is copied empty and not entered": a
gitlink `bare sub` added then `submodule deinit -f`'d. Preconditions asserted
(mode 160000, no `.git`). Sync must exit 0 with empty stderr, copy the rest of
the tree, and carry `bare sub` into the copy as an empty directory.

`run_dogfood` in this suite now runs the script under `timeout 20` when
`timeout` exists, so a runaway recursion fails an assertion (rc 124) instead of
hanging the suite. Without `timeout` (stock macOS) the hang stands.

Red: line 97 replaced by `:` gives rc 124 and 3 FAILs (exit code, rest of tree
not copied, empty directory missing). Green after restore.

## M2: sibling submodules (tests/dogfood-sync-test.sh)

The existing submodule fixture gained `tail sub`, a sibling that sorts after
`sub` (ignores its own `build/`, tracks `tool.md`). The two existing assertion
loops now cover `sub`, `sub/inner` and `tail sub`: `tool.md` copied, `build` and
`.git` absent.

Red: the literal mutation of line 79 (remove `local`) turns the line into
`dir=... ignored staged entry`, which runs `ignored` as a command. Every sync
then dies with rc 127, so it fails the suite for the wrong reason and proves
nothing about siblings; the first six lines are recorded as such. The mutant
that exercises the finding is `dir="$1" prefix="$2"; local ignored staged entry`
(the state a dropped `local` shares between levels). It fails exactly one
assertion: `tail sub/build is left out: ... exists`. Green after restore.

Not done: the review also asked for a root tracked file sorting after the
gitlinks. It cannot discriminate (rsync copies tracked files whatever the
exclude list holds), so it was left out rather than added as decoration.

## m1: errexit on the `-s` listing (tests/dogfood-sync-refusal-test.sh)

New scenario "a git failure on the gitlink listing stops sync before rsync". The
stub git fails `ls-files` only when its arguments hold the word `-s`, so the
`-o -i` listing succeeds first. Asserts non-zero rc, the stub's message on
stderr, and no `dist/`.

Red: line 93 ending `|| true` gives 2 FAILs (exit code is 0; `dist/` exists).
Green after restore.

## m2: silent match with no copy (tests/dogfood-session-start-test.sh)

New scenario "session-start is silent on the copy named before any sync": fresh
fixture with no `dist/` (asserted), `CLAUDE_CODE_PLUGIN_DIRS=$root/dist/plugin`,
expects rc 0 and empty stdout and stderr.

Red: the `! -d "$copy"` block moved above the entry loop gives 1 FAIL, stdout
holding the "no copy at ..." object. Green after restore.

## m4: toolkit/README.md

One sentence added in the sync paragraph (about line 270): "A git error listing
the root or an initialised submodule stops the sync with git's own message,
`dist/` untouched." The following sentences were re-wrapped to 80 columns.
`doc-sync-test.sh` passes.

## m5: docs/changelog.md

Blank line 18 deleted; nothing else changed.

## Suite results (foreground, after the last restore)

- `dogfood-sync-test.sh`: all dogfood sync scenarios passed
- `dogfood-sync-refusal-test.sh`: all dogfood sync refusal scenarios passed
- `dogfood-session-start-test.sh`: all dogfood session-start scenarios passed
- `doc-sync-test.sh`: ok (5 shared command blocks, Layout matches toolkit/)
- `install-test.sh`: passed
- `shellcheck` on `toolkit/dogfood.sh` and the three changed suites: clean
- `docs-test.sh`: FAILS, not from my files. The line cap passes; three
  `broken-link` errors come from the other agent's untracked
  `plans/2026-10-08-dogfood-0.9.2/reports/node-split-report.md` (pointers
  `dogfood-sync.md`, `references/dogfood.md`, `references/dogfood-sync.md`
  resolved relative to `reports/`). I did not touch it; it will clear when that
  file's links are written as resolvable paths or inline code.

`just precommit` was not run, per the instructions. Nothing was staged or
committed.

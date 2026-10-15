# Slice 3 green: toolkit/dogfood.sh sync honours the allowlist

Only toolkit/dogfood.sh changed in this slice. No test was edited and nothing
was committed.

## Diff stat

```
 toolkit/dogfood.sh | 77 +++++++++++++++++++++++++++++++++++++++++++++++++++---
 1 file changed, 74 insertions(+), 3 deletions(-)
```

(tests/dogfood-sync-test.sh shows as modified in the tree, but that change was
already present before this slice started. It was not touched here.)

## Gates

- `bash -n toolkit/dogfood.sh`: exit 0, no output.
- `shellcheck toolkit/dogfood.sh`: exit 0, no findings.
- `bash tests/dogfood-sync-test.sh`: `all dogfood sync scenarios passed` (0
  failures).
- `bash tests/dogfood-sync-refusal-test.sh`:
  `all dogfood sync refusal scenarios passed` (0 failures).

## What changed

- `sync_copy`: after the existing excludes are written, `dist.sh paths` runs
  (found beside the script through `dist_path`) with its output redirected to
  `$work/listed`, never piped. Status 0 takes the allowlist, 3 keeps today's
  behaviour, 1 exits 1 with dist/ untouched, and any other status refuses with
  one `dogfood:` line. A `dist.include` with no `dist.sh` refuses with one line
  that names dist.sh. Both refusals come before `mkdir -p dist/plugin`.
- The allowlisted case builds `$work/filters` through `filter_rules`: the
  excludes as `- ` rules, then `+` rules for each parent directory, then `+` for
  a file or `+ /p/` and `+ /p/***` for a directory, then `- *`. rsync reads it
  with `--from0 --filter=". $work/filters"`, keeping
  `-a --delete --delete-excluded`.
- The non-opt-in branch is the original rsync call, unchanged, with
  `--exclude-from=- <"$work/excludes"`.
- Header comment above `sync_copy` gained a paragraph for the allowlisted case.

## Deviation to review

A listed path that is a symlink to a directory takes a file rule, not the `/p/`
and `/p/***` pair, because rsync does not treat a symlink as a directory. The
plan said to test -d. No suite pins this case.

## Test I think is wrong

None found. Both suites pass against this script, and the red-phase mutant
results in the slice3-red report still apply to it. The refusal wording for a
missing dist.sh is not pinned beyond the name, which matches the red report's
note.

## Green review

Verdict: APPROVE. One optional note.

Compared with an independent reference green (same filter order: ignore
excludes, parent `+` rules, `+ /p/` and `+ /p/***` or `+ /p`, `- *`; NUL merge
file; `--delete --delete-excluded`; allowlist read from the worktree). The
shapes agree. Both sync suites pass here. Scratch probes (`$TMPDIR/p1.sh`):

- Not opted in: the else branch is the original rsync call, textually identical,
  still fed `--exclude-from=- <"$work/excludes"`. With `dist.sh` beside it and
  no `dist.include`, `dist.sh paths` exits 3 with no output and the sync
  proceeds as before; with `dist.include` a directory, same.
- Pipes: none. `dist.sh paths` writes to `$work/listed`, the rules to
  `$work/filters`, both complete before rsync starts.
- Whitespace: nothing is split. Probed a consumer path with a space, a nested
  `a b/c d/f` with an unlisted sibling (absent), components with a trailing
  space (`t /x/f`, `l /y/f`, copied correctly), and `TMPDIR` containing a space
  (the `--filter=". $work/filters"` form survives it). A leading-blank line is
  refused by `dist.sh`.
- Refusals leave `dist/` absent on every path tried: a listed path that matches
  nothing, a glob character in the list, a `dist.sh` stub exiting 7 (one
  `dogfood:` line naming the status), and `dist.include` as a dangling symlink
  with no `dist.sh`. The `mkdir -p dist/plugin` sits after all of them.
- errexit: `bash "$dist" paths … >file || status=$?` captures the status, and
  the `case` has no fall-through to rsync (0 takes the list, 3 syncs as before,
  1 and everything else exit 1). `dist_path`'s `&&` list is the last command of
  a function called inside `$(…)` whose assignment is checked (`dist=$(…)`
  aborts under errexit), the same shape as `root_dir`.
- Deviation: sound. A listed symlink to a directory with a `+ /p/` and
  `+ /p/***` pair would never match (rsync treats the link as a non-directory
  under `-a`, so `+ /p/` does not select it and `- *` drops it); the file rule
  copies it as a link. Probed: `lnk -> real` and a link inside a listed
  directory both arrive as links. It means the dogfood copy can hold a symlink
  that `dist.sh tree` would refuse at release; that is a dogfood-only
  divergence, and the failure surfaces at release time rather than being hidden.
  No suite pins it.
- Comment voice and placement match the file (paragraph in the header comment
  above `sync_copy`, helpers after their caller, one-line comments inside).

Optional: a `dist.sh paths` failure that exits 1 without printing (for example
`mktemp` failing inside it) ends the sync with no `dogfood:` line, because the
`1)` branch assumes dist.sh already spoke. Not reproducible with the real
inputs; no change needed.

# Item 1.1/5 GREEN — an ignored pattern-character entry aborts sync

- Change: `toolkit/dogfood.sh` `sync_copy` — inside the ignore-list loop, a
  `case` on each entry refuses `*`, `?`, `[`, `]` and backslash: one stderr line
  `dogfood: ignored entry '<entry>' holds a pattern character; rsync would read it as a pattern`,
  `exit 1` from the loop. `pipefail` carries the status out of the pipeline, the
  EXIT trap removes the temp list, and the abort comes before `mkdir` and rsync,
  so `dist/plugin/` is untouched. Comment updated.
- Bash 3.2 safe (plain `case` globs); the entry is read with `read -r -d ''` and
  printed as-is.
- `tests/dogfood-test.sh`: all scenarios pass, including the five
  pattern-character fixtures and the tracked/untracked control.
- `just format-docs` then `just precommit` (unsandboxed): ok, no failures, no
  intermittent suite failures to record.

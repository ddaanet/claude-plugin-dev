# 2026-10-16 — Gate sentinels: two review rounds, before release

The gate sentinels and the quiet bats runner
([the record that shipped them](2026-10-16-gate-sentinels.md)) were reviewed
twice before any release. The first round was fixed in one commit and the second
in the next. Neither changes a decision there that a release could have depended
on; both change what the code does.

## First round

- **Moved inputs no longer fail the recipe.** `record-sentinel` keeps the
  checks' own verdict, records nothing and prints one line. It had exited 1,
  failing a gate whose checks passed.
- **The guard adds `justfile` and `plugin-dev` itself.** Both are fixed paths in
  every consumer; the manual no longer tells a maintainer to list them, and the
  recipe's own `$0` is not hashed.
- **The hash covers each file's execute bit**, and no other mode bit.
- **A `cd` between guard and record works.** The sentinel path is absolute and
  the hash runs from the directory the guard ran in.
- **A pathspec matching no file is refused** at the guard, naming it. Excludes
  are not held to it.
- **A file that cannot be read fails the hash.** A middle file's failing `cat`
  was swallowed by the loop and a partial hash recorded.
- **Name and content are delimited.** Contents go through one `xargs -0 cksum`
  over the list, whose line carries the size and the name, in place of a `cat`
  per file. A tree of two files and a tree of one file holding the other's name
  and content no longer hash alike.
- **`run-bats.sh` shows the log whenever bats exited non-zero with no `not ok`
  block**, and removes it on a green run, whose summary line then names no log.
- **`sentinel-guard` is defined ahead of `check-sentinel`.**
  `PLUGIN_DEV_GATE_FORCE` is documented as any non-empty value, as the code has
  always read it.

## Second round

The review of the first round's commit found that it had introduced two faults
of its own, and turned up six more.

- **An exclude-only gate hashed almost nothing.** Appending
  `justfile plugin-dev` to the caller's pathspecs gave
  `sentinel-guard lint ':!docs'` a positive pathspec, so the excludes subtracted
  from those two and not from the repository. The built-ins are now a second
  input set, listed apart and joined to the caller's after listing; an exclude
  applies to its own list only.
- **The built-ins matched nothing outside the simple case.** Literal `justfile`
  and `plugin-dev` resolve against the directory the recipe runs in, so a file
  named `Justfile`, `[working-directory]` and a gate in a module each hashed
  neither. The prolog now interpolates `justfile()` and `source_directory()`
  evaluated in `gates.just`, shell-quoted, as `gate_builtins`, and lists them as
  `:(literal)` pathspecs. Both functions were probed through an import before
  use. A module's own file is not covered and the manual says to list it.
- **"Matches no file" skipped any pathspec containing `exclude`.** The test was
  a substring match, so `:(glob)excluded/**` escaped it. Only `:!…`, `:^…` and
  `exclude` among the comma-separated magic words of `:(…)` are exempt.
- **A run that ran no test passed.** `run-bats.sh` removed its log on any
  status-0 run, a typo'd `--filter` or an empty `.bats` file included. Zero
  passed and zero failed is now a failure: it prints `bats: no tests ran`, the
  log, and exits 1.
- **`gate-inputs-hash` needed `gate_cwd`.** gitlore's `run-suites` sets only
  `gate_inputs` and would have died under `set -u`. It defaults to `.`, and
  `gate_cwd` joins the variable names CLAUDE.md lists as read by gitlore. The
  built-ins live in the prolog, so such a caller still hashes them.
- **The match check listed every file.** It stops at the first, by reading one
  record of `git ls-files -z`.
- **A symlink hashed as the regular file it points at.** The manifest now
  records `l` for it, ahead of the execute-bit test.

## Tests

Each fix was written as a failing assertion first and seen red against the code
before it. The fixtures now vendor `gates.just` at `plugin-dev/` as a consumer
does, since an absolute built-in outside the repository cannot be listed. The
scenarios for the files the guard hashes moved into a third suite,
`tests/gates-inputs-test.sh`, which keeps the other two under the line cap. The
first-file check is pinned by a shim `git` that logs how each `ls-files` exited:
a reader that stops early kills a long listing with SIGPIPE, 141.

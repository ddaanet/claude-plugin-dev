## Remaining

- Release the toolkit as a minor from `dev` via `edify:release`, then update the
  consumers to the new dist tag (they gain the memory-pointer handling only on
  the update after, since the vendored copy runs the update).
- The pre-commit hook's `format-docs` reflows a staged Markdown file without
  restaging it: the commit lands unformatted and the tree is left dirty with the
  reflow (seen on `TASK.md`, `docs/references/gates.md`). `whitespace` stages
  what it fixes; `format-docs` should do the same for tracked files.
- `docs/references/recovery.md` (around line 125) still argues from gitlore's
  memory-approval gate as a consumer `pre-commit` hook; gitlore retired that
  hook, so the premise needs rewriting to the live mechanism.
- `toolkit/release-preflight.sh`'s `tree_is_clean` and `toolkit/install.sh`'s
  clean-tree guard run a plain `git diff --quiet HEAD`, which honours a
  consumer's `diff.ignoreSubmodules` / `submodule.<name>.ignore`, so a code
  submodule's unrecorded move passes them; `update.sh`'s dirt check uses
  `--ignore-submodules=untracked` to refuse it. Align the three, deciding first
  whether the other two should keep refusing untracked files inside a submodule,
  which their plain check does and `=untracked` would let through.

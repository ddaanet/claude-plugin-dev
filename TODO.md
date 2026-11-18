## Remaining

- Release the toolkit as a minor from `dev` via `edify:release`, then update the
  consumers to the new dist tag (they gain the memory-pointer handling only on
  the update after, since the vendored copy runs the update).
- The pre-commit hook's `format-docs` reflows a staged Markdown file without
  restaging it: the commit lands unformatted and the tree is left dirty with the
  reflow (seen on `TASK.md`, `docs/references/gates.md`). `whitespace` stages
  what it fixes; `format-docs` should do the same for tracked files.

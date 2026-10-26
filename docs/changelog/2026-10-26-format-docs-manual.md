# 2026-10-26 — `format-docs` reflows the shipped manual

`just format-docs` ran rumdl over `docs/` and `plans/` only, so
`toolkit/README.md`, `toolkit/manual/` and `toolkit/migrations/` were wrapped by
hand. The 400-line cap `tests/line-cap-test.sh` holds them to was therefore
measured on that hand wrapping, the same gap the cap over `docs/` closed when
`format-docs` was introduced: a file could sit under the cap on ragged lines
that a reflow would have changed.

## Changed

- **`format-docs`** passes `toolkit/README.md`, `toolkit/manual` and
  `toolkit/migrations` to `rumdl fmt` beside `docs` and `plans`. `.rumdl.toml`
  names no paths, so it needed no change.
- **The shipped Markdown was reflowed once** in the same commit. Seven files
  changed, line breaks only; fenced blocks are untouched (rumdl skips code
  blocks here), so the install and update blocks `tests/doc-sync-test.sh`
  compares between the two READMEs are as they were. The longest file,
  `toolkit/README.md`, stays at 309 lines.
- **`CLAUDE.md`** and a comment in `tests/docs-test.sh` state the new scope.
  `tests/docs-test.sh` still counts `docs/` and lists `docs/` and `plans/` only;
  the cap over the manual stays in `tests/line-cap-test.sh`.

Past `migrations/` notes are reflowed along with the rest. They are printed by
`update.sh` as they stand, and a reflow changes line breaks and not words. One
inline code span in `migrations/v0.9.1.md` is over 80 columns and stays, which
`fmt` reports and does not fail on.

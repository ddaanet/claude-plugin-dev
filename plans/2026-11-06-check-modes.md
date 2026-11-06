# Plan: check-modes, the vendored exec-bit check

2026-11-06. From `inbox/2026-11-05-run-bats-counts-skips-as-passed.md`, finding
2. Approved by my human partner: a consumer-side check, by rule (a file starting
`#!` is executable), not a list. Tasks are contracts, not code.

## Why consumer-side

A consumer commit flipped six vendored scripts to 100644 after vendoring. The
recipes call `bash <script>`, so the gate saw nothing, while `bin/claude` drops
off PATH silently and a direct call fails. A test in this repo never sees a
consumer, and an `update.sh` warning runs only at a pull, so only a check in the
consumer's own gate catches a later flip.

## Contract

- **`toolkit/check-modes.sh`**, executable. Checks the directory it lives in
  (the vendored copy in a consumer, `toolkit/` here), no arguments, from
  anywhere in the work tree. Files from disk,
  `git ls-files -co --exclude-standard` under that directory, NUL-delimited. A
  file whose first two bytes are `#!` must pass `[ -x ]`. Exit 0 prints one
  sign-off line naming the count checked. Exit 1 prints one stderr line per
  file, `mode-lost: <path from the repo root>`, then a hint: the `chmod +x`
  command over those paths, quoted, then commit. Not inside a work tree: one
  stderr line, exit 1. Same shape as `check-size.sh`.
- **The rule holds for the toolkit itself.** `install.sh`, `update.sh`,
  `version-guard.sh` and `exempt-list.sh` become 100755.
  `tests/dist-tree-test.sh` replaces its hard-coded executable loop with the
  rule over the shipped set, and lists `check-modes.sh`.
- **`release.just`** gains a `check-modes` recipe beside `check-size`, a
  one-line doc comment, and the header paragraph naming it; no recipe runs it.
  The wiring is
  `precommit: check-refs check-size check-frontmatter check-modes`.
- **This repo's gate** runs `bash toolkit/check-modes.sh` beside
  `check-size.sh`, and `_import-check` dry-runs the new recipe and names it in
  its sign-off.
- **Migration note** `toolkit/migrations/v0.16.0.md`, breaking: a consumer
  recipe named `check-modes` now clashes (step 0, rename it), then wiring it
  (step 1), then fixing what it reports on first run (step 2). Same shape as
  `v0.15.0.md`.

## Steps

1. **Red** (Sonnet): new `tests/check-modes-test.sh` against fixture repos,
   scenarios: a clean vendored dir signs off with its count; a `#!` file at mode
   644 refuses with its `mode-lost` line and a hint whose `chmod` run verbatim
   clears it; a non-`#!` file at 644 passes; an untracked `#!` file is checked
   and an ignored one is not; a path with a space; a file outside the script's
   directory is not checked; run from a subdirectory; outside a work tree. Plus
   the `dist-tree-test.sh` rule change. Registered in `tests/CLAUDE.md`.
2. **Red review** by a different agent: each fails on an assertion against the
   unchanged tree.
3. **Green** (Haiku): the script, the four mode flips, `release.just`, the root
   `justfile`.
4. **Docs** (Sonnet): the manual's optional-checks section in
   `toolkit/README.md`, `docs/toolkit-layout.md`, a decision node
   `docs/references/mode-check.md` with its hub line in `docs/design.md` and its
   name in `CLAUDE.md`'s node list, the migration note, the `gates.just` usage
   example's direct call stays valid. Present tense.
5. **`just precommit`, one commit, `/code-review medium`.** Then delete the
   inbox brief and its `TODO.md` line.

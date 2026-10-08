# Corrections report: the four probed dogfood claims

Applied from `unprobed-items.md`. Nothing staged, committed, stashed or
released; `toolkit/VERSION`, `tests/` and `inbox/` untouched.

## Files changed (6)

- `docs/references/dogfood.md` (234 -> 238 lines)
  - jq paragraph: `jq` exits 2 on a usage or system error (1.7 probed); a parse
    error exits 5 in 1.7 (probed) and 4 in 1.6 (read from its source, not run);
    exit 1 holds whichever version meets the payload. The "1.6 exits 2 on a
    parse error (read from its source, not probed)" claim is gone.
  - Twice-firing sentence: now states they run twice, no de-duplication even
    with identical command strings, `--setting-sources project` does not stop
    the variable (probed on CC 2.1.294), and a script meets it only when the
    shim is on its PATH and the copy exists.
- `docs/references/dogfood-sync.md` (177 -> 182 lines)
  - Trade-off list and `just dogfood` section: commands, `.mcp.json` and output
    styles go live on `/reload-plugins`, beside skill bodies.
  - Empty `.mcp.json`: accepted silently on CC 2.1.294; plugin loads, no server
    or error shown, parse error to the debug log only, no servers loaded; only
    `claude plugin validate` on the copy fails ("Unexpected EOF"). Paragraph
    reflowed to the formatter's 80-column output.
- `toolkit/README.md`
  - The two "unverified" bullets became one: commands, `.mcp.json` and output
    styles go live after `/reload-plugins`; a relaunch does too.
  - Empty `.mcp.json` sentence: loads regardless, ignores the file, reports
    nothing in the session, `claude plugin validate` on the copy fails. This
    matches the sync node. The README states no version for it, as the sibling
    sentences do not; the node names CC 2.1.294.
- `toolkit/dogfood.sh`: comment lines only. `git diff` shows 4 lines out and 4
  in, all `#` lines in the `pre_tool` header: the "and on a parse error in 1.6"
  clause is dropped and the comment reflowed. No code line changed.
- `docs/changelog/2026-10-08-probed-dogfood-claims.md` (new): what was probed,
  CC 2.1.294 and jq 1.7 installed, what each result changed, the jq 1.6 caveat
  (read from source, not run, no published checksum), and that gitlore's evals
  meet the double hook run only after adopting the shim (its vendored toolkit
  has no `bin/` and no `PATH_add` today). No migration note.
- `docs/changelog.md`: bullet at the top of the list, no blank line between
  items.

`docs/design.md` was grepped for twice, `.mcp.json`, reload and jq 1.6. It
states none of the four claims, so it is unchanged.

## Remaining "unprobed" and "unverified" claims

After the edits, grep of `docs/`, `toolkit/` and `CLAUDE.md` finds only:

- `docs/design.md:293` and `docs/references/dogfood-sync.md:143`, the macOS
  rsync claim, left alone as instructed.
- Dated changelog records from 2026-10-03 and 2026-10-05, never revised.

## Checks

All foreground, all green:

- `bash tests/doc-sync-test.sh`: doc sync ok (5 shared command blocks, Layout
  matches `toolkit/`).
- `bash tests/docs-test.sh`: every relative pointer resolves, the cap holds.
- `bash tests/dist-tree-test.sh`: dist tree ok (11 files).
- `bash tests/citation-test.sh`: citations ok.
- `bash tests/dogfood-pre-tool-test.sh`: all scenarios passed.
- `bash -n toolkit/dogfood.sh` and `shellcheck toolkit/dogfood.sh`: clean.
- `git diff -- toolkit/dogfood.sh`: comment lines only, as above.
- `.venv/bin/rumdl check docs/`: two findings, both pre-existing, neither mine.
  They are `dogfood-sync.md:106` (101-column code span) and line 20 of
  `2026-10-08-dogfood-no-copy-remedy-and-submodule-ignores.md`. My new record
  and the edited paragraphs were reflowed to the formatter's output, using
  `rumdl fmt` on scratch copies under `$TMPDIR`, so the repo was not run through
  `format-docs`.

## Declined or flagged

- `tests/dogfood-pre-tool-test.sh:352` and `:357` still say "2 in jq 1.6" and
  "jq 1.6 exits 2 on a parse error". They are comments; no assertion pins the
  wording and the suite passes. Not edited, per the instruction. The changelog
  record names them. The stub that exits 2 still tests the right property.
- `toolkit/dogfood.sh` is under `toolkit/`, so the comment change ships only
  with the next release. No bump was made.
- The report's note that gitlore's eval repo `.claude/skills` and
  `.claude/commands` copies may sit beside the loaded plugin was not probed; the
  record says so.

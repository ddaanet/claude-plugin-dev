# Item 2.1 slice 1 — GREEN

## Implementation

`toolkit/bin/claude` (mode 100755 in the index): physical `<root>` from its own
location, runs `dogfood.sh sync`, exports `CLAUDE_CODE_PLUGIN_DIRS`, unsets
`CDPATH`, drops PATH entries spelled exactly as its own directory, execs
`claude "$@"`.

## Order made to pass

The four scenarios share one small script, and the shim was written whole rather
than grown per scenario; the four then passed in a single run. The order below
is the suite's, not a growth sequence.

1. the shim execs the next claude with argv intact (incl. same pid): pass
2. the shim syncs before exec (copy present at launch): pass
3. the shim exports the copy (physical root, launch from elsewhere): pass
4. the shim unsets CDPATH: pass

## Gate bookkeeping

- `tests/dist-tree-test.sh`: `bin/claude` in `expected`; index-mode 100755
  assertion.
- `CLAUDE.md`: Layout bullet for `toolkit/bin/claude`.
- `justfile`: shellcheck, `bash -n` and suite line for the launcher.

## Results

- `bash tests/dogfood-launcher-test.sh`, `tests/dist-tree-test.sh`,
  `tests/doc-sync-test.sh`: green; `shellcheck toolkit/bin/claude`: clean.
- `just precommit` runs in the commit hook; warnings, if any, are in the commit
  log.

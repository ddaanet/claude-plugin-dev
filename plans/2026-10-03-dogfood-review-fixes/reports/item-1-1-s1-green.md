# Item 1.1/1 GREEN — the shim syncs only outside a dogfood session of its own repo

Change: toolkit/bin/claude wraps `dogfood.sh sync` in an exact string test,
`CLAUDE_CODE_PLUGIN_DIRS` != `$root/dist/plugin`; the export is unchanged and
unconditional. Header comment states the condition and why.

## Order made to pass

1. "a variable equal to this copy skips the sync" — the only red test; the
   conditional made it pass on the first attempt.
2. Remaining launcher scenarios (incl. the list-valued one, "an inherited
   variable is overwritten", "the shim syncs before exec") stayed green.

## Results

- `bash tests/dogfood-launcher-test.sh`: all scenarios passed.
- `just precommit`: ok (all suites, linters, format-docs); no warnings reported.
  No flake occurred.

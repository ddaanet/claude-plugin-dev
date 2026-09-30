# Item 2.1 slice 3 — GREEN

Change: `path_without` in `toolkit/bin/claude` now takes the shim's own file
(`${BASH_SOURCE[0]}`) and drops an entry when `"${entry:-.}/claude"` is `-ef`
that file. An empty entry means the working directory, so it is tested as
`./claude` (not `/claude`): dropped only if the cwd holds the shim itself,
otherwise kept in place. The newline-safe capture and the colon-prefix rebuild
are unchanged. Comment and header updated.

Order made to pass (one at a time):

1. the shim strips its own entry in any spelling — pass (identity check)
2. the shim keeps another bin/claude — pass
3. the shim keeps the rest of PATH as spelled — pass

Earlier five scenarios stayed green. Full suite:
`bash tests/dogfood-launcher-test.sh` all passed.
`shellcheck toolkit/bin/claude` clean.

`just lint` does not exist in this repo; `just precommit` passed with no
warnings.

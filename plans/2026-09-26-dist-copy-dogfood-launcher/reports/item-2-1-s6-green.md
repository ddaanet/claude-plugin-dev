# Item 2.1/6 GREEN: no next claude exits 127

In session, as a one-guard implementation. After the shim rebuilds PATH,
`toolkit/bin/claude` runs `command -v claude`. If that finds nothing, the shim
prints `dogfood: no other claude on PATH` to stderr and exits 127 before the
`exec`. The file header now states that exit.

The test review had dropped one column from the `$stubdir` line of
`make_consumer`'s header, and that alignment is restored.

Run: `bash tests/dogfood-launcher-test.sh` passes all 12 scenarios, the new one
included. `shellcheck` is clean on both files. `just precommit` runs in the
commit's pre-commit hook.

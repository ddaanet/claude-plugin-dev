# Item 2.2/2 GREEN: a re-run is a no-op (no diff)

In session. 2.2/1's GREEN already implements this behaviour: `add_hook`'s
presence check and the `cmp` guard ahead of the write. The RED report proves the
test by mutation, and the test review reproduced that proof with two mutations
of its own, so no implementation change is needed.

`bash tests/update-plugin-dev-test.sh` reports
`update-plugin-dev scenarios passed`. `just precommit` runs in the commit's
pre-commit hook.

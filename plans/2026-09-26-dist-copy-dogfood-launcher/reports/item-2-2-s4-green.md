# Item 2.2/4 GREEN: idempotency ignores the matcher (no diff)

In session. The presence check in 2.2/1's `add_hook` already selects on the
command alone, under any entry of the event, whatever that entry's matcher. The
RED report proves this by mutation, restoring the old null-or-`Write|Edit` test.
The test review proves it again with a different mutation, an equal-matcher
check. No implementation change is needed.

`bash tests/update-plugin-dev-test.sh` reports
`update-plugin-dev scenarios passed`. `just precommit` runs in the commit's
pre-commit hook.

# Item 2.2/3 GREEN: a pre-existing SessionStart entry survives (no diff)

In session. 2.2/1's `add_hook` already appends to the event's array (`//= []`,
then `+=`), so the consumer's own `SessionStart` entry survives. The RED report
proves the test by mutation, and the test review reproduced the proof with a
different mutation, so no implementation change is needed.

`bash tests/update-plugin-dev-test.sh` reports
`update-plugin-dev scenarios passed`. `just precommit` runs in the commit's
pre-commit hook.

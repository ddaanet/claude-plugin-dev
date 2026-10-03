# Item 1.1/2 GREEN — a failed sync at launch is attributed to the shim

Change: toolkit/bin/claude. On a failed `dogfood.sh sync` the shim captures the
status (`|| status=$?`, so `set -e` does not kill it first), prints one stderr
line after the sync's own output,
`dogfood: sync failed, so `claude` was not started`, and exits with the sync's
own status. The slice-1 skip condition is untouched. Header comment updated.

Order made to pass: one failing test, "a failed sync aborts the launch" (the
one-line `^dogfood:.*not started` assertion); the "failed rsync keeps its
status" scenario already passed with the status-preserving exit.

Results: launcher suite green (all scenarios passed, including both failed-sync
scenarios). `just precommit` green (shellcheck, all suites, docs). A shellcheck
SC2016 note on a single-quoted backtick was fixed with a double-quoted string.
Precommit warnings: none. No flaky suite failures.

# Item 2.1 slice 5 GREEN: a failed sync aborts the launch (no diff)

The existing shim already has this behaviour. It runs under `set -euo pipefail`,
so a failing `bash … dogfood.sh sync` ends it with sync's own status, before the
exec, and leaves sync's stderr unredirected. Slice 1's code review probed this.
The test was proven by mutation in RED (`|| true`, `|| exit 0`) and again in the
test review with different mutations, including one that silences sync's stderr.
`toolkit/bin/claude` is unchanged.

`bash tests/dogfood-launcher-test.sh`, run in the foreground: all dogfood
launcher scenarios passed.

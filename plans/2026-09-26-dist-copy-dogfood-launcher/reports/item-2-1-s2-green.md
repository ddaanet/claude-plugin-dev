# Item 2.1 slice 2 GREEN: an inherited variable is overwritten (no diff)

Slice 1's GREEN already implements this behaviour: the shim's
`export CLAUDE_CODE_PLUGIN_DIRS="$root/dist/plugin"` replaces any inherited
value. The test was proven by mutation in RED, and again with three different
mutations in the test review. `toolkit/bin/claude` is unchanged.

`bash tests/dogfood-launcher-test.sh`, run in the foreground: all dogfood
launcher scenarios passed. This commit carries the new test and the slice's
reports.

# Item 2.1 slice 4 GREEN: subdirectory launch (no diff)

Both of this slice's tests passed against the existing shim. Slice 1's GREEN
takes `<root>` from the shim's own location, and nothing changes directory in
the main shell. Slice 3's GREEN tests an empty PATH entry as `./claude`. Both
tests were proven by mutation in RED and again with different mutations in the
test review. `toolkit/bin/claude` is unchanged.

One test-side addition, made by the orchestrator in session: the test review's
out-of-scope finding 2. Slice 1's `the shim exports the copy` now launches from
a directory that is itself a git repo (`git init -q "$sandbox/elsewhere"`), so a
shim that takes `<root>` from git's toplevel first reds there. The reviewer
verified that on a scratch copy. The scenario comment says so.

`bash tests/dogfood-launcher-test.sh`, run in the foreground: all dogfood
launcher scenarios passed. `shellcheck` is clean.

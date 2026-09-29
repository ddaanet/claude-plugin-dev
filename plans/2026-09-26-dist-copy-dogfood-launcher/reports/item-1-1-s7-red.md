# Item 1.1 slice 7 RED: rsync failure

Test added to tests/dogfood-test.sh (section "an rsync failure keeps its status
and stderr", before the usage section). A stub `rsync` first on PATH prints
`rsync: stub failure` to stderr and exits 23; git is real. Assertions: rc == 23;
`grep -c -x` of that line in stderr == 1.

`bash -n` and `shellcheck` clean. Committed SUT: suite green (test passes as
expected, no red phase since rsync already runs as a plain statement under set
-e with stderr unredirected).

## Mutation proof

Each by exact string replacement on the rsync line's tail
`"$root/" "$root/dist/plugin/" <"$excludes"`, restored by the swapped
replacement; `git diff --quiet toolkit/dogfood.sh` true after each; suite green
after all.

- (a) status, `... || exit 1`:
  `FAIL: an rsync failure: exit code is rsync's own: expected '23', got '1'`
- (b) stderr, `... 2>/dev/null`:
  `FAIL: an rsync failure: its stderr line appears exactly once: expected '1', got '0'`
- (c) once,
  `... 2>"$excludes.err" || { s=$?; cat "$excludes.err" "$excludes.err" >&2; exit "$s"; }`
  (status kept, line emitted twice):
  `FAIL: an rsync failure: its stderr line appears exactly once: expected '1', got '2'`

Only the named assertion failed in each. Note: a first (c) attempt with
`2> >(tee /dev/stderr >&2)` stayed green, because tee reopening /dev/stderr
truncates run_dogfood's stderr file, yielding one line; it was not a valid
duplication mutation and was restored.

Scratch: /tmp/claude/dogfood-build/mut.py (replacement helper). No commit made.

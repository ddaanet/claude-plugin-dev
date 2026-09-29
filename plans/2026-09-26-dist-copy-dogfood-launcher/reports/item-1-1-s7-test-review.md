# Item 1.1 slice 7 test review: rsync failure

Verdict: **pass, no changes.** The test matches the slice text and the
Interfaces line, discriminates on both named behaviours plus duplication, and
cannot go green for a wrong reason that I could construct.
`tests/dogfood-test.sh` unchanged by this review (447 lines).

## 1. Mechanical

Against the committed SUT: `git diff --quiet toolkit/dogfood.sh` true, suite
green (`all dogfood scenarios passed`), `bash -n` and `shellcheck` clean.

Mutations of my own, distinct from the RED report's (a)-(c), each by exact
single-occurrence string replacement, landing proven by a non-empty `git diff`,
restored by the inverse replacement, `git diff --quiet` true after each. Helper:
/tmp/claude/dogfood-build/s7-review/mut.sh.

- **status**, rsync line tail `... <"$excludes" || true`:
  `FAIL: an rsync failure: exit code is rsync's own: expected '23', got '0'`
- **stderr**, tail `... <"$excludes" 2>&1` (stderr sent to stdout, not
  discarded):
  `FAIL: an rsync failure: its stderr line appears exactly once: expected '1', got '0'`
- **duplication**, a probe `rsync --version >/dev/null || true` inserted before
  the real call (the stub ignores args, so its line lands twice; status still
  23):
  `FAIL: an rsync failure: its stderr line appears exactly once: expected '1', got '2'`
  - A first variant `rsync >/dev/null || true` also reddened this assertion, but
    real rsync's usage text additionally failed
    `a tracked file deleted in the worktree prints nothing on stderr`; the
    `--version` variant isolates it.
- **stub bypass**, `command -p rsync` (default PATH, real rsync, which
  succeeds): both assertions red, `expected '23', got '0'` and
  `expected '1', got '0'`.

Each red was on the named assertion alone (except the stub bypass, which changes
both behaviours by design). Final state: SUT clean, suite green.

## 2. Wrong-reason hunting

- **Stub actually invoked.** The stderr assertion counts a line only the stub
  emits, so it proves the stub ran; rc 23 alone could come from a real rsync
  partial-transfer error, but no single fault gives 23 and the stub's line
  without the stub. The bypass mutation confirms it: routing around the PATH
  lookup reds both assertions.
- **Same PATH lookup as production.** The script calls bare `rsync`. The test
  prefixes PATH on the `run_dogfood` call, which bash exports to the function's
  children, and `bash .../dogfood.sh` resolves `rsync` through it: the same
  mechanism slice 6's git stub uses. The stub dir holds only `rsync`, so `bash`
  and `env` still resolve to the real ones.
- **Real git still reached.** Only `rsync` is stubbed; `git` resolves past the
  stub dir. The refusal checks and `ls-files` run for real.
- **Fixture reaches rsync.** A fresh `make_consumer` carries the manifest and
  the `/dist/plugin/` ignore, and holds no pattern-character entries. The stub's
  line in stderr is itself proof the run got past every refusal; a refusal would
  give rc 1 and a count of 0.
- **Count extraction.** `printf '%s\n' "$err" | grep -c -x` prints `0` on no
  match (grep's exit 1 is harmless inside an argument substitution), which the
  stderr mutation exercised. The needle has no BRE metacharacters; `-x` pins the
  whole line.
- **Accepted residual.** Capturing rsync's stderr and re-emitting it once,
  byte-identical, would pass. It is behaviourally indistinguishable at the
  interface and the slice does not ask to tell them apart.

## 3. Fixes

None needed.

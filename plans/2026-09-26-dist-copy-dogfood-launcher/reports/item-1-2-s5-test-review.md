# Review: Item 1.2/5 test review — `pre-tool is silent without jq`

**Scope**: `make_jqless_bin` and the test `pre-tool is silent without jq` in
tests/dogfood-test.sh (uncommitted), the RED report item-1-2-s5-red.md.
toolkit/dogfood.sh read as the SUT only. **Date**: 2026-09-30 **Mode**: review +
fix

## Summary

The test is red for the right reason against the committed SUT: exit 127 and
`jq: command not found` on stderr, from line 86's `jq`. The jq-less PATH holds
what a correct GREEN needs and nothing that could stand in for jq. One gap was
fixed: nothing in the test showed that its payload is one the guard would deny,
so a jq-present control now runs the same payload first. One limit is noted
below. The test cannot tell a `command -v jq` guard from a
`2>/dev/null || exit 0` suppression, and no test in the suite can.

**Overall Assessment**: Ready

## Mechanical check

Suite run in the foreground, before and after the fix. Both runs show the same 2
failures, both from this test and both on assertions:

- `FAIL: pre-tool is silent without jq exit code: expected '0', got '127'`
- `FAIL: pre-tool is silent without jq prints nothing on stderr: expected '', got '…/my consumer/plugin-dev/dogfood.sh: line 86: jq: command not found'`

The stdout assertion passes, which is expected because the SUT dies before it
prints. The `command -v jq` precondition passes. The new control passes too
(`assert_denied` over the same payload with jq on PATH). All other scenarios
pass.

The precondition's mechanism was probed. In a shell that has already hashed
`/usr/bin/jq`, `PATH=<empty dir> command -v jq` returns 1 and
`PATH=<dir>:/usr/bin command -v jq` returns 0. The prefix assignment applies to
the builtin and flushes the hash, so the check cannot pass on a stale hash. If
the prefix were ignored, `command -v` would find jq and the `fail` would fire,
so the check fails safe.

## Wrong-reason analysis

- **PATH contents.** `pre_tool` calls one external command before jq: `dirname`
  in `root_dir`. `cd`, `pwd`, `printf`, and all of `physical_path` are builtins.
  `run_dogfood` calls `bash`, `mkdir` and `cat`, and under `PATH=… run_dogfood`
  the prefix applies to the whole function body. The four symlinks are exactly
  that set. A GREEN guard written as `command -v jq` (a builtin) needs nothing
  more. None of the four can parse JSON, so a GREEN cannot pass by falling back
  to some other parser. A fallback through `grep`/`sed` would hit 127 and fail.
  Symlinking single binaries, rather than filtering PATH directories, keeps out
  a jq that shares a directory with `bash`. The helper takes only a directory
  argument and names nothing specific to `pre-tool`, so Item 1.3/4 can reuse it
  as it stands.
- **Is the payload a copy path?** It is `$root/dist/plugin/skills/demo/SKILL.md`
  after a real `sync`, with `$root` in its `pwd -P` spelling, the same path the
  deny tests use. Before this review nothing in the test showed that, and
  silence from a payload outside the copy is simply the allow. The fix below
  adds the paired positive: the same fixture and the same payload, differing
  only in whether jq is on PATH.
- **Birth state / bare negative.** Against the committed SUT this is not a bare
  negative: it is red now (127), and deleting a GREEN's guard makes it red
  again.
- **Guard vs suppression.** Both GREEN shapes were probed in place on
  toolkit/dogfood.sh. The SUT was restored afterwards by inverting the edit, and
  `git diff --quiet` confirms it is clean.
  - A: `command -v jq >/dev/null || exit 0` after `root_dir`. Whole suite green.
  - B: line 86 as `jq … 2>/dev/null && printf x)" || exit 0`. Whole suite green.

  With no jq on PATH, A and B produce identical observables, so no assertion in
  this test can separate them, and none was invented. The runbook's "stderr
  empty" is satisfied by both. `memory/ddaanet/no-stderr-suppression.md`
  requires A, which guards the expected failure away. B also silences jq's own
  parse errors: `printf 'not json' | bash toolkit/dogfood.sh pre-tool` exits 5
  with `jq: parse error…` today, and under B it would exit 0 in silence. That
  contradicts the SUT's documented contract (lines 78–80, "A payload jq cannot
  read … stops the script non-zero"). See Minor issue 2.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Silence was not shown to come from the missing jq**
   - Location: tests/dogfood-test.sh, `pre-tool is silent without jq`
   - Problem: the test's only positive evidence that its payload is a copy path
     was the path spelling. A silent exit 0 is also what the allow branch gives
     for any path outside the copy. The test had no positive paired with it over
     the same fixture.
   - Fix: run the same `$payload` with jq on PATH first and `assert_denied` it.
     The two runs then differ only in the trigger. A comment above the scenario
     states why.
   - **Status**: FIXED

### Minor Issues

1. **Helper comment overclaimed**
   - Location: tests/dogfood-test.sh, `make_jqless_bin` header
   - Note: "A PATH of <dir> alone reaches everything but jq" read as a promise
     of a full PATH minus jq. It reaches four commands.
   - **Status**: FIXED. The comment now says "reaches those and not jq".
2. **No test excludes a stderr-suppressing GREEN**
   - Location: suite-wide. This is not in this slice's diff.
   - Note: probe B passes the whole suite. A test such as "pre-tool fails loudly
     on a payload jq cannot read" (malformed stdin with jq present; assert rc ≠
     0 and jq's error on stderr) is green against the committed SUT and red
     against B. That supplies the discrimination through mutation, as
     test-discipline prescribes for code that already exists.
   - **Status**: OUT-OF-SCOPE. It is a new scenario outside this slice's IN list
     (the helper and this one test). Recommended to the orchestrator: have the
     GREEN code review reject a `2>/dev/null` on the jq read, and consider
     adding the malformed-payload scenario.

## Fixes Applied

- tests/dogfood-test.sh `pre-tool is silent without jq`:
  `run_dogfood pre-tool <<<"$payload"` plus
  `assert_denied "$label: control with jq on PATH" "$root"` before the PATH
  narrows. The scenario comment now explains the control.
- tests/dogfood-test.sh `make_jqless_bin` header: the wording now says the PATH
  reaches the listed commands and not jq.
- `shellcheck tests/dogfood-test.sh` is clean after the edit.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| 1.2/5: jq-less PATH, copy-path payload → exit 0, stdout and stderr empty | Satisfied (red, awaiting GREEN) | three `assert_eq` on rc/out/err; the copy path is now proven by the jq-present control |
| Fixture: jq-less PATH is symlinks to the commands the script invokes, jq excluded | Satisfied | `make_jqless_bin`: bash, dirname, mkdir, cat |
| Fixture: each use first asserts `command -v jq` fails under it | Satisfied | precondition `if PATH=… command -v jq; then fail`; mechanism probed |
| Helper stays generic for 1.3/4 | Satisfied | takes only a directory; no pre-tool specifics |

## Positive Observations

- The payload is built with the real jq before the PATH narrows, and a comment
  says why.
- It uses single-binary symlinks rather than directory filtering, so a jq that
  sits next to `bash` cannot leak in.
- The RED fails on assertions, and names the exact line and cause.

## Recommendations

- GREEN: guard with `command -v jq >/dev/null || exit 0`. Do not redirect jq's
  stderr. The guard can sit before or after `root_dir`, since the PATH supplies
  `dirname`.

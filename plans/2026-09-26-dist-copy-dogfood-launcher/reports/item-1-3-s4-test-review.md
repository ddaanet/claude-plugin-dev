# Review: Item 1.3/4 test review — `session-start reports a missing jq on systemMessage only`

**Scope**: the new scenario in tests/dogfood-test.sh (uncommitted) and
item-1-3-s4-red.md. toolkit/dogfood.sh was read as the SUT and mutated in place
only for probes, each restored by inverting the edit
(`git diff --quiet toolkit/dogfood.sh` clean after every probe). **Date**:
2026-09-30 **Mode**: review + fix

## Summary

The scenario is red for the right reason. Against the committed SUT it gives 10
failures, all on assertions, with no harness error. The two runs matter for
different reasons. `(unset)` dies at line 144 (`jq: command not found`, exit
127). `(names-the-copy)` exits 0 silently because the copy check runs without
jq. That second run is the one that rules out a stderr-suppressing GREEN.

Three fixes were applied:

- The run now follows the suite's prefix convention instead of `export`/`unset`.
- "names jq" no longer passes on a sandbox path that happens to contain `jq`.
- The scenario comment names the jq-present controls.

**Overall Assessment**: Ready

## Mechanical check

The suite was run in the foreground before the fixes, after them, and after
every probe was restored. Each run gave the same 10 `FAIL:` lines, all from this
scenario. Every other scenario passed.

- `(unset)`, 6 failures:
  - exit code `127`;
  - stderr `…/dogfood.sh: line 144: jq: command not found`;
  - stdout one JSON object, ANSI reset, names jq, and hookSpecificOutput absent,
    each failing over `''`.
- `(names-the-copy)`, 4 failures: the four stdout checks, over `''`. The exit
  code and stderr assertions pass, as they should: the committed SUT exits 0 in
  silence here.

The `command -v jq` precondition passes. Its mechanism was probed in 1.2/5's
review: the prefix flushes the hash, and the check fails safe.
`shellcheck tests/dogfood-test.sh` is clean.

## Probes (SUT mutated in place, restored by inversion)

| Mutation of `session_start` | Result |
|---|---|
| A: `command -v jq >/dev/null \|\| { printf static; exit 0; }` after `copy=` | whole suite green |
| B: the final `jq -nc … 2>/dev/null \|\| printf static` | red: all 4 stdout checks of `(names-the-copy)` |
| C: guard as in A, but the message is `no check of $copy` (no "jq"), run with `TMPDIR` under a directory named `jqx` | red: `names jq` in both runs (after the fix) |
| D: print the static object unconditionally | red: `silent on the copy` (stdout) and `warns when the variable is unset` (3 checks) |

- **A** shows that the intended GREEN satisfies the scenario together with every
  other test.
- **B** answers the suppression question. The copy loop is pure bash, so a GREEN
  that only catches jq's failure at the end never reaches jq when the copy is
  named. It exits silently and reds. A GREEN has to check jq's presence before
  the copy check, which is the Interfaces line "the copy check is skipped". That
  is also the shape `no-stderr-suppression` asks for: guard, don't redirect.
  - The suppression would hide nothing further here. Session-start's jq takes
    `-n` and `--arg` and parses no input, so jq has no parse error it could
    mask. The one jq that does parse input, pre-tool's payload read, is already
    pinned loud by `pre-tool fails loudly on a payload jq cannot read`.
- **C** is Minor 2. Before the fix, `contains("jq")` accepted it: probed
  directly with jq, the old filter was `true` and the new one `false`.
- **D** shows that the existing jq-present tests are the controls (see below).

## Wrong-reason analysis

- **`export`/`unset` in the loop.** It was sound as written: `run_dogfood` runs
  under `set +e`, so nothing exited between the export and the unset, and the
  trailing unset restored the preamble's state. It departed from the convention
  item-1-3-s1 set, though ("a test wanting it passes it as a prefix"), and it
  left the variable exported at script scope for the length of one run. Now
  rewritten with prefixes (Minor 1).
  - Prefix assignments on a function call are scoped to the call: `PATH` and
    `CLAUDE_CODE_PLUGIN_DIRS` reach the child and are restored afterwards.
    1.3/1's row 2 showed they reach the child, and every later scenario passing
    under the full PATH shows they are restored.
- **Is a jq-present control needed?** No new one. The existing tests already are
  the controls, over the same fixture and payload, differing only in PATH:
  - `session-start is silent on the copy` for `(names-the-copy)`;
  - `session-start warns when the variable is unset` for `(unset)`. Its
    hookSpecificOutput assertions are also the positive for this scenario's
    "hookSpecificOutput is absent" negative.

  `run_session_start` builds a payload byte-identical to this scenario's. D
  shows the controls red on a message emitted whether or not jq is present. The
  scenario comment now names them (Minor 3).
- **"contains `jq`" strength.** The message is static and the outline pins no
  wording beyond "jq is missing", so naming jq is the right claim. The weakness
  was accidental satisfaction. `mktemp -d` gives a random suffix of 10
  alphanumerics, so the sandbox path contains `jq` in about 0.2% of runs, and a
  GREEN whose jq-less message carries a path would then pass on the path alone.
  The filter now cuts `$sandbox` out of the message before searching
  (`split($s) | join("")`, literal, not a regex).
- **ANSI reset and parse.** `startswith("\u001b[0m")` compares against a jq
  string literal. A GREEN that writes a raw ESC byte into the JSON is rejected
  by "stdout is one JSON object": jq 1.7 refuses unescaped control characters
  (probed, exit 5), and so do Node's `JSON.parse` and Python's `json`. So the
  suite's jq is at least as strict as Claude Code's parser on this point.
  Residual: this rests on the suite's jq being ≥1.7. An older jq was not probed.
- **Does the payload matter?** Not to a correct GREEN: stdin is not read, and a
  GREEN without jq could not parse it anyway. It is kept so that stdin is
  byte-identical to the jq-present controls, which is what makes the pairing
  exact. It is built before PATH narrows because `run_session_start` needs jq to
  build it, which is also why the scenario does not call that helper.
- **PATH contents.** Session-start needs `dirname` (`root_dir`), and
  `run_dogfood` needs `bash`, `mkdir` and `cat`. `make_jqless_bin` supplies
  exactly those, and A goes green under them. None of them parses JSON.
- **Bare negative.** "hookSpecificOutput is absent" reds on empty stdout today,
  because `jq -e` over no input exits 4. Its positive is the unset warn test,
  described above.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **Variable set by `export`/`unset` rather than prefix**
   - Location: tests/dogfood-test.sh, the scenario's loop
   - Note: this departs from the suite's session-start convention and exports
     the variable at script scope for the length of a run.
   - **Status**: FIXED. The `(unset)` run passes only `PATH=`. The
     `(names-the-copy)` run passes `CLAUDE_CODE_PLUGIN_DIRS=… PATH=…` as
     prefixes. The `export` and both `unset`s are gone.
2. **"names jq" satisfiable by the random sandbox path**
   - Location: tests/dogfood-test.sh, the `systemMessage names jq` assertion
   - Note: the old filter passes a path-bearing message whenever the `mktemp`
     suffix contains `jq`. Probe C passed the old filter and fails the new one.
   - **Status**: FIXED. The filter now reads
     `split($s) | join("") | contains("jq")` with `--arg s "$sandbox"`, plus the
     suite's SC2016 disable comment.
3. **Controls not named**
   - Location: tests/dogfood-test.sh, the scenario comment
   - Note: nothing told a reader that the jq-present runs of the same two cases
     already exist.
   - **Status**: FIXED. The comment names both tests, and says why the sandbox
     is cut out before the search.

## Fixes Applied

- tests/dogfood-test.sh, the scenario comment: four lines added naming the
  jq-present controls and the reason for stripping the sandbox path.
- tests/dogfood-test.sh, the loop: prefix assignments replace `export`/`unset`.
- tests/dogfood-test.sh, `systemMessage names jq`: the sandbox path is cut out
  before `contains("jq")`.
- Re-run: the same 10 assertion failures, none elsewhere. `shellcheck` is clean.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| jq-less PATH, variable unset → stdout parses | Satisfied (red, awaiting GREEN) | `(unset)`: one-object check, read with the suite's jq |
| `.systemMessage` starts with `\u001b[0m` and contains `jq` | Satisfied | two `jq_holds`; the jq check is hardened against the path |
| `.hookSpecificOutput` absent | Satisfied | `has("hookSpecificOutput") \| not`; positive in the unset warn test |
| Interfaces: the copy check is skipped | Satisfied | `(names-the-copy)`; probe B reds only there |
| Interfaces: exit 0, no stderr | Satisfied | `assert_eq` on rc and err in both runs |
| Fixture: `command -v jq` precondition | Satisfied | passes; mechanism probed in 1.2/5 |

## Positive Observations

- The `(names-the-copy)` run goes past the slice text and pins the Interfaces
  line "the copy check is skipped". Probe B shows that it is the run that
  excludes the stderr-suppressing GREEN.
- The payload is built with the real jq before PATH narrows, byte-identical to
  `run_session_start`'s, so the jq-present tests pair with this scenario
  exactly.
- The RED report explains why `(names-the-copy)` passes its exit-code and stderr
  checks today, instead of leaving it looking like a gap.

## Recommendations

- GREEN: at the top of `session_start`, once `copy` is set (or before it, since
  `dirname` is on the PATH), guard with `command -v jq >/dev/null`. On a miss,
  print a static single-quoted JSON object with the `\u001b[0m` escape written
  as JSON text, not a raw byte, and `exit 0`. Do not redirect jq's stderr.

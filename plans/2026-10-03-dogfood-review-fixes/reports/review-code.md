# Review: dogfood review fixes — code and tests

**Scope**: `git diff f7a9bcf0c9f75f8ccdc67acd6d2d02895045b90e` over
`toolkit/bin/claude`, `toolkit/dogfood.sh`, `toolkit/install.sh` (Next steps
`echo` lines as shell code only), `tests/dogfood-launcher-test.sh`,
`tests/dogfood-pre-tool-test.sh`, `tests/dogfood-session-start-test.sh`
**Date**: 2026-10-03T22:45:28+02:00 **Mode**: review + fix

## Summary

The shim's sync condition (Major 1), the not-started line (m3), the jq status
mapping in `pre-tool` (m1), and the test changes (m10, m11, m12) match the
outline. All three mutations run here redded the suites: a conditional
payload-`cwd` root, a logical shim root, and a logical `root_dir`. The
payload-`cwd` mutation is the one specific attention item 1 asked for. Fixes:
the m12 move had dropped the negative half of the case it moved, so that half is
restored. The m10 decoy `cwd` now comes from one payload helper instead of three
copies. A redundant `unset` is removed.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **m12 move dropped the case's negative half**
   - Location: `tests/dogfood-session-start-test.sh`, scenario "session-start
     invoked through a symlinked repo matches the physical copy". Compare the
     baseline `tests/dogfood-launcher-test.sh`, which held the `session_start`
     helper and its two assertions.
   - Problem: the launcher-suite case had two halves, run through the same
     symlinked spelling. One asserted silence on the copy the shim exported. The
     other asserted that another repo's copy is rejected, naming the physical
     copy. Only the silence moved, and silence is a bare negative. Decision 3
     says "move, don't relabel", which means moving the whole case.
   - Fix: added the paired positive over the same fixture.
     `CLAUDE_CODE_PLUGIN_DIRS=/elsewhere/dist/plugin` now gets
     `assert_session_warns "$label" "$root"`, so the warning must name the
     physical copy. The comment now names the pairing. Mutation check:
     `root_dir`'s `cd -P` was changed to `cd` in place and restored by the
     inverse replacement (sha256 matched and `git diff --quiet` passed after the
     restore). Under that mutation both halves redded, 3 failures in all.
   - **Status**: FIXED

2. **Decoy payload `cwd` spelled at three payload sites**
   - Location: `tests/dogfood-pre-tool-test.sh`, which builds payloads in
     `run_pre_tool`, the jq-less control and the deny-build control.
   - Problem: m10 added `--arg cwd "$sandbox/elsewhere"` to each hand-built
     payload separately. Any new payload site has to remember the decoy, or it
     quietly stops pinning that the root is not taken from the payload.
   - Fix: added a `pre_tool_payload <tool> <field> <path>` helper that carries
     the decoy and its rationale. `run_pre_tool` and both controls now use it.
     The conditional-`cwd` mutation reran against the refactored suite and
     redded with 69 failures. Those include both controls, which shows the
     helper's decoy reaches them.
   - **Status**: FIXED

3. **Redundant `unset CLAUDE_CODE_PLUGIN_DIRS` in "the shim syncs before exec"**
   - Location: `tests/dogfood-launcher-test.sh`, in that scenario.
   - Problem: the preamble already unsets the variable, and it says scenarios
     rely on its absence. A `VAR=x run_claude` prefix on a function call does
     not outlive the call in bash. So the second `unset` guards a state that
     cannot occur, and it departs from the session-start suite's convention of
     relying on the preamble.
   - Fix: removed it. The scenario's label still names the unset case.
   - **Status**: FIXED

## Specific attention items

### 1. m10 mutation proof

Reproduced in place by exact-string replacement in `toolkit/dogfood.sh`
`pre_tool`. After the existing `root=` lines, the mutation reads the payload,
takes `.cwd // empty`, and replaces `root` with `cd -P` of that `cwd` only when
it is present. Otherwise the script's own root stands. It then re-feeds the
payload on stdin with `exec <<<"$payload"`.

- Current suite against the mutation: **red**. The deny scenarios fail: Edit,
  NotebookEdit, the symlinked repo, the symlink to the copy, and `..` into the
  copy. "a path outside the repo" fails the other way: it is denied, because it
  sits under the decoy's `dist/plugin/`.
- The suite at the baseline (pre-m10, no `cwd` in payloads) against the same
  mutation: **green**, all scenarios passed. It ran from a temporary
  `tests/.baseline-pre-tool-test.sh`, so `repo_root` binds as it does in
  production, and that file was removed afterwards. So the new `cwd` field is
  exactly what catches a cwd-derived root.
- Restore: inverse replacement. Afterwards `sha256sum -c` printed OK and
  `git diff --quiet toolkit/dogfood.sh` passed, both times the mutation was
  applied.

No test fix was needed for m10 itself.

### 2. Suite lengths

Line counts after the fixes: launcher 429, pre-tool 448, session-start 345.
Judgement: **no action**. Each suite has one script under test and is one
cohesive group of end-to-end scenarios. The overage is bounded, at 7% and 12%.
Splitting off pre-tool's jq-failure group, the natural seam at about 90 lines,
would mean:

- copying roughly 100 lines of harness, since each suite keeps its own;
- editing the suite enumeration in `CLAUDE.md`, plus the justfile wiring;

all to save about 50 lines over the cap. That trade loses. Nothing was crammed:
the helper fix kept lines at or under 80 columns. If pre-tool grows again, the
jq-failure scenarios (silent without jq, fails loudly, the two exit-2 mappings)
are the seam to split along.

### 3. Conventions

- One script under test per suite: holds. The launcher suite now runs only the
  shim, and the session-start case lives in the session-start suite.
- Each suite has its own harness copy: holds. No sourcing was introduced.
- Whitespace safety: the stub directories hold spaces (`stub bin`,
  `failing rsync`). The glob-named consumer `my [consumer]` pins the literal
  match. The shim's comparison and the `|| exit 1` captures quote throughout.
- bash 3.2 / macOS: the code uses `${VAR-}`, `(( ))`, `+=`, `local` in a
  function, `grep -cE` with POSIX classes, and `grep -qxF`. All are portable.
  The jq stubs use `#!/bin/sh` and POSIX `case`/`for`. No GNU-only flags were
  introduced.

## Fixes Applied

- `tests/dogfood-session-start-test.sh`, symlinked-invocation scenario: added
  the paired warn assertion, with another repo's copy in the variable and the
  physical copy named, and extended the comment.
- `tests/dogfood-pre-tool-test.sh`: added a `pre_tool_payload` helper that
  carries the decoy `cwd`. `run_pre_tool` and the two control payloads now use
  it.
- `tests/dogfood-launcher-test.sh`, "the shim syncs before exec": removed the
  redundant `unset CLAUDE_CODE_PLUGIN_DIRS`.

Verification:

- `shellcheck` is clean on all three suites.
- Each suite passes standalone.
- `just precommit` exited 0, run in the foreground.
- Commit `58f24a1` is unchanged; the three edits are in the working tree only.
- Every mutation was restored, and the sha256 matched each time.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| Major 1: skip the sync only when the variable equals `<root>/dist/plugin` (physical root); export in every case | Satisfied | `toolkit/bin/claude` `main`. The literal quoted comparison is against the `cd -P` root. |
| Major 1: launcher scenarios (unset syncs; equal skips the sync and still execs with the variable; another path syncs and overrides) | Satisfied | Launcher scenarios "the shim syncs before exec", "a variable equal to this copy skips the sync" (reached through a symlinked spelling), "an inherited variable is overwritten", "a variable listing this copy among others syncs" and the glob-named case. The logical-root shim mutation redded 4 assertions. |
| m1: `pre-tool` never exits 2 on a jq failure; status 1; the suite asserts the exact status | Satisfied | Both jq calls in `pre_tool` carry `\|\| exit 1`. Three scenarios assert `rc == 1`: real jq 1.7 (exits 5), a stub exiting 2 on the read, and a stub exiting 2 on the deny build. |
| m3: one `dogfood:` not-started line; the sync's stderr kept; non-zero exit | Satisfied | The shim's `status` capture plus its one `echo`. The suite counts exactly one matching line, checks the sync's or rsync's own line, and checks a status of 1 or 23. |
| m10: `pre-tool` payloads carry a `cwd` pointing elsewhere | Satisfied | `pre_tool_payload`. The conditional mutation redded the current suite and passed the baseline suite. |
| m11: "the shim exports the copy" exports `CLAUDE_PROJECT_DIR` pointing elsewhere | Satisfied | That scenario sets `CLAUDE_PROJECT_DIR="$sandbox/elsewhere"` on a decoy that sync accepts. |
| m12: the symlinked-spelling `session-start` case moves to the session-start suite | Satisfied (after fix) | Both halves are now in the session-start suite; the launcher suite tests only the shim. |
| `install.sh` Next steps lines as shell code | Satisfied | Plain literal `echo`, matching the steps above it. Wording is left to the docs review. |

**Gaps:** none.

---

## Positive Observations

- The glob-named consumer `my [consumer]` makes an unquoted-comparison mutation
  observable. A bracket class matches its own letters but not the literal `[`.
- The `not_started_re` regex requires `claude` to stand as a word, so
  `.claude-plugin` and a `$TMPDIR` such as `/tmp/claude-1000` cannot satisfy it.
- The failing-rsync stub, which exits 23, separates passing the status through
  from a fixed `exit 1`, which the manifest refusal alone cannot.
- The deny-build stub hands every call except the decision build to the real jq.
  So the payload is read and judged as in production before the second failure.
- The `pre_tool` comment states why the status is 1 and never jq's own: jq exits
  2 on usage errors and on 1.6 parse errors. jq 1.7 behaviour was checked
  locally: 5 on a parse error, 2 on an unknown option.

## Recommendations

- If `tests/dogfood-pre-tool-test.sh` grows further, split off the jq-failure
  scenarios as their own suite, still testing the same script. That costs the
  harness copy and the `CLAUDE.md` suite enumeration update noted above.

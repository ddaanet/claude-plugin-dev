# Review: Item 2.2/5 code review — a fresh settings.json carries all three hooks

**Scope**: `toolkit/install.sh` step 3 as it stands after slices 2.2/1–2.2/5:
the unified seed and pipeline, `add_hook`, the step-3 comments, the error line,
the `cmp` guard, the write-through, and the header's step 3. Tests only for
whether they exercise the change. **Date**: 2026-09-30 **Mode**: review + fix
(TDD code review, after GREEN, last slice of Item 2.2)

## Summary

The GREEN is correct. A missing `settings.json` now runs the same three
`add_hook` stages as an existing one, seeded with `{}`. The separate `jq -n`
document is gone, and with it the one path that wrote a toolkit-only document.
Two defects were fixed:

- the error line claimed a rewrite of a file that, in the fresh case, did not
  exist;
- the seed was captured into a variable outside the guarded pipeline, so a read
  failure bypassed the one error branch.

The comment block was also re-paragraphed. Item 2.2 is complete against the
runbook.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **Error line inaccurate in the fresh case**
   - Location: `toolkit/install.sh`, step 3's error branch.
   - Note: `could not rewrite $settings — left unchanged.` presumes a file to
     rewrite. The fresh case's reachable failure is a missing `jq`: the
     pre-flight runs `jq empty` only when `settings.json` exists, so with no
     file and no `jq`, stages 2–4 fail and the line reported a rewrite of a file
     that was never there. Probed: three `jq: command not found` lines, then the
     old error line, exit 1, `.claude/` empty. The new line,
     `could not wire the hooks into $settings — nothing written.`, is true in
     both cases. No test pins the old text.
   - **Status**: FIXED

2. **Seed read outside the guarded pipeline**
   - Location: `toolkit/install.sh`, `seed="$(cat "$settings")"` then
     `printf '%s\n' "$seed"`.
   - Note: jq output is the same either way. Probed: a file with no trailing
     newline comes out identical, since `$(…)` strips trailing newlines and
     `printf '%s\n'` re-adds one, and jq ignores trailing whitespace. A NUL
     byte, which bash ≥ 4.4 would drop from the substitution, never gets that
     far: the pre-flight `jq empty` rejects it. What the capture does cost:
     - the read ran after `mktemp` but outside the `{ …; } || { …; }` group, so
       a `cat` failure exited through `set -e`, leaked the tmp file and skipped
       the error line. That contradicted the comment's claim that a failure only
       ever errors through that branch. It is practically unreachable, because
       the pre-flight has already opened the file;
     - a second in-memory copy of the file and a strip-and-re-add round trip,
       with no benefit.

     The seed is now the pipeline's first stage:
     `if [ -f "$settings" ]; then cat …; else echo '{}'; fi | add_hook …`. A
     compound command as a pipeline element is POSIX and bash 3.2. Under
     `pipefail`, a failure of that stage reaches the error branch. It can take a
     SIGPIPE only when a jq stage has already exited early, which is itself a
     failure.
   - **Status**: FIXED

3. **Comment block run together**
   - Location: step-3 comment above `add_hook`.
   - Note: the identity-rule paragraph started on a short line glued to the
     previous paragraph
     (`# A hook counts as present when any entry under its event`), which was
     left over from the slice's edit. "Both cases" also named cases the sentence
     had not introduced. The block is now two paragraphs, the first opening with
     "An existing file and a missing one run the same pipeline" and saying that
     a failure in any stage takes the one error branch. Everything is reflowed
     at 80 columns.
   - **Status**: FIXED

## Checks performed (no finding)

- **No path writes a stub over an existing `settings.json`.** The only write is
  `cat "$tmp" > "$settings"`, and `$tmp` is always the three-stage output over
  the file itself when `[ -f "$settings" ]`. The `{}` seed is reached only when
  no regular file exists. Probed with `.hooks.SessionStart: {}`, which fails
  stage 3 alone: jq's diagnosis, the error line, exit 1, and `cmp` against the
  original shows it unchanged.
- **pipefail per stage.** The group is the left operand of `||`, so errexit is
  off inside it, but `pipefail` carries the status of any non-final stage. Stage
  1 (read or seed), each `add_hook` (its last command is jq, so it returns jq's
  status) and the `> "$tmp"` redirect all land in the error branch.
- **`cmp` guard and write-through.** They are unchanged from 2.2/1 and keep that
  review's properties. A re-run on an existing file is byte-identical and prints
  `already installed, nothing to do`. A fresh file is created at the umask
  (probed: `644`), not at mktemp's `0600`. `[ -f ]` short-circuits `cmp` in the
  fresh case, so the write always happens there.
- **Fresh output shape.** Probed: `{"PreToolUse":2,"SessionStart":1}` entry
  counts; the suite pins matchers and commands.
- **bash 3.2 / BSD.** The change uses `if … fi |`, `cat`, `echo` of a fixed
  literal, `cmp -s` and `mktemp` with no template. Nothing is GNU-only.
- **Header and coherence.** Header step 3 ("wire the version-guard and dogfood
  hooks") and the `changed` line ("wired the version-guard and dogfood hooks")
  are accurate for both cases. "Idempotent" still holds: the suite's re-run and
  matcher-rescoped `cmp` cases pass.
- **Tests exercise the change.** Slice 5's assertions red against the old
  `jq -n` branch (RED report) and pin all three hooks on the fresh path. No
  suite exercises the error branch. The 2.2/1 review already recommended a case
  for it, and it is not repeated as a finding.

## Mutated-SUT run

Not run. The forbidden implementation this slice rules out is the old
version-guard-only fresh document, and the RED run was already a run against
exactly that SUT. The test review's four in-place mutations of the fresh branch
(reordered, mis-scoped pre-tool, SessionStart with a matcher, correct GREEN)
cover the rest.

## Fixes Applied

- `toolkit/install.sh` step-3 comment: re-paragraphed and reflowed. It now names
  the two cases explicitly and says that a failure in any stage takes the one
  error branch.
- `toolkit/install.sh` pipeline: the `seed` variable and its `if` block are
  replaced by an `if … fi` first stage that emits the file or `{}` inside the
  guarded group.
- `toolkit/install.sh` error line: now
  `error: could not wire the hooks into $settings — nothing written.`

After the fixes:

- `shellcheck toolkit/install.sh` and `bash -n` are clean.
- `bash tests/update-plugin-dev-test.sh` reports
  `update-plugin-dev scenarios passed`.
- The probes above were re-run and gave the results shown: fresh with no jq,
  stage-3 failure, a file with no trailing newline, and a fresh install.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D11: one function of (event, matcher, command), called three times, no-settings branch included (seed `{}`) | Satisfied | `add_hook`; one pipeline for both cases |
| D11: new entries, pre-tool on `Write\|Edit\|NotebookEdit`, SessionStart with no matcher | Satisfied | pipeline stages 3 and 4; fresh probe |
| D11: idempotency, present = same event and command, any matcher | Satisfied | `add_hook` presence test; slices 2 and 4 pass |
| D11: quoted `"${CLAUDE_PROJECT_DIR}"` in the new commands, `hook_cmd` unchanged | Satisfied | `pretool_cmd`, `session_cmd`, `hook_cmd` literals |
| Header step 3 and `changed` line name all three hooks | Satisfied | both say "version-guard and dogfood hooks" |
| D6/D7 wiring in a fresh install | Satisfied | slice 5 assertions |

## Deferred Items

- **Moving install.sh's scenarios into their own suite.** Reason: Scope OUT
  (outline item 4, phase-boundary work).

## Positive Observations

- Unifying the two cases removed the stub-writing branch, where 2.2/1 had only
  guarded against reaching it. The hazard the old comment warned about is now
  impossible by construction.
- The fresh case gained an error line. Before the slice, a missing `jq` there
  exited 127 through `set -e`, with no message of the script's own and with the
  tmp file leaked.

## Recommendations

- **Pre-existing, not raised as a finding: an input with no JSON value passes
  the pre-flight and wires nothing.** `jq empty` accepts an empty or
  whitespace-only file, and jq then emits nothing through all three stages.
  Probed:
  - a zero-byte `settings.json` gives `already installed, nothing to do`, and no
    hooks are wired;
  - a whitespace-only file is overwritten with an empty file and reported as
    `wired the version-guard and dogfood hooks`.

  Both are false success messages. A file holding two documents is likewise
  rewritten as two documents, each with the hooks added. The step-3 code before
  Item 2.2 (`jq … "$settings"`) behaves identically, so this is outside the
  diff. The natural fix is in the pre-flight: require exactly one object, for
  example `jq -s -e 'length == 1 and (.[0] | type) == "object"'`. Whether an
  empty file should instead be seeded like a missing one is a design choice for
  my human partner.
- **Pre-existing: a fresh install with no `jq` fails only after the subtree add
  and the justfile edit.** The pre-flight checks `jq` only when `settings.json`
  exists. A `command -v jq` check beside it would fail fast in both cases. This
  is outside the diff; the slice's change only made that failure print a line.

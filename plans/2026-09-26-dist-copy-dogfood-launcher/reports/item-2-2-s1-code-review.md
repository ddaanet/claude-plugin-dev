# Review: Item 2.2 slice 1 — install wires the dogfood hooks (code review)

**Scope**: `toolkit/install.sh` as changed by the slice's GREEN commit (subject
`Item 2.2/1 — install wires the dogfood hooks`). That covers step 3's
`add_hook`, the chained pipeline, `pretool_cmd` and `session_cmd`, the header's
step 3, and the `changed` line. The no-settings branch is slice 5's work, and
the tests are out of scope except for judging whether they exercise the change.
**Date**: 2026-09-30 **Mode**: review + fix

## Summary

The step-3 refactor is correct. Nothing in it is a correctness defect.

- `add_hook` implements the Interfaces' identity rule exactly.
- A failure in any stage of the three-stage pipeline exits 1 with the error line
  and leaves `settings.json` byte-identical.
- Every illegal settings shape is refused loudly, and every legal-but-odd shape
  is handled.

The fixes are to wording: two comments had gone inaccurate, and the `changed`
line claimed an addition that had not happened.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **`changed` line reports version-guard as added when it was already present**
   - Location: `toolkit/install.sh`, the `changed+=` line after the `cmp`.
   - Note: the line prints whenever the file changes. The common re-run case is
     an existing consumer that already has version-guard and gains only the two
     dogfood hooks. Probed on a fixture with version-guard under matcher `Bash`,
     the output read `(added version-guard and dogfood hooks)`, although only
     the dogfood hooks were added. Changing the verb to "wired" makes the line
     describe the file's resulting state. No test pins this text.
   - **Status**: FIXED

2. **Identity-rule comment gave a reason that does not support the rule**
   - Location: `toolkit/install.sh`, the step-3 comment block.
   - Note: the comment said the matcher is not part of the identity because "an
     entry with no matcher is legal and matches every tool". That argues for
     counting a matcher-less entry as present. It does not argue for counting an
     entry under `Bash` as present, which the rule (Interfaces: "whatever the
     entry's matcher, or none") also does. The comment now gives the reason that
     covers both cases: the consumer may have rescoped the entry, and a second
     copy would run the command twice wherever the matchers overlap.
   - **Status**: FIXED

3. **"nothing but one hook" goes stale at slice 5**
   - Location: same comment block.
   - Note: the slice changed "this hook" to "one hook". Slice 5 seeds the
     no-settings branch with all three hooks, so the phrase would become false.
     "nothing but the toolkit's hooks" is true before and after slice 5. The
     comment's opening line also now reads "Append each hook", since there are
     three.
   - **Status**: FIXED

## Checks performed (no finding)

- **Failure under `set -euo pipefail`.** The pipeline is the left operand of
  `||`, so errexit is off inside it, but `pipefail` still carries a non-final
  stage's status. Probed through the real `install.sh`, with
  `.hooks.SessionStart` set to `{}` so that only stage 3 fails:
  - jq's diagnosis appeared, followed by
    `error: could not rewrite .claude/settings.json — left unchanged.`;
  - the exit status was 1;
  - `cmp` against the pre-run copy showed the file unchanged.

  When stage 1 fails, stages 2 and 3 get empty stdin, emit nothing and exit 0,
  and `pipefail` still reports stage 1's status. `add_hook`'s last command is
  jq, so the function returns jq's status.
- **jq on odd shapes.** Probed `add_hook` against each shape; each gave the
  result shown.

  | Shape | Result |
  |---|---|
  | `{}`, top-level `null` | hooks added |
  | `.hooks: null` | hooks added |
  | `.hooks.<event>: null` | hooks added |
  | an entry without `hooks` | kept, and the new entry appended |
  | `hooks: null` inside an entry | kept, and the new entry appended |
  | an existing command under matcher `startup` | no-op |
  | a non-object `.hooks` (array, string) | refused, exit 5 |
  | an object-valued `.hooks.<event>` | refused, exit 5 |
  | a string entry | refused, exit 5 |
  | a string hook | refused, exit 5 |
  | a top-level array | refused, exit 5 |

  Every refused shape is one Claude Code would reject too, so refusing loudly
  with the file unchanged is the right outcome, and none of them needs handling.
- **Identity rule.** `.hooks[$event][]? | .hooks[]? | select(.command == $cmd)`
  matches the Interfaces: present means some entry under the same event carries
  the command, whatever its matcher, a missing one included. A fixture with
  version-guard under matcher `Bash` gained only the two dogfood entries. The
  re-run printed `already installed, nothing to do`. This also relaxes
  version-guard's old null-or-`Write|Edit` test, which is the change slice 4
  pins. Its mutation is to restore that test.
- **SC2016 and the single-quote convention.** Both new command strings are
  single-quoted literals. Each carries its directive with the reason as a second
  comment, which is the form shellcheck parses. `hook_cmd` keeps its unquoted
  spelling, as the runbook requires. Extending CLAUDE.md's `hook_cmd`
  Conventions bullet to the two new strings is Item 3.6's job, per the runbook,
  so it is not raised here.
- **bash 3.2 and BSD.** The change uses a plain function, a `{ …; } || { …; }`
  group and `cmp -s`, and jq's `//=`, `if/then/else/end` and `.[$var]`. All of
  these work in jq 1.5 and later, and in bash 3.2.
- **Unquoted heredocs.** The change touches none.
- **Later slices can still red or be proven by mutation.** Slice 5 reds on the
  untouched no-settings branch. Slices 2 to 4 pass against this GREEN and need
  the mutations the runbook names. Nothing in the fixes changes behaviour.

## Mutated-SUT run

One in-place mutation, targeting the forbidden shape the slice rules out: a
SessionStart entry carrying a `matcher` key. The replacement was exact-string:

- before: `(if $matcher == "" then {} else {matcher: $matcher} end)`
- during the run: `{matcher: $matcher}`

`bash tests/update-plugin-dev-test.sh` failed one assertion:

```text
FAIL: install adds the session-start hook once: expected 'none', got 'matcher='
1 failure(s)
```

The inverse replacement restored the file.
`git diff --stat -- toolkit/install.sh` was empty afterwards, which verifies the
restore; the fixes above were applied after that check.

## Fixes Applied

- `toolkit/install.sh` step-3 comment: "Append the hook" became "Append each
  hook", and "nothing but one hook" became "nothing but the toolkit's hooks".
  The identity rule's rationale was replaced with one that covers a rescoped
  matcher as well as a missing one.
- `toolkit/install.sh` `changed` line: "added" became "wired", so the line is
  accurate when version-guard was already present.

After the fixes:

- `shellcheck toolkit/install.sh` is clean.
- `bash tests/update-plugin-dev-test.sh` reports
  `update-plugin-dev scenarios passed`.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| D11 refactor: one function of (event, matcher, command) | Satisfied | `add_hook`, called three times in the existing-settings branch; slice 5 extends the calls to the no-settings branch |
| D11 new entries: `PreToolUse` `Write\|Edit\|NotebookEdit` → pre-tool; `SessionStart`, no matcher → session-start | Satisfied | the pipeline's stages 2 and 3; the `$matcher == ""` branch omits the key |
| D11 idempotency: present = same event and same command, any matcher | Satisfied | the filter's presence test, plus the `Bash`-matcher probe |
| D11 quoting: `"${CLAUDE_PROJECT_DIR}"` in the new commands, version-guard unchanged | Satisfied | `pretool_cmd` and `session_cmd` are single-quoted literals; `hook_cmd` is untouched |
| D6/D7 wiring | Satisfied (existing settings) | the no-settings branch is slice 5 |
| Header step 3 and `changed` line name the hooks | Satisfied | both name the version-guard and dogfood hooks |

## Deferred Items

- **The no-settings branch still writes only version-guard.** It is slice 5's
  job, per the runbook.
- **CLAUDE.md's `hook_cmd` single-quote Conventions bullet does not yet cover
  `pretool_cmd` and `session_cmd`.** Item 3.6 owns that edit.

## Positive Observations

- The commands reach jq through `--arg`, so the quotes and `${…}` pass through
  literally with no escaping in the filter.
- The fail-closed structure survived the move from one jq to a pipeline. There
  is still one error branch, the `cmp` guard is unchanged, and the write still
  goes through the destination, which keeps its mode.
- The `if $matcher == ""` construct emits no key at all, rather than a `null` or
  empty-string matcher, which is the shape the test pins.

## Recommendations

- No suite exercises the `could not rewrite … left unchanged` path. It was
  verified here by a probe only, and the pipeline is the new code that path
  guards. A case whose settings have an object-valued `.hooks.SessionStart`
  would show the path. It would fail only in stage 3, which also covers the
  `pipefail` concern, and would assert exit 1, the error line and a `cmp`
  against the original. It fits the phase-boundary cleanup that moves
  install.sh's scenarios into their own suite. It is not a finding here, since
  tests are out of this review's scope.

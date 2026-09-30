# Review: Item 1.3/1 code review — `session-start` external contract

**Scope**: `session_start`, its comment block, and the header and routing lines
in toolkit/dogfood.sh, as committed in HEAD
(`Item 1.3/1 — session-start warns off the copy`). The tests are out of scope
and were not edited. **Date**: 2026-09-30 **Mode**: review + fix

## Summary

`session_start` is minimal. It takes `<root>` from `root_dir`, stays silent when
the variable equals `<root>/dist/plugin` exactly, and otherwise builds one
object with `jq -nc --arg`. It does not read stdin, and nothing is spliced into
the output. Both channels carry the path. The agent channel states a fact and
offers no route around it. Two minor issues were fixed. The function comment
claimed behaviour that belongs to 1.3/2, and the user line used a `;` separator
where the in-file and skill convention is an em-dash.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **Comment promises the per-entry match early**
   - Location: toolkit/dogfood.sh, the `session_start` comment block
   - Note: "A session that does not load `<root>/dist/plugin` gets one object
     and otherwise nothing" is an iff claim about loading. The code compares the
     whole variable against the copy. A session with
     `/x/other:<root>/dist/plugin` does load the copy, yet today it gets the
     warning, so the comment describes 1.3/2 and not this code. The same
     sentence repeated the file header's "never the payload's cwd". That is
     implied by "the payload is not read", which stays.
   - Fix: the comment now reads "Silent when `CLAUDE_CODE_PLUGIN_DIRS` is
     exactly `<root>/dist/plugin`; any other value, unset included, gets one
     object." 1.3/2 rewrites this line when it adds splitting. The header's
     "warn when this session does not load" is the subcommand's purpose and does
     not claim "only when", so it stays.
   - **Status**: FIXED
2. **systemMessage separator**
   - Location: toolkit/dogfood.sh, the `systemMessage` string
   - Note: the finding and the remedy were joined by `; `. `pre_tool`'s
     `systemMessage` in the same file uses ` — `, and craft:directive-writing
     sets lowercase plus an em-dash separator for the user channel.
   - Fix: `; ` becomes ` — `. The words are unchanged.
   - **Status**: FIXED

## Wording check (in scope)

- **systemMessage**: one line. It says what is wrong (the session does not load
  the copy, named by absolute path) and gives the remedy the dispatch asks for:
  launch through `plugin-dev/bin/claude`. That is the Phase 2 shim's vendored
  path under install.sh's fixed `TOOLKIT_PREFIX="plugin-dev"`, and the path is
  right. The "from the repo root" clause is redundant for the session that sees
  the message, since project hooks fire only from a root launch
  (`project-hooks-launch-dir`). It is kept on purpose. A user relaunching from a
  subdirectory gets the copy loaded and every project hook silently off, and
  this line is the one place they are told otherwise before the README.
- **additionalContext**: "This session does not load `<copy>`, so plugin
  behaviour observed in it is not that of the promoted copy." This is decision
  7's wording, stated as a fact. It holds no command, no flag and no variable
  name, so it gives the agent nothing to relaunch or re-export. The shim path is
  withheld from this channel and appears only in the user's.

## Mutated-SUT run

`root="$(root_dir)"` in `session_start` was replaced in place with
`root="$CLAUDE_PROJECT_DIR"`, using a perl exact replacement that asserted one
anchor match. This mutation is the plausible-but-forbidden D5 violation.
`run_dogfood` supplies a decoy `CLAUDE_PROJECT_DIR` of `$sandbox/elsewhere`.
Result: 3 failures, all assertion `FAIL:` lines:

- silent test: `prints nothing on stdout`. It warned about
  `…/elsewhere/dist/plugin`.
- warn test: `systemMessage … names the copy`, and
  `additionalContext names the copy`.

The inverse replacement restored the file. `git diff` afterwards showed only the
two fixes above. The test review already reported the always-warn and
payload-`cwd` mutations as red. The "any value silences" mutation stays green
here, which is expected: `<other>/dist/plugin` warning is 1.3/3.

## Fixes Applied

- toolkit/dogfood.sh, the `session_start` comment: states the whole-variable
  equality the code performs, and drops the repeat of the header's cwd clause.
- toolkit/dogfood.sh, `systemMessage`: separator `; ` becomes ` — `.

## Verification

- `bash tests/dogfood-test.sh`: all dogfood scenarios passed, after the fixes
  and again after the mutation was restored.
- `shellcheck toolkit/dogfood.sh`: clean.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| exit 0, stdin not read | Satisfied | `jq -n`; nothing reads fd 0 |
| silent when the variable is `<root>/dist/plugin` | Satisfied (whole-value form) | equality guard; per-entry matching is 1.3/2 (OUT) |
| otherwise one object, `systemMessage` leading with ESC `[0m` and naming the copy | Satisfied | `"\u001b[0m" + …$copy…` |
| `hookEventName = "SessionStart"`, `additionalContext` stating the fact | Satisfied | jq object |
| root from the script's own location (D5) | Satisfied | `root_dir`; the `CLAUDE_PROJECT_DIR` mutation reds |
| no jq on PATH gives a static object | Not in this slice | 1.3/4 (OUT) |

## Positive Observations

- The guard is one line ahead of the jq call, so the silent path forks nothing.
- `root` and `copy` are declared `local` before they are assigned, so a
  `root_dir` failure still stops the script under errexit.
- The object is built with `--arg`, following `pre_tool`, so a spaced or quoted
  root path cannot break the JSON.

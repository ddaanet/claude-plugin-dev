# Item 1.2/1 code review

Scope: `toolkit/dogfood.sh` as changed in the slice commit — `pre_tool`, its
dispatch line, the header. Fixes applied in the working tree, uncommitted.

## Findings and fixes

### Deny wording (major, fixed)

- **The deny reason named `sync`.** "…which sync overwrites" put an identifier
  the agent can act on into the halting channel. An agent refused an edit into
  the copy, holding a `plugin-dev/dogfood.sh` and a `dogfood` recipe in the same
  tree, can reason: edit the source, then run sync to carry the change over.
  That is a mid-session promotion, which decision 4 keeps deliberate (it runs
  half-edited hook scripts in the editing session). "The edit was refused" also
  read as narration after CC's `hook error:` prefix. Now:
  `<path> is in dist/plugin/, the generated copy of this plugin. Edits to the copy are refused.`
  It reads correctly after `PreToolUse:Edit hook error:`, states the verdict as
  fact, and offers no action.
- **`additionalContext` said "that file".** It arrives as a separate attachment,
  not as part of the tool result, so the referent is only implied. Now
  self-contained: `The source of <path> is <src>. Make the edit there.`
  Imperative is correct on this directive channel.
- **`systemMessage` carried an instruction** ("edit the source instead"). The
  user channel is curt and factual, with no actionable phrase, and the
  instruction is the agent's anyway. Now:
  `dogfood: blocked an edit into dist/plugin/ — the generated copy`. It stays
  one line: the edited path is left out, so a name holding a newline cannot
  break the line.

After the fixes the three channels split cleanly: the verdict on
`permissionDecisionReason`, the recovery on `additionalContext`, the notice on
`systemMessage`.

### "exit 0 always" is not what the code does on a bad payload (minor, comment fixed)

Probed. A malformed payload (`{not json`) or a `tool_input` that is not an
object makes jq exit 5 with its own stderr, and errexit ends the script on 5.
Empty stdin exits 0 silently (jq prints nothing, the path is empty). A
`root_dir` failure would behave the same way on its own status. CC treats a
non-2 non-zero exit as a non-blocking hook error: the notice is visible, the
edit proceeds, and CC's own sensitive-file ask still stands before a copy edit
(`reports/probe-hooks.md`, control run).

Behaviour kept. Absorbing the status into `exit 0` would make the failure silent
to everyone. Failing closed with `exit 2` would block every
Write/Edit/NotebookEdit on a payload that tells nothing about the path. Neither
is better than a visible fail-open with a backstop. The header now says "exit 0
on either verdict", and the `pre_tool` comment states the failure path.
**For the planner:** the runbook's Item 1.2 Interfaces line "→ exit 0 always" is
stricter than the code. I left it unchanged. It holds for every verdict, not for
an unreadable payload; slice 1.2/5's no-jq path is a separate case and does exit
0.

### Literal prefix matching (verified, no change)

`"$root/$copy/"*` and `${path#"$root/$copy/"}` quote the variable part, so only
the trailing `*` is a glob. Probed with a root named `a b[c]*?`. A copy path
under it is denied and mapped correctly. A path that the root matches as a glob
but not as a literal (`a bc_X/dist/plugin/f`) is allowed with empty stdout.

### Layout and portability (no change)

`main` dispatches to both entry points; `pre_tool` follows `sync_copy`, and
every helper follows its callers. `root_dir`, shared by both, stays last. The
slice uses bash 3.2 constructs only (`local` with an initialiser and a quoted
`${var#…}` pattern), and jq is called the same way on GNU and BSD. The comment
is accurate: the path is compared as given, and physical resolution is slice
1.2/4.

## Verification

- `bash tests/dogfood-test.sh`: all dogfood scenarios passed.
- `just precommit` (unsandboxed): `ok`, the full suite included.

## Refactor flagged

None.

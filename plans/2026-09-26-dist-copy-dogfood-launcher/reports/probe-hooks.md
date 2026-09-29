# Probe: Q3 and the `CLAUDE_CODE_PLUGIN_DIRS` premises

2026-09-29, Claude Code 2.1.284, run during the `/proof` of `outline.md`.
Outline item 1, run ahead of execution. The subdirectory question is answered in
`probe-subdir-hooks.md`.

## Setup

- A scratch git repo at `/tmp/claude/probe-deny/root`, laid out as a root-layout
  plugin: `.claude-plugin/plugin.json` (`probedeny`), a marker skill
  `skills/probe-marker/SKILL.md`, `notes.txt` holding `alpha`, and
  `/dist/plugin/` git-ignored.
- The copy was synced by hand:
  `rsync -a --exclude=.git --exclude=/dist/plugin/ ./ dist/plugin/`.
- The committed `.claude/settings.json` registers:
  - `SessionStart`, which logs `CLAUDE_CODE_PLUGIN_DIRS`;
  - `PreToolUse` on `Write|Edit|NotebookEdit`, which logs the variable and the
    edited path.
- With `PROBE_DENY=1`, the `PreToolUse` hook denies any path under
  `root/dist/plugin/`, using the three channels D6 specifies
  (`permissionDecisionReason`, `additionalContext` naming the source path,
  `systemMessage`).
- Two unsandboxed runs, the control with `PROBE_DENY=0` and the deny run with
  `PROBE_DENY=1`. Each was:

  ```sh
  env -u <each parent CLAUDE* session variable> \
    CLAUDE_CODE_PLUGIN_DIRS=/tmp/claude/probe-deny/root/dist/plugin \
    claude -p --model haiku --permission-mode acceptEdits \
    --output-format stream-json --verbose "<two Edits>"
  ```

  The prompt asked for one Edit to `root/notes.txt` and one to
  `root/dist/plugin/notes.txt`, each attempted once and not retried.

## Results

| Premise / question | Control (`PROBE_DENY=0`) | Deny run (`PROBE_DENY=1`) |
|---|---|---|
| The copy loads from the variable | init lists `probedeny`, path `root/dist/plugin`, source `probedeny@inline`, skill `probedeny:probe-marker` | same |
| Hooks see the variable | `SessionStart` and both `PreToolUse` calls logged `PLUGIN_DIRS=/tmp/claude/probe-deny/root/dist/plugin` | same |
| A source edit goes through | `The file …/root/notes.txt has been updated successfully.` | same |
| The copy is flagged | `Claude requested permissions to edit …/dist/plugin/notes.txt which is a sensitive file.` (`is_error: true`) | — |
| **Q3: the hook's deny lands before the path-safety `ask`** | — | `PreToolUse:Edit hook error: PROBE-HOOK-DENY: path is the loaded plugin copy` (`is_error: true`). The hook's reason, not the sensitive-file message |
| `additionalContext` reaches the agent on the deny | — | transcript attachment `hook_additional_context`, `hookEvent: PreToolUse`, carrying the denied call's `toolUseID` and `PROBE-CTX: edit the source instead: …/root/notes.txt` |

After the deny run, the source held `beta` and the copy still held `alpha`.

**Q3 is answered yes.** The copy guard works as D6 designs it, and the fallback
is not needed. Every premise D9 takes from the bundle held on 2.1.284.

## Notes

- Claude Code prefixes the deny reason with `PreToolUse:Edit hook error:` in the
  tool result. The reason's own wording should read correctly after that prefix.
- The `systemMessage` line was not searched for in the transcript. It is the
  user channel, and `plugin-craft:hook-authoring` §2 already covers its delivery
  on a deny.
- To re-run this as the drift check (Risks), recreate the scratch repo as above
  and repeat both runs. The evidence is the stream-json tool results and the
  transcript's `hook_additional_context` attachment, both read with `jq`.

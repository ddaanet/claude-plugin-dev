# Probe: do a repo root's project hooks fire from a subdirectory launch? No

2026-09-29, Claude Code 2.1.284, run during the `/proof` of `outline.md` (D9).

## Setup

- A scratch git repo at `/tmp/claude/probe-subdir/root` with a root
  `.claude-plugin/plugin.json` and a committed `.claude/settings.json`.
- The settings register `SessionStart` and `PreToolUse` (`matcher: "*"`), each
  with two command hooks appending to one log:
  - an inline `echo` naming `$CLAUDE_PROJECT_DIR` and `$PWD`, which shows
    whether the settings were read at all;
  - `bash "${CLAUDE_PROJECT_DIR}/hook.sh"`, which shows whether a hook path
    built from the variable resolves.
- Two unsandboxed `claude -p --model haiku` runs, one from `root/` and one from
  `root/sub/deeper/`. The parent session's `CLAUDE*` variables were stripped
  from the environment. Each run was asked to Read `x.txt` in its own cwd, which
  forces a `PreToolUse`.

## Result

- **From the root:** all four entries fired. `CLAUDE_PROJECT_DIR`, `$PWD` and
  the payload `cwd` all named the root.
- **From `sub/deeper/`:** no entry at all. The run completed normally (the Read
  returned `hello`), but neither hook from the root's `.claude/settings.json`
  ran, not even the inline one.

Claude Code read project settings from the launch cwd only. It did not walk up
to the git root.

## Consequence for the outline

A dogfood session launched from a subdirectory loads the copy (the variable is
absolute) but has neither the `pre-tool` copy guard nor the `session-start`
warning. A copy edit still meets the path-safety `ask`.

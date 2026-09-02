# The version-guard hook

Why the hook that refuses agent edits to the manifest version is shaped the way
it is. The conclusion this argument supports is listed in
[../design.md](../design.md).

## Dual-channel hook output

`version-guard.sh` emits two distinct fields when denying an edit:

- `permissionDecisionReason` — verbose, agent-facing. Names the legitimate path
  (`just release …`), forbids workarounds, no escape hatches the agent can
  self-authorise.
- `systemMessage` — one short line, human-facing. Surfaces *that* a block
  happened, not *why* in detail.

This split exists because agents read instructions literally. A diagnostic
message intended for human eyes that says "if you really need to bypass this,
run X" gets parsed as a green light to run X. The agent channel is therefore
worded as unconditional refusal with redirect; the human channel is curt and
informative.

Both fields ride **stdout with exit 0**, which is the only way either is
delivered: Claude Code parses a hook's stdout as JSON, and only on exit 0. A
`permissionDecision` of `deny` there blocks the call exactly as `exit 2` does,
so nothing is lost by not exiting 2 — whereas on exit 2 the JSON is handed to
the model as raw stderr text, and `systemMessage` never reaches the human at
all.

The hook locates the manifest from `CLAUDE_PROJECT_DIR`, never from the
payload's `cwd`. `cwd` tracks the Bash tool's persistent shell and moves with a
`cd` or an /add-dir; a manifest looked up under a drifted cwd is simply not
there, and the hook's own "not my file" path then exits 0. That is a silent,
total bypass of the guard, so there is no fallback to `cwd`. Comparing that path
against `tool_input.file_path` is done by absolutising both in shell rather than
with `realpath -m`, which is GNU-only: on macOS both substitutions come back
empty, the comparison succeeds, and the guard inverts into firing on every file
written. The manifest path is constructed rather than supplied, so symlink
resolution buys nothing that string comparison does not.

The Edit branch applies the edit to the manifest text and re-reads `.version`
from the result. Pattern-matching `new_string` for a `"version"` key was the
obvious cheaper route and is wrong: the shortest edit that bumps the version
replaces the value alone (`1.2.3` → `9.9.9`), carries no key to match, and is
the form an agent reaches for first. The substitution runs through jq's
`split/1`, which splits on a literal string, because JSON punctuation in
`old_string` would be read as a glob by a bash `${text/pat/rep}`. The Write
branch stays a plain jq read of `tool_input.content`, which is already the full
file.

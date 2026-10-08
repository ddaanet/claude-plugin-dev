# The dogfood launcher

Why a consumer's development session loads its plugin from a synced copy, and
why the pieces that keep that copy honest are shaped the way they are. The
conclusions these arguments support are listed in [../design.md](../design.md).
What goes into the copy, when it is promoted and how a failed sync reports are
argued in [dogfood-sync.md](dogfood-sync.md).

## The problem it solves

Claude Code treats every path under an inline plugin root — one loaded by
`--plugin-dir` or `CLAUDE_CODE_PLUGIN_DIRS` — as a sensitive file for `Write`
and `Edit`. A session that loads a plugin from its own working tree therefore
asks before every agent edit to it. It also runs whatever is on disk: a hook
script or a `bin/` file is read on every call, so a half-edited one runs in the
very session editing it.

The launcher separates the two trees. `just dogfood` syncs the plugin into
`dist/plugin/`, and `plugin-dev/bin/claude` starts Claude Code with that copy
loaded. Agents edit the source, which is outside every loaded root, so nothing
prompts. The copy changes only when someone promotes it on purpose.

## A real copy, not a symlink

A symlinked `dist/plugin` would be cheaper and always current, and it does not
work. Claude Code converts each inline root and the edited path through
`fs.realpathSync.native`, walking up to the nearest existing ancestor, before
its is-under test. A symlinked root therefore resolves to the source, and the
source is flagged exactly as if it were loaded directly. That was read from the
Claude Code 2.1.283 bundle
([research Q1](../../plans/2026-09-26-dist-copy-dogfood-launcher/reports/research-probes.md)),
and the Q3 probe below observed the copy flagged while a source edit went
through, on CC 2.1.284.

## One script, three subcommands, rooted at its own location

`toolkit/dogfood.sh` carries `sync`, `pre-tool` (the copy guard) and
`session-start` (the check). Each finds the repo root as the physical parent of
the script's own directory, never from `CLAUDE_PROJECT_DIR` or a hook payload's
`cwd`. A resumed session's `SessionStart` fires with the resuming process's cwd,
which can belong to another repository; the vendored script's location is the
one spelling of the root that cannot drift.

## The copy guard denies; it does not rewrite

`pre-tool` runs on `PreToolUse` for `Write|Edit|NotebookEdit`. It reads the
target as `.tool_input.file_path // .tool_input.notebook_path`, since
`NotebookEdit` names its target `notebook_path` (CC 2.1.283 bundle). Any target
under `<root>/dist/plugin/` is denied, unconditionally: that path is always the
copy, so no marker is needed to know it.

The comparison is made on physical paths. The root is physical, and the target
is resolved one name at a time up to its nearest existing ancestor, the rest
kept as spelled, as Claude Code's own check does; an existing target that is
itself a symlink is resolved in full. Without this, a symlinked spelling of the
repo would let a copy edit through. A leaf symlink that does not resolve —
dangling, looping — is compared as spelled, so a `Write` through a dangling link
into the copy is not refused here.

The deny splits three ways, on stdout with exit 0 like the version-guard's (see
[version-guard.md](version-guard.md)):

- `permissionDecisionReason` states the verdict: the path is in the generated
  copy and edits to it are refused. Claude Code prefixes the reason with
  `PreToolUse:<Tool> hook error:`, so it is worded to read after that. It offers
  no way past the refusal, a sync included: a mid-session sync is a promotion
  nobody asked for.
- `additionalContext` names the source path to edit instead. It arrives apart
  from the tool result, so it names the denied path too.
- `systemMessage` is one line for the human.

**Rejected: an `updatedInput` rewrite to the source path.** It would land the
edit, and it hides the mapping: the agent never learns the copy is not the
source and keeps aiming at it.

In two cases the guard reaches no verdict and leaves the edit to the backstop
behind it, Claude Code's own sensitive-file `ask`, which still stops an edit
into the copy. With no `jq` on PATH, `pre-tool` exits 0 with no output rather
than fail every edit of the session, and `session-start` is where the missing
`jq` is reported. A payload `jq` cannot read, or a directory on the path that
cannot be entered, stops the script with exit 1, which Claude Code shows as a
non-blocking hook error. Any `jq` failure exits 1 with `jq`'s stderr kept, never
with `jq`'s own status: `jq` exits 2 on a usage or system error (1.7 probed),
and exit 2 from a `PreToolUse` hook blocks the tool call. A parse error exits 5
in 1.7 (probed) and 4 in 1.6 (read from its source, not run), so the choice of
exit 1 holds whichever version meets the payload.

## The session check reports; it does not refuse

`session-start` speaks in two cases and is silent otherwise.

**The session does not load `<root>/dist/plugin`.** It was launched past the
shim — no direnv, an IDE or the desktop app, an absolute path to `claude` — or
it inherited another repository's value. The test splits
`CLAUDE_CODE_PLUGIN_DIRS` on `:` and compares each entry whole. An absolute
entry naming a directory that can be entered is resolved physically, because
Claude Code writes the variable back normalized and a symlinked spelling must
still match; any other entry is compared as spelled, trailing slashes stripped,
and a relative one, which Claude Code drops, never matches. A substring or
prefix match would accept `/other/<root>/dist/plugin`. The payload is not read.

The finding goes to both channels. `systemMessage` names the remedy:
`just dogfood` and a relaunch when no `<root>/dist/plugin` directory exists, as
after a shim launch with no copy, else launching through `plugin-dev/bin/claude`
from the repo root. `additionalContext` gives the agent the finding as a fact —
no copy exists, or behaviour observed here is not the promoted copy's — and
nothing to act on: promoting and relaunching are the human's acts.

**`jq` is missing.** There is then no object to build and no copy guard, so the
check is skipped and a static `systemMessage` says so. It stays off the agent's
channel: only the human can install `jq`.

Either line opens with an ANSI reset, so Claude Code does not dim it like
routine hook output. There is no adoption check: every consumer is meant to use
the shim, and the warning is the nudge until it does.

## The shim: `plugin-dev/bin/claude`

A bash script, put first on PATH by the consumer's `.envrc` as
`PATH_add plugin-dev/bin`, after gitlore's `PATH_add .gitlore/bin` so that it
wins. It finds the root from its own location (`<shim dir>/../..`), resolved
physically as `dogfood.sh` resolves its own, exports `CLAUDE_CODE_PLUGIN_DIRS`
at `<root>/dist/plugin` over any inherited value when the copy exists and warns
instead when it does not (see "A launch with no copy warns and starts without
it" in [dogfood-sync.md](dogfood-sync.md)), unsets `CDPATH`, and execs the next
`claude` on PATH with its arguments unchanged — typically gitlore's launcher. It
never syncs.

The next `claude` is found by dropping every PATH entry whose `claude` is the
shim itself (`-ef`), not every entry holding a file of that name, so a trailing
slash, a symlinked directory or `/./` in the entry cannot make the shim exec
itself. An empty entry means the working directory and is tested as `./claude`.
With no other `claude` on PATH the shim exits 127 and says so. The stripped PATH
is exported, so the session and its Bash tool inherit it, and a `claude` an
agent runs there finds the next `claude`, not the shim.

**The variable, not the flag.** `CLAUDE_CODE_PLUGIN_DIRS` takes a `:`-separated
list of absolute local paths, which Claude Code normalizes and writes back into
its own environment (CC 2.1.283 bundle). Unlike `--plugin-dir`, it therefore
reaches hooks and child processes, and that is what `session-start` checks.
Every `claude` through the shim loads the copy when there is one, so a script
that wires the plugin's hooks into its own settings, as gitlore's evals do, runs
them twice: Claude Code does not de-duplicate a hook registered by a plugin and
by a settings file, even with identical command strings, and
`--setting-sources project` does not stop the variable (probed on CC 2.1.294).
Such a script meets it only when the shim is on its PATH and the copy exists.

**Launching from a subdirectory.** The shim does not refuse it. Such a session
loads the copy, because the path is absolute, but none of the root's project
hooks fire: Claude Code reads project settings from the launch directory only,
not the git root (probed on CC 2.1.284,
[probe-subdir-hooks.md](../../plans/2026-09-26-dist-copy-dogfood-launcher/reports/probe-subdir-hooks.md)).
The session has no copy guard, no `SessionStart` check and no version-guard, and
nothing reports their absence. A copy edit still meets the path-safety `ask`,
which is why this is accepted. A warning printed by the shim before its exec
would not help, since the TUI hides it; the manual says to launch from the root.

## `install.sh` wires the hooks, and only the hooks

Step 3 of `install.sh` is one function of (event, matcher, command), called
three times: the version-guard on `PreToolUse` `Write|Edit`, the copy guard on
`PreToolUse` `Write|Edit|NotebookEdit`, and the check on `SessionStart` with no
matcher.

An entry counts as present when any entry under the same event carries the same
command, whatever its matcher, a missing one included. The consumer may have
rescoped a hook, and a second copy beside the rescoped one would run the command
twice wherever the two matchers overlap.

The dogfood commands quote the variable,
`bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" pre-tool`, so a repo path
with a space survives the hook shell. The version-guard's string stays unquoted:
presence is matched on the command string, so changing it would make a re-run
add a duplicate beside every existing consumer's entry.

`.envrc`, `.gitignore` and the consumer's `clean` recipe are documented in the
manual, not edited. The `PATH_add` has to land after gitlore's and needs a
`direnv allow`, and `clean` recipes differ from one consumer to the next. A
missing ignore entry cannot pass unnoticed: `sync` refuses until git ignores
`dist/plugin/`.

## The migration is a note

`update.sh` does not re-run `install.sh`, so a consumer upgrading into the
launcher gets the steps from `migrations/v0.9.0.md`: re-run the installer from
the human's own shell, since the agent's sandboxed Bash cannot write
`.claude/settings.json`; delete any hand-copied `.bin/claude` and its
`PATH_add`, and drop the `.bin` reference from each recipe line, deleting the
line only when that reference is all it checks; add `PATH_add plugin-dev/bin`
last; ignore `/dist/plugin/` and make `clean` spare it.

Those steps break any hand-copied `.bin/claude` shim a consumer carries, and
deliberately so: backward compatibility is not a constraint on what the toolkit
vendors, and a loud failure at update time is preferred to a compatibility path.
The note is named for the release that ships it, because `update.sh` prints the
notes in the range (old, new] and a misnamed one is skipped. Dropping the launch
sync ships `migrations/v0.9.1.md`: run `just dogfood` before the next launch.

## Probe evidence

**Q3 and the premises**
([probe-hooks.md](../../plans/2026-09-26-dist-copy-dogfood-launcher/reports/probe-hooks.md),
CC 2.1.284). A scratch root-layout plugin with its copy loaded through
`CLAUDE_CODE_PLUGIN_DIRS`, run unsandboxed with `claude -p` twice, once with the
deny on and once off:

- the copy loads from the variable, and `SessionStart` and `PreToolUse` hooks
  both see the variable;
- a source edit goes through, and the copy is flagged as a sensitive file;
- a project `PreToolUse` deny lands before the path-safety `ask`: the denied
  Edit's tool result is the hook's reason, prefixed
  `PreToolUse:Edit hook error:`;
- the deny's `additionalContext` reaches the agent, tied to the denied call's
  tool-use id.

**The subdirectory launch**
([probe-subdir-hooks.md](../../plans/2026-09-26-dist-copy-dogfood-launcher/reports/probe-subdir-hooks.md),
CC 2.1.284). From the root every project hook fired; from `sub/deeper/` none
did, not even an inline `echo`, while the session otherwise ran normally.

## Bounds accepted
**Claude Code drift.** The design rests on Claude Code resolving roots through
`realpath`, parsing `CLAUDE_CODE_PLUGIN_DIRS` as above, flagging paths under an
inline root, and letting a hook deny land before the `ask`. A later version may
change any of these. The regression check is the Q3 procedure in
`probe-hooks.md`: recreate the scratch repo, repeat both unsandboxed runs, and
read the stream-json tool results and the transcript's `hook_additional_context`
attachment with `jq`. A sandboxed `claude -p` drops every `SessionStart` hook,
so the probe must run unsandboxed.

**Children inherit the variable.** A `claude` started from a dogfood session's
Bash — a probe, an eval — loads this repository's copy too. Through another
consumer's shim it loads that consumer's copy instead; otherwise its own
`session-start` reports the mismatch when it runs in another consumer.

**Only tool edits to the copy are guarded.** A Bash write into `dist/plugin/`
passes the guard and the path-safety check alike, and the next sync overwrites
or deletes it.

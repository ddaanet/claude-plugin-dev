# The dogfood launcher

Why a consumer's development session loads its plugin from a synced copy, and
why the pieces that keep that copy honest are shaped the way they are. The
conclusions these arguments support are listed in [../design.md](../design.md).

## The problem it solves

Claude Code treats every path under an inline plugin root — one loaded by
`--plugin-dir` or `CLAUDE_CODE_PLUGIN_DIRS` — as a sensitive file for `Write`
and `Edit`. A session that loads a plugin from its own working tree therefore
asks before every agent edit to it. It also runs whatever is on disk: a hook
script or a `bin/` file is read on every call, so a half-edited one runs in the
very session editing it.

The launcher separates the two trees. `plugin-dev/bin/claude` syncs the plugin
into `dist/plugin/` and starts Claude Code with that copy loaded. Agents edit
the source, which is outside every loaded root, so nothing prompts. The copy
changes only when someone promotes it on purpose.

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

## The source set: the whole tree minus what git ignores

`dogfood.sh sync` copies everything git does not ignore, tracked or not.
`git ls-files -z -o -i --exclude-standard --directory` lists the untracked
ignored paths; each entry is anchored with a leading `/` and handed to
`rsync -a --delete --delete-excluded --from0 --exclude-from=-`, along with two
hard excludes:

- `.git`, unanchored, so a nested repository's `.git` — the `memory/` gitlink's,
  for one — stays out too;
- `/dist/plugin/`, the copy itself, so a sync never recurses into it even where
  `dist/` is not ignored. Other build output under `dist/` is expected to be
  git-ignored and drops out through the list.

A tracked file that matches an ignore pattern is kept, because `-o -i` lists
only untracked paths. Deletions propagate: a path that stops being source leaves
the copy.

The exclude list is written out in full before rsync starts. Fed through a pipe,
a git failure would leave rsync running on a partial list — copying `.git` and
recursing into the copy.

Entries are refused rather than escaped. An ignored entry holding `*`, `?`, `[`,
`]` or a backslash aborts the sync, naming the path, before rsync runs or
`dist/` is touched. rsync reads the first four as wildcards, and a backslash
counts as an escape only in a pattern that also holds a wildcard (probed on
rsync 3.5.0), so no escaping is right for every entry. `--directory` collapses a
wholly ignored directory into one entry, so only those collapsed names are
checked, and they are all rsync is given.

**Rejected: a `--files-from` list of tracked and untracked files**, the obvious
source set. It fails twice
([research](../../plans/2026-09-26-dist-copy-dogfood-launcher/reports/research-probes.md)):
deletions do not propagate under `--delete`, and a tracked file deleted in the
worktree but not yet committed is still listed, so every sync exits 23 until the
deletion is committed.

## The plugin root is the repo root

`install.sh` refuses a repo without a root `.claude-plugin/plugin.json`, and
`release.sh` assumes one, so every consumer has the root layout and the sync
copies from the repo root. Nested plugin roots, such as edify's `plugin/`, are
out of scope, as edify is for the release flow.

## Sync only on deliberate promotion

The copy is synced at two moments: every launch through the shim, a relaunch to
resume a conversation included, and `just dogfood`. Nothing syncs it on an edit.

The trade-off follows from what Claude Code re-reads, and when:

- skill bodies need `/reload-plugins` whatever loads them;
- agent definitions and hook events need a new session, which starts through the
  shim and so syncs;
- only hook-script and `bin/` bodies are read on every call.

Syncing on each edit would buy liveness for that last class alone, and that
class is exactly where liveness hurts: a half-edited hook script goes live in
the session that is still editing it. So there is no `PostToolUse` sync, no
liveness marker and no lock. Two syncs that collide fail loudly and succeed on
re-run (see "Sync failure is loud").

A promotion syncs the whole tree however it changed, so a change made through
Bash needs no matcher of its own, and whether `PostToolUse` hooks fire for a
subagent's tool calls does not arise.

**Rejected: sync on edit.** A project `PostToolUse` hook matching
`Write|Edit|NotebookEdit|Bash`, with `PostToolUseFailure` for failing Bash
calls, re-ran the sync after each call, gated by an environment marker so that
only a session launched through the shim synced, and serialized by a `mkdir`
lock with a stale-lock break. It cost a sync on every tool call — a no-op sync
measured 60 to 108 ms across four consumers, `git ls-files` included
([research Q2](../../plans/2026-09-26-dist-copy-dogfood-launcher/reports/research-probes.md))
— and it made half-edited hook scripts live in the session editing them. The
marker and the lock each carried a failure mode of their own, a killed sync
stranding its lock among them, that promotion-only syncing does not have.

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
cannot be entered, stops the script non-zero, which Claude Code shows as a
non-blocking hook error.

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

The finding goes to both channels. `systemMessage` names the remedy, launching
through `plugin-dev/bin/claude` from the repo root. `additionalContext` gives
the agent the same finding as a fact — plugin behaviour observed in this session
is not the promoted copy's — and nothing to act on, since only the human can
relaunch.

**`jq` is missing.** There is then no object to build and no copy guard, so the
check is skipped and a static `systemMessage` says so. It stays off the agent's
channel: only the human can install `jq`.

Either line opens with an ANSI reset, so Claude Code does not dim it like
routine hook output. There is no adoption check: every consumer is meant to use
the shim, and the warning is the nudge until it does.

## Sync failure is loud

A failed sync at launch aborts before exec. `just dogfood` exits non-zero with
rsync's stderr as rsync wrote it. The script never redirects rsync's stderr, not
even to hide the `skipping non-regular file` line the command sandbox provokes,
because a blanket redirect silences every unanticipated message along with the
anticipated one. Each refusal of the sync's own — no manifest, `dist/plugin/`
not git-ignored, a pattern character — is one `dogfood:` line naming the path,
with `dist/` untouched.

## The shim: `plugin-dev/bin/claude`

A bash script, put first on PATH by the consumer's `.envrc` as
`PATH_add plugin-dev/bin`, after gitlore's `PATH_add .gitlore/bin` so that it
wins. It finds the root from its own location (`<shim dir>/../..`), runs
`dogfood.sh sync`, exports `CLAUDE_CODE_PLUGIN_DIRS=<root>/dist/plugin` over any
inherited value, unsets `CDPATH`, and execs the next `claude` on PATH with its
arguments unchanged — typically gitlore's launcher. The manifest and ignore
checks live in `sync`, so `just dogfood` enforces them too.

The next `claude` is found by dropping every PATH entry whose `claude` is the
shim itself (`-ef`), not every entry holding a file of that name, so a trailing
slash, a symlinked directory or `/./` in the entry cannot make the shim exec
itself. An empty entry means the working directory and is tested as `./claude`.
With no other `claude` on PATH the shim exits 127 and says so.

**The variable, not the flag.** `CLAUDE_CODE_PLUGIN_DIRS` takes a `:`-separated
list of absolute local paths, which Claude Code normalizes and writes back into
its own environment (CC 2.1.283 bundle). Unlike `--plugin-dir`, it therefore
reaches hooks and child processes, and that is what `session-start` checks.

**Launching from a subdirectory.** The shim does not refuse it. Such a session
loads the copy, because the path is absolute, but none of the root's project
hooks fire: Claude Code reads project settings from the launch directory only,
not the git root (probed on CC 2.1.284,
[probe-subdir-hooks.md](../../plans/2026-09-26-dist-copy-dogfood-launcher/reports/probe-subdir-hooks.md)).
The session has no copy guard, no `SessionStart` check and no version-guard, and
nothing reports their absence. A copy edit still meets the path-safety `ask`,
which is why this is accepted. A warning printed by the shim before its exec
would not help, since the TUI hides it; the manual says to launch from the root.

## `just dogfood`

A `release.just` recipe, `bash "{{toolkit_prefix}}/dogfood.sh" sync` like its
neighbours: it syncs and nothing else, and starts no `claude`. It depends on no
gate, since it publishes nothing and writes only the git-ignored copy. After it,
a skill body goes live on `/reload-plugins`, and an agent definition or hook
event on a relaunch through the shim.

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
`.claude/settings.json`; delete any hand-copied `.bin/claude`, its `PATH_add`,
and any recipe line naming it; add `PATH_add plugin-dev/bin` last; ignore
`/dist/plugin/` and make `clean` spare it.

Those steps break any hand-copied `.bin/claude` shim a consumer carries, and
deliberately so: backward compatibility is not a constraint on what the toolkit
vendors, and a loud failure at update time is preferred to a compatibility path.
The note is named for the release that ships it, because `update.sh` prints the
notes in the range (old, new] and a misnamed one is skipped.

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

**macOS rsync is unprobed.** The sync was probed with rsync 3.4.1 and 3.5.0 on
Linux only. Recent macOS ships `openrsync` as `/usr/bin/rsync`, older versions
rsync 2.6.9, and whether either accepts `--from0`, `--exclude-from=-` and
`--delete-excluded` together is not established. A failure there surfaces as a
failed sync.

**Benign rsync exits read as failures.** A file vanishing mid-sync makes rsync
exit 24, and two concurrent syncs can collide. Both are reported and repaired by
a re-run: rare false alarms, accepted rather than matched and hidden.

**The copy lags the source by design.** A session runs what was last promoted,
not the working tree, and a Read through a copy path returns promoted content.

**Promotion is repo-wide.** Hook-script and `bin/` bodies are read on every
call, so a launch or `just dogfood` in one session changes what every other live
session in the same repository runs.

**Children inherit the variable.** A `claude` started from a dogfood session's
Bash — a probe, an eval — loads this repository's copy too, unless it goes
through a shim that overwrites the variable. Its own `session-start` reports the
mismatch when it runs in another consumer.

**Only tool edits to the copy are guarded.** A Bash write into `dist/plugin/`
passes the guard and the path-safety check alike, and the next sync overwrites
or deletes it.

**A sandboxed sync cannot read `.mcp.json`.** The command sandbox masks a set of
dotfiles in the project root, and `.mcp.json` is the one plugin component among
them. With a char-device mask rsync prints `skipping non-regular file`, exits 0
and leaves the copy's existing `.mcp.json` alone, so a changed MCP config goes
stale silently (rsync 3.4.1); the zero-byte mask shape, unprobed, would copy an
empty file. It bites only a `just dogfood` run through an agent's sandboxed Bash
— the shim runs in the human's shell — and the manual tells a plugin that ships
a `.mcp.json` to promote from its own shell.

**The copy carries non-plugin content.** Directories such as `plugin-dev/` and
the `memory/` gitlink's files land in `dist/plugin/`. Claude Code loads only the
plugin component directories, so this costs bytes, not behaviour; the Q2 timings
include it.

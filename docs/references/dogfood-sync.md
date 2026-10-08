# The dogfood sync

Why the dogfood copy is the whole tree minus what git ignores, why it is
promoted only by `just dogfood`, and why a failed sync is loud. The launcher
around it — the copy, the guards, the shim and the hook wiring — is argued in
[dogfood.md](dogfood.md), and the conclusions these arguments support are listed
in [../design.md](../design.md).

## The source set: the whole tree minus what git ignores

`dogfood.sh sync` copies everything git does not ignore, tracked or not.
`git ls-files -z -o -i --exclude-standard --directory` lists the untracked
ignored paths, in the root and recursively in each initialised submodule, which
the root's listing never enters (`--recurse-submodules` does not support `-o`).
Each entry, prefixed with its submodule path and anchored with a leading `/`,
goes to `rsync -a --delete --delete-excluded --from0 --exclude-from=-`, along
with two hard excludes:

- `.git`, unanchored, so a nested repository's `.git` — the `memory/` gitlink's,
  for one — stays out too;
- `/dist/plugin/`, the copy itself, so a sync never recurses into it even where
  `dist/` is not ignored. Other build output under `dist/` is expected to be
  git-ignored and drops out through the list.

A tracked file that matches an ignore pattern is kept, because `-o -i` lists
only untracked paths. Deletions propagate: a path that stops being source leaves
the copy. The list is written in full before rsync starts, so a git failure in
any repo stops the sync rather than leave rsync on a partial list.

Entries are refused rather than escaped. An ignored entry holding `*`, `?`, `[`,
`]` or a backslash aborts the sync, naming the path, before rsync runs or
`dist/` is touched. rsync reads the first four as wildcards, and a backslash
counts as an escape only in a pattern that also holds a wildcard (probed on
rsync 3.5.0), so no escaping is right for every entry. `--directory` collapses a
wholly ignored directory into one entry, so only those collapsed names,
submodule prefix included, are checked, and they are all rsync is given.

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

## Sync only on `just dogfood`

The copy is synced at one moment: `just dogfood`. Nothing else promotes it — not
an edit, and not a launch, a relaunch or any other `claude` through the shim,
each of which loads the copy as it stands.

The trade-off follows from what Claude Code re-reads, and when:

- skill bodies need `/reload-plugins` whatever loads them;
- agent definitions and hook events need a new session;
- only hook-script and `bin/` bodies are read on every call.

Syncing on each edit would buy liveness for that last class alone, and that
class is exactly where liveness hurts: a half-edited hook script goes live in
the session that is still editing it. So there is no `PostToolUse` sync, no
liveness marker and no lock. Two syncs that collide fail loudly and succeed on
re-run (see "Sync failure is loud").

A promotion syncs the whole tree however it changed, so a change made through
Bash needs no matcher of its own, and whether `PostToolUse` hooks fire for a
subagent's tool calls does not arise.

The cost is a step. An agent definition or hook event goes live through
`just dogfood` and then a relaunch, two acts where a syncing launch would take
one, and a fresh clone, or a `clean` that took the copy, has none until the
first `just dogfood`.

**Rejected: sync on edit.** A project `PostToolUse` hook matching
`Write|Edit|NotebookEdit|Bash`, with `PostToolUseFailure` for failing Bash
calls, would re-run the sync after each call, gated by an environment marker so
that only a session launched through the shim syncs, and serialized by a `mkdir`
lock with a stale-lock break. It costs a sync on every tool call — a no-op sync
measured 60 to 108 ms across four repositories, `git ls-files` included
([research Q2](../../plans/2026-09-26-dist-copy-dogfood-launcher/reports/research-probes.md))
— and it makes half-edited hook scripts live in the session editing them. The
marker and the lock each carry a failure mode of their own, a killed sync
stranding its lock among them, that promotion-only syncing does not have.

**Rejected: sync at launch.** A shim that synced before its exec would make a
relaunch a promotion. But every `claude` that reaches the shim is a launch to
it, whatever its arguments: `claude --version`, a `claude mcp list` typed in a
second terminal, a script's `claude -p` — gitlore's evals start one per turn
under `just prerelease`. Each would re-promote the tree repo-wide, under every
live session, half-edited hook scripts included, with nobody choosing to:
restarting `claude` is not a decision to ship the working tree. A skip when
`CLAUDE_CODE_PLUGIN_DIRS` already equals the copy would cover only a `claude`
started inside a dogfood session, which the shim's exported PATH strip already
keeps off the shim, and would leave every other launch syncing.

### A launch with no copy warns and starts without it

With no `<root>/dist/plugin` directory, a file in its place included, the shim
prints one line,
`dogfood: no copy at <root>/dist/plugin, so claude starts without it; run just dogfood to create it`,
leaves `CLAUDE_CODE_PLUGIN_DIRS` as it came, and goes on to the PATH strip and
the exec. The session starts without the copy, and `session-start` names
`just dogfood` to the human and states the missing copy to the agent. Exporting
the path anyway would name a plugin dir that is not there, which
`session-start`, comparing entries as spelled, would pass in silence. Creating
the copy would be a sync at launch under another trigger.

**Rejected: refuse the launch.** A shim that exited instead would leave no
`claude` through it while the copy cannot be made — `rsync` missing, say — short
of a hand-typed launch past the shim, in a form for each shell. A warned plain
session costs less, and `session-start` already names it.

Every refusal of the sync, `rsync` missing included, comes before it makes
`dist/plugin` (see "Sync failure is loud"), so a refused first sync leaves no
copy and the next launch warns, rather than loading an empty one in silence. The
check is for presence only: a copy that lags the source is the design.

## Sync failure is loud

`just dogfood` exits non-zero with rsync's stderr as rsync wrote it. The script
never redirects rsync's stderr, not even to hide the `skipping non-regular file`
line the command sandbox provokes, because a blanket redirect silences every
unanticipated message along with the anticipated one. Each refusal of the sync's
own — no manifest, `dist/plugin/` not git-ignored, a pattern character, no
`rsync` on PATH — is one `dogfood:` line naming the path or the command, with
`dist/` untouched.

## `just dogfood`

A `release.just` recipe, `bash "{{toolkit_prefix}}/dogfood.sh" sync` like its
neighbours, and the one promotion: it syncs and nothing else, and starts no
`claude`. It depends on no gate, since it publishes nothing and writes only the
git-ignored copy. After it, a skill body goes live on `/reload-plugins`, and an
agent definition or hook event on a relaunch through the shim.

## Bounds accepted

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
call, so a `just dogfood` in one session changes what every other live session
in the same repository runs.

**A sandboxed sync cannot read `.mcp.json`.** The command sandbox masks a set of
dotfiles in the project root, `.mcp.json` the one plugin component among them,
and the sync does not exclude the masks, which are untracked and not ignored. A
char-device mask makes rsync print `skipping non-regular file`, exit 0 and leave
the copy's existing `.mcp.json` alone, so a changed MCP config goes stale
silently (rsync 3.4.1). A zero-byte read-only mask is copied as an empty regular
file, into a plugin that ships no `.mcp.json` as well, and stays until the next
unsandboxed sync deletes it (probed with a simulated mask on rsync 3.5.0, in the
deliverable review's code report); how Claude Code treats an empty plugin-root
`.mcp.json` is unprobed. The other masked names land the same way and cost
bytes. It bites only a sync run through an agent's sandboxed Bash,
`just dogfood` or `dogfood.sh sync`, since the shim never syncs, and the manual
says to promote from the human's own shell.

**The copy carries non-plugin content.** Directories such as `plugin-dev/` and
the `memory/` gitlink's files land in `dist/plugin/`. Claude Code loads only the
plugin component directories, so this costs bytes, not behaviour; the Q2 timings
include it.

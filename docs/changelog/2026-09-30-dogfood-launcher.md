# 2026-09-30 — The dogfood launcher: consumers load their plugin from a synced copy

A consumer plugin developed in a session that loads it from its own working tree
pays twice. Claude Code runs a path-safety check that returns `ask` for every
path under an inline plugin root, ahead of the acceptEdits auto-allow and any
allow rule, so each agent edit to the plugin stops on a prompt and auto mode
gets no classifier verdict; edify's `/build` stalled across five unattended legs
on it. And hook scripts and `bin/` files are read on every call, so a
half-edited hook runs in the session that is editing it.

The consumers made it worse, not better. Every one keeps its manifest at the
repo root, four of them — craft, cwd-safety, handoff and sandbox-lies — launched
through hand-copied `.bin/claude` shims, and cwd-safety's, handoff's and
sandbox-lies's passed the repo root as the plugin root, which made every edit
anywhere in those repos a sensitive-file edit. craft's had already moved to a
stopgap copy of its own, `.claude-plugin/` and `skills/` only, rebuilt at each
launch. The copies had drifted: craft's and sandbox-lies's unset `CDPATH`,
handoff's and cwd-safety's did not. The requirements came in as a brief from an
edify session, `plans/2026-09-26-brief-dist-copy-dogfood-launcher.md`.

## What landed

The toolkit ships the launcher, so the four shims collapse into one vendored
copy and every other consumer gains it:

- `toolkit/bin/claude`, the shim: syncs the plugin tree into `dist/plugin/`,
  exports `CLAUDE_CODE_PLUGIN_DIRS` at the copy, and execs the next `claude` on
  PATH;
- `toolkit/dogfood.sh`, with `sync`, the `pre-tool` copy guard and the
  `session-start` check;
- a `dogfood` recipe in `release.just`, which syncs and does nothing else;
- `install.sh` wiring the two hooks beside the version-guard, through one
  idempotent function whose presence test ignores the matcher;
- `migrations/v0.9.0.md`, named for the minor bump the release is planned as;
- the manual's `## Dogfooding` section, a pointer from the root README, and the
  design node `docs/references/dogfood.md` with its hub group.

Cutting the toolkit release is a separate, user-triggered `just release`, not
part of this change.

## Sync-on-edit was designed first and rejected in review

The brief proposed syncing the copy from a `PostToolUse` hook after each edit,
and the first outline built on it: the matcher widened to
`Write|Edit|NotebookEdit|Bash` once a no-op sync measured about 0.1 s, with
`PostToolUseFailure` for failing Bash calls, an environment marker so only a
shim-launched session synced, and a `mkdir` lock with a stale-lock break. The
outline review then had to close a stranded-lock failure and a subdirectory case
in that machinery.

My human partner rejected the design: it cost a sync on every tool call, and it
made half-edited hook scripts live in the session editing them — the one class
of file for which liveness was the whole point. The outline was rewritten around
promotion only, at launch and by `just dogfood`. That removed the marker, the
lock and every `PostToolUse` question at once, and answered two of the brief's
open questions by making them moot: changes made through Bash, and whether
`PostToolUse` fires for subagent tool calls.

## The probes

Three sets, all kept with the plan:

- `reports/research-probes.md` (2026-09-26, rsync 3.4.1, CC 2.1.283 bundle): a
  symlinked root is `realpath`-resolved and flags the source, so the copy must
  be real; the brief's `--files-from` source set neither propagates deletions
  nor survives a deleted tracked file; a no-op sync costs 60 to 108 ms.
- `reports/probe-hooks.md` (CC 2.1.284): a project `PreToolUse` deny lands
  before the path-safety `ask`, its `additionalContext` reaches the agent, and
  every `CLAUDE_CODE_PLUGIN_DIRS` premise held. The planned fallback for a deny
  that arrived too late was not needed.
- `reports/probe-subdir-hooks.md` (CC 2.1.284): project hooks do not fire from a
  subdirectory launch. The review had proposed refusing such a launch; it ships
  without the refusal, documented instead, since a copy edit there still meets
  the path-safety `ask`.

## Where the shipped code departs from the outline

Recorded because the outline is frozen and a reader comparing the two would
otherwise take these for drift:

- `sync` writes the ignore list to a temporary file before rsync starts rather
  than piping `git ls-files` into it, so a git failure cannot leave rsync
  running on a partial list and copying `.git`.
- `pre-tool` also resolves an existing target that is itself a symlink, in full,
  and compares a dangling leaf link as spelled. A payload `jq` cannot read exits
  non-zero, a non-blocking hook error, with the path-safety `ask` still behind
  it.
- `session-start`'s human line names the remedy — launch through
  `plugin-dev/bin/claude` from the repo root — where the outline described only
  the finding.
- The shim strips its own PATH entries with parameter expansion, not the
  `paste`-based loop the outline took from sandbox-lies's shim.
- The migration note tells the human to re-run `install.sh` from their own
  shell, since an agent's sandboxed Bash cannot write `.claude/settings.json`.
- The outline's macOS fallback — naming a Homebrew rsync in the manual and in
  `sync`'s failure — was not built, because the failure it answers is not
  established. The manual lists plain `rsync`, and the gap is a stated
  limitation.

## Left to another repository

gitlore's `GITLORE_AUTO_CLAUDE_PLUGIN_DIR` adds `--plugin-dir .`, which would
load the source tree on top of the copy. The shim does not work around it; the
removal belongs to gitlore and went there as
`gitlore/inbox/2026-09-29-brief-remove-auto-plugin-dir.md`, sequenced with
gitlore adopting the shim.

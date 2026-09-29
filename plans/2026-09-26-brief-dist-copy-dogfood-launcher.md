# Brief: dogfood launcher loads the plugin from a synced copy

2026-09-26

From an edify session. The toolkit should ship a dev launcher that dogfoods a
plugin from a synced copy of its tree, not from the tree being edited. Nothing
here is implemented. The design below was agreed with my human partner in edify.
The open questions are still open.

## Problem

Claude Code treats every path under an **inline plugin root** as a sensitive
file. An inline plugin root is a `--plugin-dir` or `--plugin-dir-no-mcp`
argument, or a `CLAUDE_CODE_PLUGIN_DIRS` entry. The Edit/Write permission
function runs its path safety check (`checkPathSafetyForAutoEdit`) before the
acceptEdits auto-allow and before any settings allow rule. For an inline plugin
root that check returns `ask`. As a result:

- acceptEdits still prompts on every edit, often with no reason shown.
- An `Edit(<root>/**)` allow rule is never consulted, whatever its scope.
- Auto mode returns "classifier gave no verdict (it skipped this action)".
- Subagents are affected too, because the inline-plugin list is session-wide.

This was verified by reading the CC 2.1.283 bundle. The durable record is the
ddaanet memory fact `cc-plugin-dir-edits-sensitive`. It was written from edify
and reaches this repo's `memory/ddaanet/` after edify publishes it and this repo
runs `/gitlore:merge`. The raw probe notes are in edify's scratch file
`tmp/cc-plugin-path-probe.md`. That file is gitignored and may be gone. Renaming
the directory changes nothing: what triggers the check is that the directory is
loaded.

**It costs more in the toolkit's consumers than in edify.** Every consumer keeps
its manifest at the repo root, and craft, cwd-safety and handoff launch through
a `.bin/claude` shim with `--plugin-dir <repo root>`. That makes every edit
anywhere in those repos a sensitive-file edit, not only edits to plugin files.
edify loads `--plugin-dir <root>/plugin`. It stalled `/build` across five
unattended legs because the first Edit under `plugin/` could not pass.

The shims are hand-copied and have already drifted. craft's copy has an
`unset CDPATH` line that handoff's and cwd-safety's do not.

## Decisions

- **Load a copy, edit the source.** The launcher syncs the plugin tree into
  `dist/plugin/` and starts `claude --plugin-dir <repo>/dist/plugin`. Agents
  edit the source tree, which is outside every loaded root, so nothing prompts.
- **Sync at launch**, with `rsync -a --delete`, so the copy starts every session
  matching the source, deletions included.
- **Sync on edit** with a project `PostToolUse` hook matching `Edit|Write`. When
  `tool_input.file_path` is under the plugin source, the hook re-runs the same
  sync. The next read of the copy then sees the edit.
- **Wire it the way `install.sh` wires `version-guard.sh`**: an idempotent entry
  in the consumer's `.claude/settings.json`. The toolkit is not a plugin, so a
  plugin `hooks.json` is not available.
- **`dist/plugin/` survives `clean`.** A consumer's `clean` that wipes `dist/`
  (edify's does: `rm -rf dist`) must spare `dist/plugin/`. Otherwise a running
  session loses its loaded plugin mid-flight. The toolkit does not own
  consumers' `clean` recipes, so the README states the requirement. The copy is
  gitignored.

## Constraints

- **Root-layout plugins.** When the plugin root is the repo root, a plain
  `rsync -a --delete <root>/ dist/plugin/` would copy `.git`, `dist/` itself and
  the dev environment. Pick the source set explicitly. One option is
  `git ls-files -z -co --exclude-standard` fed to rsync with `--from0`.
  Deletions must still propagate: a skill removed from the source must disappear
  from the copy. `--files-from` does not do that under `--delete` without more
  work, so a test has to prove it. Get the plugin root from the manifest's
  location (`dirname` of `.claude-plugin/`), not from a hard-coded `plugin/`.
- **Compose with other shims.** The current shims chain to the next `claude` on
  PATH, typically gitlore's `.gitlore/bin` launcher, and strip their own
  directory from PATH so the two do not exec each other forever. The shipped
  launcher keeps that behaviour.
- **Sync failure is loud.** If rsync fails in the hook, exit 2 with the error on
  stderr so the agent learns the copy is stale. If it fails at launch, abort the
  launch. A stale copy looks exactly like a working one.
- **Whitespace-safe throughout**: NUL-delimited path lists, quoted expansions.
  The hook reads `file_path` from JSON with `jq`, not by splitting text.
- shellcheck-clean, with tests in the style of `tests/*-test.sh`, and
  `just precommit` green.

## Open questions

1. **Symlinked `--plugin-dir` is untested.** If `dist/plugin` were a symlink to
   the source, no sync would be needed. The permission function iterates over
   several path "spellings", and that suggests a resolved symlink would still be
   flagged. Probe it before building the sync. Default: assume it is flagged and
   build the copy.
2. **Changes made without Edit or Write.** `git checkout`, `git stash`, `rm` and
   `mv` run through Bash and bypass an `Edit|Write` hook. Options: add `Bash` to
   the matcher (costs one rsync per Bash call), or sync on `UserPromptSubmit` as
   well. Default: match `Bash` too, if a no-op rsync on a plugin-sized tree
   turns out cheap when measured.
3. **Edits aimed at the copy.** Skill invocation reports the base directory of
   the loaded copy, so an agent following it will read and try to edit
   `dist/plugin/...`. That edit prompts, and the next sync would overwrite it.
   Consider a `PreToolUse` deny on the copy whose message names the source path
   to edit instead. Verify that the hook fires before the safety check's `ask`.
   Default: ship the deny.
4. **Subagent coverage.** Confirm that project `PostToolUse` hooks fire for
   subagent tool calls, so a dispatched executor's edits sync too.
5. **Launch vehicle.** A toolkit-shipped shim that consumers put on PATH via
   `.envrc`, replacing the three hand copies, or a `release.just` recipe.
   Default: the shim, since `PATH_add .bin` is how these repos launch today.

## Rejected approaches

- **Allow rules** (`Edit(/plugin/**)` in any settings scope). The safety check
  returns before any allow rule is read. Only session rules rooted at
  `/.claude/**` or `~/.claude/**` are checked earlier.
- **Renaming the plugin directory.** No list of flagged paths contains its name.
  Being loaded is the trigger.
- **Launching without `--plugin-dir`.** Edits then go through, but the session
  runs the installed release rather than the tree under development, which
  defeats the purpose of dogfooding. edify is using this as a stopgap for one
  resumed run only.

## Consumers

craft, cwd-safety and handoff have root-level `.bin/claude` shims to replace.
edify vendors nothing from the toolkit (ddaanet memory `edify-release-flow`).
Whether edify vendors this piece or keeps a local port is edify's decision and
does not block shipping here.

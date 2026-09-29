# Recall Artifact: dist-copy dogfood launcher

Read each file listed below — do not rely on inline summaries.

## Entries

- memory/feedback_plugin_dev_no_backcompat.md — replacing the consumers'
  hand-copied shims may break them; a migration note, not a compat path
- memory/ddaanet/sessionstart-resume-cwd.md — why `dogfood.sh` finds the repo
  from its own location, not the payload cwd or `CLAUDE_PROJECT_DIR`
- memory/ddaanet/cc-agent-discovery.md — agent definitions are cached per
  session: only a restart through the shim makes an edited agent live
- memory/ddaanet/hook-output-channels.md — the `session-start` warning leads
  with an ANSI reset so it is not dimmed as hook chatter
- memory/ddaanet/sandbox-effects.md — phantom `.mcp.json` char devices (rsync
  prints `skipping non-regular file`, exits 0); a sandboxed `claude -p` drops
  `SessionStart` hooks, so the probe runs unsandboxed
- memory/ddaanet/no-stderr-suppression.md — that rsync warning is not a licence
  for `2>/dev/null`

### Added at `/runbook` (implementation focus)

- memory/ddaanet/cc-plugin-dirs-env-var.md — the variable's format and
  normalisation: what `session-start` compares against and what the shim exports
- memory/ddaanet/project-hooks-launch-dir.md — why no slice tests hook firing
  from a subdirectory: the shim still execs there, the hooks simply never run
- memory/ddaanet/reflow-joins-field-lines.md — the runbook's field lines are
  nested bullets, or `just format-docs` merges them into prose
- memory/precommit-intermittent-suite-failure.md — a `release-test.sh` or
  `version-guard-test.sh` failure inside a slice's `just precommit` is re-run
  standalone before it is read as a regression

## Skills to load before executing

- plugin-craft:hook-authoring — the three-way deny split for the copy guard;
  `systemMessage` as the `session-start` channel
- plugin-craft:verifying-plugin-changes — what `/reload-plugins` refreshes and
  what needs a restart; the basis of decision 4
- shell-scripting:shell-gotchas — GNU vs BSD (no `sed -z` on macOS), bash 3.2,
  whitespace-safe NUL lists
- craft:directive-writing — wording of the copy-edit deny and the
  `session-start` warnings
- craft:test-discipline — the deletion-propagation and deleted-tracked-file
  tests must be red against the naive `--files-from` sync

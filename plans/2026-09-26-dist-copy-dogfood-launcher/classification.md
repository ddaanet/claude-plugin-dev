# Classification

- **Classification:** Complex
- **Implementation certainty:** Low — four of the brief's open questions hinge
  on unprobed Claude Code behaviour (symlinked `--plugin-dir`, `PreToolUse` deny
  ordering against the path-safety `ask`, project `PostToolUse` firing for
  subagent calls, cost of a no-op rsync per Bash call), and one on an unproven
  rsync property (`--files-from` with `--delete` removing a deleted source
  file). Each answer can change the architecture: a working symlink removes the
  sync entirely.
- **Requirement stability:** Moderate — the core decisions (load a copy, sync at
  launch and on edit, settings.json wiring, `dist/plugin/` spared by `clean`)
  are agreed; launch vehicle and Bash coverage are open with stated defaults.
- **Behavioral code check:** Yes — a new launcher script, a new hook script, new
  `install.sh` wiring branches.
- **Work type:** Production
- **Artifact destination:** production (`toolkit/`, shipped to every consumer)
- **Evidence:** brief's Open questions 1–5 and Constraints; recall
  `plugin-dev-no-backcompat` (replacing the three hand-copied shims may break
  consumers freely), `claude-project-dir` (hook resolves the root from
  `CLAUDE_PROJECT_DIR`), `cc-agent-discovery` (agent definitions cached per
  session, bounding what sync-on-edit refreshes).

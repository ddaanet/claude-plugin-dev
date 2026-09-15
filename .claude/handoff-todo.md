## Open decisions

- Outline Open question 1: a marketplace entry that disagrees with the manifest on an initial release loops between the `check-version.sh` drift refusal and resume's no-tag refusal. Default: keep the refusal, make its hint initial-release aware. Alternative: skip `check-version.sh` when no semver tag exists.
- Outline Open question 2: the version-guard deny message when the tag listing fails (git absent, not a repo). Default: the steady-state message.

## Remaining

- Run the Codex review of the outline and fold its findings in.
- /proof the outline, then route to /runbook per /edify:design's Moderate path.
- Item B from the brief — README note on `sandbox.excludedCommands` for the marketplace push — stays a separate change and needs checking against current Claude Code first.
- After the toolkit release, drop a note (not an edit) for `plugin-craft:toolkit-release`, whose first-release wording will change.
- Root `memory/MEMORY.md` is over Claude Code's loader cap — the gitlore hook reports 103% of its 25600-byte budget — so entries past the cutoff never reach a session. Parked deliberately; `/gitlore:index-audit` is the pass that addresses it. Raise it only if asked.

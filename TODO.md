## Open decisions

- Approve the memory commit of memory/ddaanet/shared-claude.md: the 400-line cap is hard for design docs and implementation, soft for plans. Summary proposed: "shared-claude: the 400-line cap is soft for plans".
- tests/docs-test.sh and tests/line-cap-test.sh enforce the 400-line cap as a hard gate over plans/, but my human partner ruled the cap soft for plans: decide whether plans/ leaves the hard gate (warn instead) or stays gated in this repo.
- inbox/brief-remove-claude-exemption.md is on hold: gitlore, cwd-safety, onekeys, candidature and this repo track .claude/handoff-*.md, shell-gotchas tracks .claude/handoff-session, and every consumer tracks .claude/gitlore-hook-setup.

## Remaining

- Verify handoff's first opted-in release (origin dist, dist-vX.Y.Z, marketplace ref: dist).
- Cut toolkit 0.10.1 (release-bare fix, splits, line-cap gate) when my human partner runs `just release`.
- After 0.10.1 ships: delete memory/ddaanet/release-bare-not-bypass-flag.md and its index lines in memory/MEMORY.md and memory/ddaanet/MEMORY.md, and delete inbox/brief-release-bare-not-bypass-flag.md.
- Migrate consumers to the new toolkit, per repo with consent: gitmoji, cwd-safety, onekeys (0.6.x), shell-gotchas (0.7.1), candidature (0.7.2), gitlore (0.9.3); install.sh from my human partner's shell where dogfood hooks are not yet wired.
- plugin-craft:toolkit-release could also link plugin-dev/docs/dist-branch.md; add to /Users/david/code/plugin-craft/inbox/brief-toolkit-release-bare-call.md or a new note.

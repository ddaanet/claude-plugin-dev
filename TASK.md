## Current task

Release `dev` onto `main` as the toolkit's next version through the full release
ritual. Since v0.16.0, `dev` carries two consumer-facing toolkit fixes (a
release from `dev` refuses before any commit when another worktree holds `main`;
`move_main` prints git's own refusal above its hint) plus self-release-only
fixes and a CLAUDE.md rule that root-level scripts are not hardened to match
`toolkit/`. The working tree holds a moved `memory` gitlink and a formatter
rewrap of TASK.md, which ride the first commit the ritual makes. Siblings last
batch-migrated to 0.15.0 (handoff, plugin-craft, sandbox-lies, shell-gotchas);
0.16.0 is breaking with a migration note. First action: invoke the
`release-ritual` skill.

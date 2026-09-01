## Open decisions

None.

## Remaining

- Exclude `.claude` from `release.sh`'s dirty check, alongside the `memory` gitlink it already excludes — a staged handoff frame is not work a release should refuse over. Then update `ddaanet/claude-plugin-dev`, whose `error: uncommitted changes` section describes the current behaviour.
- Cut a release so consumers get both halves of the 2026-09-01 shell audit. v0.7.0 shipped the rest; version-guard's four fixes are in the tree, uncommitted.
- Root `memory/MEMORY.md` is ~26.1KB against Claude Code's ~24.4KB loader cap, so its tail never reaches a session. Parked deliberately, not pending — raise it only if asked, or if a lost pointer actually costs something.

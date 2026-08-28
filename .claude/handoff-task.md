## Current task

Three threads.

The toolkit thread has closed the subagent audit: all six ranks landed, the last being rank 6 — `common_preflight`'s hardcoded `memory` pathspec, now read from `.gitmodules` keyed on the submodule name `gitlore-memory`. What remains on that thread is cutting the 0.6.1 patch that carries the five fixes to consumers.

The dist-ref propagation is unfinished. onekeys, shell-gotchas and handoff still carry the leaked `plugin-dev/` paths, each blocked by its own uncommitted tracked work, each with a `brief-plugin-dev-0.6.0.md` in place. onekeys is furthest behind — still at 0.5.3, still tracking `plugin-dev/CLAUDE.md` and `plugin-dev/.claude/settings.json`.

Separately, a design discussion on simplifying toolkit install/update was interrupted during context-gathering, before any design was presented.

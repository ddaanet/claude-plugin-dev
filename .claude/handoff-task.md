## Current task

Three threads.

The toolkit thread works the subagent audit at `brief-audit.md` in its own severity order. Ranks 1 through 5 have landed: the refused-commit manifest rollback, the writability probe keeping mktemp's own words, the errexit-position comment in `common_preflight`, and the `push_branch` failure hint together with the ancestor invariant that makes a `refresh_release_commit` amend unnecessary. Rank 6 is the last item and the only one still carrying an open fix-shape decision. Its brief, `brief-release-sh-two-nits-from-gitlore-audit.md`, stays at the repo root until nit 2 lands; every closed brief is filed under `plans/` with its own date.

The dist-ref propagation is unfinished. onekeys, shell-gotchas and handoff still carry the leaked `plugin-dev/` paths, each blocked by its own uncommitted tracked work, each with a `brief-plugin-dev-0.6.0.md` in place. onekeys is furthest behind — still at 0.5.3, still tracking `plugin-dev/CLAUDE.md` and `plugin-dev/.claude/settings.json`.

Separately, a design discussion on simplifying toolkit install/update was interrupted during context-gathering, before any design was presented.

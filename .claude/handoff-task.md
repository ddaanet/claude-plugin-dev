## Current task

Three threads.

A subagent audit of the six pending briefs landed at `brief-audit.md` and
drives the toolkit thread: two briefs were still open, one reports no defect
but carries three optional items, three were already closed. The
highest-severity item is fixed — a consumer `pre-commit` hook refusing the
release commit no longer strands the manifest bump — and the four closed
briefs now sit in `plans/` under their own dates. The audit's remaining ranks
are unimplemented, and none of the fixes have reached a released `dist-` tag,
so consumers still run the unguarded script.

The dist-ref propagation is unfinished: onekeys, shell-gotchas and handoff
still carry the leaked `plugin-dev/` paths, each blocked by its own
uncommitted tracked work, each with a `brief-plugin-dev-0.6.0.md` in place.
onekeys is the furthest behind — still at 0.5.3, still tracking
`plugin-dev/CLAUDE.md` and `plugin-dev/.claude/settings.json`.

Separately, a design discussion on simplifying toolkit install/update was
interrupted during context-gathering, before any design was presented.

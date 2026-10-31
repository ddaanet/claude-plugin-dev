# Brief: ship the 400-line cap check to consumers

From a handoff (autodrive-handoff) session, 2026-10-30. A proposal, not a
decision.

## What happened

handoff's agent instructions carry the 400-line hard cap on source files, tests
and design docs, and its precommit has nothing holding it:
`tests/hook-test.bats` reached 3985 lines and `scripts/_lib.sh` 689 before
anyone counted. handoff is splitting its oversized files now and wants a gate to
keep them under the cap.

The toolkit already has the check, `tests/line-cap-test.sh`, but only as its own
suite. Nothing under `toolkit/` ships it, so every consumer either keeps a copy
that drifts or goes without. handoff chose not to keep a copy and to adopt the
toolkit's through `just update-plugin-dev` once it ships.

## What a consumer would need

- A script under `toolkit/` that a consumer's `precommit` can call, or a cached
  gate in `gates.just`, using the same scope as `line-cap-test.sh`: every file
  git does not ignore, tracked or not, except `plans/`, `docs/changelog/`,
  gitlinks, symlinks and binary files. The report would stay
  `oversized-file: <path>: <n> lines > 400`.
- A way for the consumer to exempt a path and give its reason. handoff needs two
  exemptions: a test file that a dated deletion pass removes whole (splitting it
  first would be wasted work), and its `CLAUDE.md` until that gets its own
  split. How the consumer declares an exemption is the toolkit's call.
- Markdown under `docs/`: in the toolkit, `docs-test.sh` covers it and
  `line-cap-test.sh` skips it. A consumer that does not also get `docs-test.sh`
  needs the shipped check to count that markdown itself.

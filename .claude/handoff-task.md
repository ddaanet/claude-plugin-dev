## Current task

Two threads. The dist-ref release is out (v0.6.0 plus dist-v0.6.0, the first
to exercise the dist-tag path outside fixtures) and vendored into five of the
eight consumers; onekeys, shell-gotchas and handoff still carry the leaked
`plugin-dev/` paths, each blocked by its own uncommitted tracked work, and each
has a `brief-plugin-dev-0.6.0.md` waiting in place.

Separately, a design discussion was in progress on simplifying how the toolkit
is installed and updated — reaching `toolkit/install.sh` from a sibling
`claude-plugin-dev` checkout instead of a `/tmp` clone, and whether a new
`update.sh` should own consumer-side migrations. It was interrupted during
context-gathering, before any design was presented or approved.

## Open decisions

- Whether `tests/docs-test.sh` keeps its pointer-resolution check or narrows to the line cap alone. The ask was a line-cap check; pointer resolution was added unrequested because the hub-to-node split makes those links load-bearing — a rotted one strands an argument silently.
- Whether `docs/changelog/` stays inside `just format-docs`'s scope. The 2026-09-02 wrap pass reflowed three dated entry bodies (`2026-07-29-resume-release`, `2026-08-28-writability-probe-keeps-mktemps-words`, `2026-09-01-clean-tree-excludes-dot-claude`). Content is byte-identical modulo line breaks, but the project rule is that a dated record is never revised; the alternative is excluding `docs/changelog/` from the wrap.
- The install/update invocation design for the toolkit. The sub-questions from the original brainstorm did not survive into this frame, so they need re-deriving before any design is presented.

## Remaining

- Update the `ddaanet/claude-plugin-dev` memory file, whose `error: uncommitted changes` section still describes `release.sh`'s clean-tree check as it behaved before `.claude` was exempted.
- Root `memory/MEMORY.md` sits over Claude Code's ~24.4KB loader cap, so its tail never reaches a session and the entry falling past the cutoff is this repo's own only project pointer. Parked deliberately — raise it only if asked, or if a lost pointer actually costs something.

## Current task

The `resume-release` implementation plan at `plans/2026-07-29-release-resume-plan.md` was regrouped from eight tasks to five and given mutation-validation steps; nothing in it has been implemented yet, and the execution mode is still the gate on starting Task 1.

The repo's documentation layout changed this session — `docs/` holds only current content (`design.md`, `changelog.md` + `changelog/<date>-slug.md`), `plans/` holds specs and plans. The sibling plugin repos still use the old root `DESIGN.md` + `docs/superpowers/specs/` shape.

## Open decisions

- How to execute the plan: Tasks 1-2 via fresh subagents with a review checkpoint between them (what the plan's header now recommends), or inline throughout.
- Whether the sibling repos (handoff, gitmoji, onekeys, cwd-safety, shell-gotchas, gitlore) migrate to the docs/ + plans/ layout, and whether that happens before or after the 0.5.0 propagation.

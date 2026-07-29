## Current task

The spec and implementation plan for `resume-release` are written and approved; nothing has been implemented yet, and the execution mode is the gate on starting Task 1.

Alongside it, the repo adopted a new documentation layout this session — `docs/` holds only current content (`design.md`, `changelog.md` + `changelog/<date>-slug.md`), `plans/` holds specs and plans. The sibling plugin repos still use the old root `DESIGN.md` + `docs/superpowers/specs/` shape.

## Open decisions

- How to execute `plans/2026-07-29-release-resume-plan.md`: subagent-driven (fresh subagent per task, review between tasks) or inline with checkpoints.
- Whether the sibling repos (handoff, gitmoji, onekeys, cwd-safety, shell-gotchas, gitlore) migrate to the docs/ + plans/ layout, and whether that happens before or after the 0.5.0 propagation.

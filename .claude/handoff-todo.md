## Remaining

- `/edify:deliverable-review plans/2026-10-03-dogfood-review-fixes` on opus, per the task file.
- Dogfood v0.9.0 in one consumer the same day: `just update-plugin-dev dist-v0.9.0` there, then `plugin-dev/migrations/v0.9.0.md`. Another repo, so my human partner runs it or names the one to touch; handoff's justfile exercises the step-2 `.bin/*` case.
- `docs/references/dogfood.md` is at 399 of 400 lines: its next addition needs a split.
- Unprobed, recorded in the dogfood node: hooks firing twice in the gitlore evals under the shim, an empty plugin-root `.mcp.json`, `/reload-plugins` scope for commands/`.mcp.json`/output styles, jq 1.6's parse-error status.

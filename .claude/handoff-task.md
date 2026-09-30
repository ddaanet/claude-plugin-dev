## Current task

`/edify:build plans/2026-09-26-dist-copy-dogfood-launcher` is at the end of Phase 1's planned slices. Items 1.1, 1.2/1–5 and 1.3/1–4 are committed, each with its RED, test-review, GREEN and code-review reports under the job's `reports/`. Next is an added slice, 1.2/6: `pre-tool` follows a symlink at the leaf. The 1.2/4 code review flagged that `physical_path` resolves directories only, so `skills/x.md` linking to a file in `dist/plugin/` passes the guard, though Claude Code's own check `realpath`s the leaf. My human partner noted that macOS 26.6's `readlink` has `-f`, which removes the BSD-portability objection. The proposed shape: when the whole path exists and its leaf is a symlink, resolve it with `readlink -f`, leaving the missing-tail walk as is. The comment above `pre_tool` states the current residual and must change with it. After 1.2/6 comes the Phase 1 boundary (`references/phase-boundary.md`). The build baseline is `fd16ae65f4b244f1098b94b7ee848f5a7f74c8f2`, also stored in `/tmp/claude/dogfood-build/build-baseline`; it stays out of `tmp/` because this repo does not ignore `tmp/`. Section 5 reads it from there.

Conventions this run settled on:
- Dispatches leave the Agent `name` unset (`shared-claude.md` Dispatch).
- A slice whose behaviour an earlier GREEN already implemented is proved by mutation in RED and test review. GREEN and the code review then run in session as short no-diff notes, committed with the slice. A one-line or one-guard implementation gets an in-session GREEN and a self-review note.
- Run `just format-docs` before staging, or the pre-commit hook reflows reports after staging and leaves the tree dirty.
- Commits run unsandboxed, with the hook output captured to a file under `/tmp/claude/dogfood-build/`. The pre-commit hook runs the full `just precommit`, so a commit that lands on a clean tree counts as the post-item verification.
- A transient `.git/index.lock` failure recurs. Check that the lock is gone, then retry.
- A dirty memory submodule makes gitlore refuse every commit until my human partner approves a summary, written to `.claude/gitlore-memory-message`.
- `runbook.md` sits at 399 of the 400-line cap. Keep list revisions line-neutral.

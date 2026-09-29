## Current task

`/edify:build plans/2026-09-26-dist-copy-dogfood-launcher` is mid-Phase 1. Items 1.1 (slices 1–7) and 1.2/1–3 are committed, each with its RED, test-review, GREEN and code-review reports under the job's `reports/`. Next is Item 1.2/4 RED (physical spelling through a symlinked repo), then 1.2/5 and Item 1.3, then the Phase 1 boundary (`references/phase-boundary.md`). The build baseline is `fd16ae65f4b244f1098b94b7ee848f5a7f74c8f2`, also stored in `/tmp/claude/dogfood-build/build-baseline`. It stays out of `tmp/` because this repo does not ignore `tmp/`. Section 5 reads it from there.

Conventions this run settled on:
- Dispatches leave the Agent `name` unset (`shared-claude.md` Dispatch).
- A slice whose behaviour an earlier GREEN already implemented is proved by mutation in RED and test review. GREEN and the code review then run in session as short no-diff notes, committed with the slice. A one-line implementation gets an in-session GREEN and a self-review note.
- Run `just format-docs` before staging, or the pre-commit hook reflows reports after staging and leaves the tree dirty.
- Commits run unsandboxed. The pre-commit hook runs the full `just precommit`, so a commit that lands on a clean tree counts as the post-item verification.
- A transient `.git/index.lock` failure has hit twice. Check that the lock is gone, then retry.
- `runbook.md` sits at 399 of the 400-line cap. Keep list revisions line-neutral.

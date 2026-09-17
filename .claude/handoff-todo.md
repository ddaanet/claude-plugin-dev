## Open decisions

- Publish this repo's own gitlore memory store with `/gitlore:push`? The shared `ddaanet` tier was merged and published on 2026-09-17; the `memory` store's own remote was deliberately left alone, publishing it being wider than the tier merge that was asked for.

## Remaining

- Split `docs/references/recovery.md` (389 lines against the 400-line cap). The obvious cut is by boundary: consumer recovery — `check-version.sh` detection, `resume-release`, the shared release tail, the refusal ladder — against this repo's own release, now `scripts/self-release.sh`. The clean-tree-exclusions section spans both, so it has to be placed rather than simply assigned.
- Split `tests/hook-test.sh` (498 lines) by script under test. Why it was deferred out of Phase 2, and what a split has to solve, is in `plans/2026-09-15-first-release-version/reports/phase-2-corrector.md` section (b).
- `/deliverable-review plans/2026-09-15-first-release-version` (opus, fresh session).
- Root `memory/MEMORY.md` is over Claude Code's loader cap, so entries past the cutoff never reach a session; `/gitlore:index-audit` addresses it. Three facts stay unwritten for that reason: mutation-test a refusal's *prose*, not only its decision; to test a property that a `set -o` line currently masks, run a `sed`-stripped copy of the script with that line removed, as `tests/release-test.sh` now does for `pipefail`; and `git-config-multivalued-read` warns against `git config -z --get-regexp` when the key is interpolated, while `shared-claude.md`'s always-on whitespace rule names that exact form as a default, with no routing cue between them.

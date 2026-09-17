## Open decisions

- Publish this repo's own gitlore memory store with `/gitlore:push`? The shared `ddaanet` tier was merged and published this session; the `memory` store's own remote was deliberately left alone, publishing it being wider than the tier merge that was asked for.

## Remaining

- `toolkit/release.sh:151` cites `outline.md` from shipped code. `toolkit/` is the dist boundary, so a consumer vendors the file and reads a pointer at a document they do not have. Confirmed to be the only such citation anywhere under `toolkit/`.
- Three pre-existing `ls-remote | cut` captures in `release.sh` (recorded around `:438,466,562` during Phase 1, shifted since) fail closed only via `pipefail`. The middle one would skip the "refusing to move a published tag" guard if that ever lapsed.
- Split `tests/hook-test.sh` (498 lines) by script under test. Why it was deferred out of Phase 2, and what a split has to solve, is in `plans/2026-09-15-first-release-version/reports/phase-2-corrector.md` section (b).
- Root `memory/MEMORY.md` is over Claude Code's loader cap, so entries past the cutoff never reach a session; `/gitlore:index-audit` addresses it. The durable lesson this run produced and confirmed twice — mutation-test a refusal's *prose*, not only its decision — stays unwritten for that reason. A second index-audit finding is queued too: `git-config-multivalued-read` warns against `git config -z --get-regexp` when the key is interpolated, while `shared-claude.md`'s always-on whitespace rule names that exact form as a default, and the fact's index line carries no routing cue to it.
- `/deliverable-review plans/2026-09-15-first-release-version` (opus, fresh session).

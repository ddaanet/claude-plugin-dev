## Open decisions

- Commit each pre-run consumer fix in its own repo before my human partner runs tmp/migrate-0.11/migrate.sh? Default: yes, one commit per repo after that repo's precommit passes, nothing pushed.

## Remaining

- Toolkit: add an opt-in `hash-sentinel` to gates.just that re-takes guard_hash after a formatter runs past the guard, so a cached gate skips formatting and a formatting edit needs one run, not two; then move ghmem's run-format after its guard and call hash-sentinel.
- scripts/self-release.sh require_prior_release_published reads a failed `git ls-remote` (sandbox blocking github.com:22) as tags missing on origin, and its hint lists v0.10.0, dist-v0.10.0 and the GitHub release as unpublished when they were all published; refuse with the probe failure instead of the missing-list hint.
- My human partner runs a live dogfood session: `command -v` on a plugin bin/ command resolves in main-thread and subagent Bash; launched before the first `just dogfood`, session-start warns and `/reload-plugins` after the sync loads the copy without a restart (verified headless only).
- release-marketplace.sh rewrites marketplace.json whole in jq's 2-space style on every real bump; edit the version in place instead.
- scripts/self-release.sh common_preflight refuses a dirty tree with a bare "uncommitted changes" naming no path, while toolkit/release-preflight.sh report_dirty names them; make the self-release name the offending paths.
- `just format-docs` runs rumdl over docs/ and plans/ only, so the shipped manual (toolkit/README.md, toolkit/docs/, toolkit/migrations/) is never reflowed and its 400-line count is measured on hand wrapping; widen the recipe's scope.
- toolkit/docs/dist-branch.md: recommend listing `docs` in dist.include so README links into docs/ never dangle in the dist tree, the rule every consumer adopted in the 0.11 migration.
- memory/MEMORY.md is over its byte budget (105%), so its tail is truncated at load: run /gitlore:index-audit when my human partner asks for it.

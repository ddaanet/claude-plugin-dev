## Open decisions

- Commit each pre-run consumer fix in its own repo before my human partner runs tmp/migrate-0.11/migrate.sh? Default: yes, one commit per repo after that repo's precommit passes, nothing pushed.

## Remaining

- Pre-run fix, candidature: harness runs only from the plugin cache. Add a background SessionStart hook (modelled on ghmem hooks/scripts/build-venv.sh: lock, marker, log, one-line systemMessage when node/npm is missing) running `npm ci --omit=dev` in ${CLAUDE_PLUGIN_ROOT}/tools/linkedin-harness; commit a package-lock.json; point the skill reference (edit src/, rebuild with build/build.sh) at the harness under the plugin root and the build log; update README.md line 50; move tools/linkedin-harness/DESIGN.md to docs/linkedin-harness.md (fix harness README line 4 and the D-35 audit row) and test/ to tests/linkedin-harness/ (imports become ../../tools/linkedin-harness/lib/…, package.json test script follows); add a new DESIGN.md decision for the npm SessionStart install with its audit row, update D-35; leave D-34 unchanged. Also replace the DESIGN.md citations in skills soumission.md:151 and consolidation.md:67 with absolute GitHub URLs.
- Pre-run fix, gitlore: quote the 13 unquoted ${CLAUDE_PLUGIN_ROOT} in hooks/hooks.json so `claude plugin validate --strict` passes before its first dist release.
- Pre-run fix, sandbox-lies and prohibitions: README links into docs/ (sandbox-lies README lines 59, 72, 73; prohibitions docs/design.md link) become absolute GitHub URLs, since docs/ does not ship.
- Pre-run fix, shell-gotchas: add an MIT LICENSE, and LICENSE to its dist.include in tmp/migrate-0.11/shell-gotchas/migration.patch.
- Pre-run fix, sandbox-lies: exclude TASK.md and TODO.md from .rumdl.toml's scope (handoff files stay unwrapped), and drop the sandbox-lies reflow_docs step from tmp/migrate-0.11/migrate.sh.
- Toolkit: add an opt-in `hash-sentinel` to gates.just that re-takes guard_hash after a formatter runs past the guard, so a cached gate skips formatting and a formatting edit needs one run, not two; then move ghmem's run-format after its guard and call hash-sentinel.
- scripts/self-release.sh require_prior_release_published reads a failed `git ls-remote` (sandbox blocking github.com:22) as tags missing on origin, and its hint lists v0.10.0, dist-v0.10.0 and the GitHub release as unpublished when they were all published; refuse with the probe failure instead of the missing-list hint.
- My human partner runs a live dogfood session: `command -v` on a plugin bin/ command resolves in main-thread and subagent Bash; launched before the first `just dogfood`, session-start warns and `/reload-plugins` after the sync loads the copy without a restart (verified headless only).
- release-marketplace.sh rewrites marketplace.json whole in jq's 2-space style on every real bump; edit the version in place instead.
- scripts/self-release.sh common_preflight refuses a dirty tree with a bare "uncommitted changes" naming no path, while toolkit/release-preflight.sh report_dirty names them; make the self-release name the offending paths.
- `just format-docs` runs rumdl over docs/ and plans/ only, so the shipped manual (toolkit/README.md, toolkit/docs/, toolkit/migrations/) is never reflowed and its 400-line count is measured on hand wrapping; widen the recipe's scope.
- memory/MEMORY.md is over its byte budget (105%), so its tail is truncated at load: run /gitlore:index-audit when my human partner asks for it.

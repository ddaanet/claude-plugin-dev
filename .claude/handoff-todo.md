## Open decisions

- The install/update invocation design, interrupted mid-brainstorm. Three
  separable questions: (a) should `install.sh` default its ref to the newest
  `dist-` tag resolved from the remote, removing the version argument
  entirely; (b) should the docs point at
  `../claude-plugin-dev/toolkit/install.sh` on the assumption of a sibling
  checkout, replacing the clone-to-`/tmp` step; (c) should a separate
  `update.sh` own consumer-side migrations — the class the per-release briefs
  describe by hand, e.g. v0.4.0 requiring a `prerelease` recipe before the
  subtree lands. Key finding: `install.sh` fetches from `TOOLKIT_URL`, not
  from the checkout it runs out of, so (b) needs no code change — only (a)
  and (c) do. Running from the source checkout also sidesteps the bootstrap
  problem that a vendored copy always holds the old migration logic.
  Classified bounded for (a)/(b), architectural for (c).
- Which fix shape for the hardcoded `memory` pathspec at `release.sh:60` and
  `:90` (rank 6 of the audit): read the path from `.gitmodules` keyed on the
  submodule name, or drop the pathspec for
  `git diff --quiet --ignore-submodules=all HEAD`. The second is smaller but
  also hides a consumer's genuinely uncommitted code submodule; no consumer
  carries one today. Unreachable by all nine repos as they stand, so there is
  no pressure to rush it.
- Whether to trust the audit's finding that
  `docs/changelog/2026-08-14-dist-ref-stops-squash-leak.md` is wrong to call
  the bootstrap gap "narrowed but not closed". It reports a fixture showing a
  pre-0.5.2 recipe pulls `dist-v0.6.0` cleanly, and that no pre-0.5.2 recipe
  refuses a `dist-` ref. Unverified here. A dated entry is never revised, so
  confirming it means a new dated entry, not an edit.
- The ddaanet memory tier divergence. This repo's root `memory/MEMORY.md`
  block is older than `memory/ddaanet`'s local HEAD, whose newer content sits
  in unpushed tier commits. Composition mirrors root to tier, so every commit
  here rewrites five index lines back to their 2026-08-01 wording and would
  publish that regression to the shared tier. `/gitlore:merge` is a no-op —
  both stores match their remotes. Either propagate tier to root (reopening
  the index-budget question below) or keep restoring
  `memory/ddaanet/MEMORY.md` by hand after each gate run.
- Which index pointers to retire for the ~24.4KB loader cap (root is ~24.7KB,
  so its tail is silently dropped in every ddaanet repo). The remedy is fixed
  — retire a pointer, never shorten one into an unroutable line — but the
  selection is unmade. Separately, four root pointers name targets absent
  from the store and need dropping or redirecting: `shell-gotchas-on-review`,
  `skill-vs-command`, `verify-session-root`,
  `run-the-gate-not-a-suite-subset`.
- Whether the five consumers already at `dist-v0.6.0` need a docs-only
  re-pull for the README fix, or whether it rides their next routine update.

## Remaining

- Cut a 0.6.1 patch, carrying the drift-proofed install docs and the
  refused-commit rollback. A new consumer clones the toolkit at a source tag
  to obtain `install.sh`, and v0.6.0's README still names the nonexistent
  `dist-v0.5.5`, so a fresh install today fails at the clone.
- Work the audit's remaining ranks, in order: nit 1 (`check_marketplace_writable`
  discards `mktemp`'s stderr behind `2>/dev/null`, then asserts a sandbox
  cause the probe never established); the push-race brief's item 3 (a comment
  recording the ancestor invariant, which is what stops someone rebuilding
  the `refresh_release_commit` amend the brief argues against) and item 1 (a
  failure hint on `push_branch`, whose wording should be designed with the
  refused-commit hint or the two will drift); nit 3 (a comment at
  `release.sh:78` recording that the `[ ... ] &&` line is errexit-exempt only
  because it sits mid-function); the push-race item 2 test.
- Fix `toolkit/README.md:129`, which says `update-plugin-dev` "warns if you
  pass a branch ref". It refuses one — stale since `6266b6a`.
- Propagate `dist-v0.6.0` into onekeys, shell-gotchas and handoff once each
  clears its blocking tracked work. Ask before any write in those repos.
  Expect two recoverable snags per repo: gitmoji's commit-msg hook rejects
  the subtree squash message, leaving a correct staged merge to finish by
  hand with a conventional message (never `--no-verify`, never `git checkout`
  first); and a modify/delete conflict on a vendored file the dist ref no
  longer ships, resolved by deleting it after checking the local edit exists
  upstream.
- Decide where `brief-audit.md` and the two open briefs
  (`brief-release-memory-push-race.md`,
  `brief-release-sh-two-nits-from-gitlore-audit.md`) belong once their items
  land — the closed set went to `plans/` under each brief's own date.

## Open decisions

- The install/update invocation design, interrupted mid-brainstorm. Three
  separable questions: (a) should `install.sh` default its ref to the newest
  `dist-` tag resolved from the remote, removing the version argument
  entirely; (b) should the docs point at `../claude-plugin-dev/toolkit/install.sh`
  on the assumption of a sibling checkout, replacing the clone-to-`/tmp` step;
  (c) should a separate `update.sh` own consumer-side migrations — the class
  the per-release briefs currently describe by hand, e.g. v0.4.0 requiring a
  `prerelease` recipe in the consumer justfile before the subtree lands.
  Key finding already established: `install.sh` fetches content from
  `TOOLKIT_URL`, not from the checkout it runs out of, so (b) needs no code
  change at all — only (a) and (c) do. Running from the source checkout also
  sidesteps the bootstrap problem that a vendored copy always holds the *old*
  migration logic. Classified bounded for (a)/(b), architectural for (c).
- The ddaanet memory tier divergence. This repo's root `memory/MEMORY.md`
  block is older than `memory/ddaanet`'s local HEAD, whose newer content sits
  in ~140 unpushed tier commits. Composition mirrors root to tier, so every
  commit here rewrites five index lines back to their 2026-08-01 wording and
  would publish that regression to the shared tier. `/gitlore:merge` is a
  no-op — both stores already match their remotes. Either propagate tier to
  root (which reopens the index-budget question below) or keep restoring
  `memory/ddaanet/MEMORY.md` by hand after each gate run.
- Which index pointers to retire for the ~24.4KB loader cap (root is ~24.6KB,
  so its tail is silently dropped in every ddaanet repo). The remedy is fixed —
  retire a pointer, never shorten one into an unroutable line — but the
  selection is unmade. Separately, four root pointers name targets absent from
  the store and need dropping or redirecting: `shell-gotchas-on-review`,
  `skill-vs-command`, `verify-session-root`, `run-the-gate-not-a-suite-subset`.
- Whether to delete this repo's three closed briefs:
  `brief-subtree-squash-leaks-memory-submodule.md`,
  `brief-subtree-squash-leaks-toolkit-environment.md`, and
  `brief-update-plugin-dev-bootstrap-gap.md`. The last is now confirmed closed:
  a consumer vendored at 0.3.0 pulled `dist-v0.6.0` with its own old recipe,
  because the dist lineage carries no gitlink for the fetch to recurse into.
  All three are untracked, so deletion is unrecoverable.

## Remaining

- Cut a 0.6.1 patch so the drift-proofed install docs reach a released tag. A
  new consumer clones the toolkit at a source tag to obtain `install.sh`, and
  v0.6.0's README still names the nonexistent `dist-v0.5.5`, so a fresh install
  today fails at the clone.
- Propagate `dist-v0.6.0` into onekeys, shell-gotchas and handoff once each
  clears its blocking tracked work. Ask before any write in those repos.
  Expect two recoverable snags per repo: gitmoji's commit-msg hook rejects the
  subtree squash message, leaving a correct staged merge to finish by hand with
  a conventional message (never `--no-verify`, never `git checkout` first); and
  a modify/delete conflict on a vendored file the dist ref no longer ships,
  resolved by deleting it after checking the local edit exists upstream.
- Decide whether the five updated consumers need a docs-only re-pull for the
  README fix, or whether it rides their next routine update.

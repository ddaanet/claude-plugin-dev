## Open decisions

- `memory/MEMORY.md` is past Claude Code's ~24.4KB loader cap, so its tail
  entries are silently dropped from every session in every ddaanet-tier repo.
  The remedy is fixed — retire a pointer, never shorten one into an
  unroutable line — but which entries to retire is unmade. Predates this work.
- Whether the general gotcha behind this session's fix — `git subtree` copies
  a ref's whole root tree, so vendoring ships the source repo's working
  environment — earns a ddaanet memory. It is captured project-locally in
  `docs/design.md` and the 2026-08-14 changelog entry; promoting it is blocked
  on the index-budget decision above.
- Whether to delete `brief-subtree-squash-leaks-memory-submodule.md` and
  `brief-subtree-squash-leaks-toolkit-environment.md`, both closed by this
  change. They are untracked, so deletion is not recoverable.

## Remaining

- Cut the toolkit release — the first to exercise `just release`'s dist-tag
  path outside fixtures.
- Propagate the dist tag into the eight sibling consumers (gitmoji,
  candidature, onekeys, gitlore, shell-gotchas, cwd-safety, handoff,
  unsandbox-git-status), refreshing each one's `brief-plugin-dev-*.md` to the
  dist-ref vocabulary. Their vendored VERSIONs need re-deriving: the readings
  taken earlier this session proved stale.
- Verify whether a consumer vendored below v0.5.2 can pull a `dist-` tag using
  its own old `update-plugin-dev`. The dist lineage carries no gitlink, so the
  fetch collision should be unreachable even without the recursion scoping
  that old copy lacks. If it holds, `brief-update-plugin-dev-bootstrap-gap.md`
  is closed by this change rather than still open.

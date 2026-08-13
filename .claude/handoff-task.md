## Current task

The install.sh subtree-add recursion fix and the deterministic test seeds
are in; what remains is cutting the next toolkit release and propagating
it to the sibling consumers.

## Open decisions

- Release bump size: the changes are fixes only, suggesting patch
  (v0.5.4) — confirm before `just release` (which must run unsandboxed;
  it dies at the marketplace bump otherwise).
- The three `brief-*.md` files in the repo root remain open asks: how to
  stop the subtree squash from shipping `plugin-dev/memory` and the
  toolkit's working environment into consumers (subtree cannot exclude
  paths, so the design call is between changing what this repo tracks
  and changing how release tags are cut), and where the documented
  bootstrap workaround for consumers still below v0.5.2 lives (README,
  release notes, or the per-consumer briefs).
- Which `memory/MEMORY.md` entries to retire — the index sits at ~98% of
  Claude Code's 24.4KB loader budget, so tail entries risk being
  silently dropped (carried from the previous handoff).

## Open decisions

- Whether to roll back the staged marketplace bump when its commit is refused,
  mirroring what `bump_commit_tag` already does for the manifest. The 2026-09-03
  change left it as a printed `git -C <dir> checkout HEAD --
  .claude-plugin/marketplace.json` because the brief was scoped to messages, but
  the leftover blocks `resume-release`'s own pre-flight — which is the same
  argument that made the manifest rollback automatic.
- Whether to add the two static-analysis checks sketched but not authorized: a
  divergence check between `README.md` and `toolkit/README.md` over the install
  and update instructions (CLAUDE.md states the rule that a change lands in both;
  nothing enforces it), and a correspondence check between CLAUDE.md's Layout
  list and the actual contents of `toolkit/`. The install-invocation change
  strengthens the first case — the shared block is now duplicated in four places,
  counting `install.sh`'s header and the design node. My human partner said
  static analysis is good and they would have more of it, which is an appetite
  rather than a go-ahead on these two.
- Whether to drop a note in `plugin-craft` carrying the one lesson from this
  repo that is general enough for a distributed skill: `git subtree` copies a
  ref's whole root tree, so shipping a subdirectory needs a `subtree split` dist
  ref. Everything else about the toolkit is private-toolchain content and was
  ruled out of that plugin on audience grounds. Offered, unanswered; that repo
  is read-only from here.

## Remaining

- Implement `plans/2026-09-02-brief-readme-absorbs-update-lore.md`, then reduce
  `memory/ddaanet/claude-plugin-dev.md` to whatever the README does not own.
- Root `memory/MEMORY.md` is over Claude Code's loader cap — the gitlore hook
  now reports 104% of its 25600-byte budget — so entries past the cutoff never
  reach a session. Parked deliberately; raise it only if asked.

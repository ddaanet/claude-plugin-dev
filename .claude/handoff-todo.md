## Open decisions

- The install invocation design. A first install today is a three-step dance a
  human copies from `README.md`: resolve the newest source tag with `git
  ls-remote`, `git clone --depth 1` it to a temp dir, `cd` to the plugin, then
  `bash /tmp/cpd/toolkit/install.sh`. The clone exists only to obtain one file —
  `install.sh` vendors from `TOOLKIT_URL` itself and never reads the checkout
  again. Three directions weighed: (1) fetch just the script from a pinned raw
  GitHub URL, which kills the clone and keeps the dist-tag discipline but adds a
  second distribution channel that must stay in step with the dist tag; (2)
  leave it as-is, on the grounds that a once-per-plugin ceremony may not be worth
  engineering away; (3) make the toolkit a marketplace plugin exposing
  `/plugin-dev:install`, which means overturning the CLAUDE.md non-goal against
  adding a `.claude-plugin/plugin.json` here. Recommendation was (1). The
  original brainstorm may have carried a fourth option that did not survive into
  any frame.
- Whether to add the two static-analysis checks sketched but not authorized: a
  divergence check between `README.md` and `toolkit/README.md` over the install
  and update instructions (CLAUDE.md states the rule that a change lands in both;
  nothing enforces it), and a correspondence check between CLAUDE.md's Layout
  list and the actual contents of `toolkit/`. My human partner said static
  analysis is good and they would have more of it, which is an appetite rather
  than a go-ahead on these two.
- Whether to drop a note in `plugin-craft` carrying the one lesson from this
  repo that is general enough for a distributed skill: `git subtree` copies a
  ref's whole root tree, so shipping a subdirectory needs a `subtree split` dist
  ref. Everything else about the toolkit is private-toolchain content and was
  ruled out of that plugin on audience grounds. Offered, unanswered; that repo
  is read-only from here.

## Remaining

- Implement `plans/2026-09-02-brief-release-diagnostics.md`, then retire
  `memory/ddaanet/claude-plugin-dev-release.md`.
- Implement `plans/2026-09-02-brief-readme-absorbs-update-lore.md`, then reduce
  `memory/ddaanet/claude-plugin-dev.md` to whatever the README does not own.
- Root `memory/MEMORY.md` is over Claude Code's loader cap — the gitlore hook
  reports 104% of its 25600-byte budget — so entries past the cutoff never reach
  a session. Parked deliberately; raise it only if asked.

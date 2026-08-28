## Brief: `update-plugin-dev` can't self-upgrade past the exact bug v0.5.2 fixed

2026-08-13 — target: `claude-plugin-dev` (this repo) · found from `onekeys`

### Decisions

- **The v0.5.2 fix doesn't reach a consumer that needs it**, because of a
  bootstrap gap: the recipe that actually executes `just update-plugin-dev
  vX.Y.Z` is whatever's *already vendored* in the consumer (`plugin-dev/`
  on disk), not the target tag being requested. A consumer still on <0.5.2
  runs the OLD, unfixed `update-plugin-dev` to fetch the pull — and that old
  recipe hits the exact `fetch.recurseSubmodules=on-demand` collision
  0.5.2 fixed, regardless of which tag it's asked to reach. Requesting
  v0.5.3 directly does not avoid this: the fix has to already be present
  *locally* to pull cleanly, and it isn't, by definition, in a consumer
  that hasn't updated yet.
- This is worse than the original bug report suggests. `2026-08-11-subtree-
  submodule-collision.md` (the fix's own changelog entry) and `onekeys`'s
  own `brief-plugin-dev-0.5.3.md` both say, in effect, "go straight to
  v0.5.3" as if targeting a fixed tag sidesteps the problem. It doesn't.
  Any consumer below v0.5.2 that also mounts a `memory` submodule at
  top-level (the standard ddaanet-plugin shape) is stuck the same way no
  matter what tag it requests.

### Constraints

- A fix inside `update-plugin-dev` itself can't close this gap by
  construction — the very code with the bug is what has to run first. This
  needs either (a) a documented manual workaround consumers apply once to
  bootstrap past it, or (b) some other mechanism outside the vendored
  recipe (e.g. an `install.sh`-style one-shot fetch that doesn't go through
  `git subtree pull`'s submodule-recursing fetch at all, or a documented
  `git config` scoping step run by hand before the first post-0.5.1
  update).
- Affects every consumer still below v0.5.2 that also mounts a `memory`
  submodule — i.e. every ddaanet plugin repo that hasn't yet run
  `update-plugin-dev` since 0.5.2 shipped.

### Rejected approaches

- Relying on "just target v0.5.3 directly" as guidance — already tried in
  `onekeys`, still failed with the identical `upload-pack: not our ref`
  error the 0.5.2 changelog describes.

### Additional context

Reproduced in `onekeys` (vendored at v0.4.0, i.e. pre-0492652):
`just update-plugin-dev v0.5.3` failed identically to the bug report's own
repro. Worked around manually, outside the recipe:

```sh
git config fetch.recurseSubmodules no
git subtree pull --prefix=plugin-dev git@github.com:ddaanet/claude-plugin-dev.git v0.5.3 --squash
git config --unset fetch.recurseSubmodules
```

That got `onekeys` to v0.5.3, at which point `update-plugin-dev` itself
carries the fix and works normally for future updates.

Separately, the v0.5.3 pull also carried `plugin-dev/memory` (this
toolkit's own gitlore submodule) into `onekeys` as an unmapped `160000`
gitlink, breaking `git submodule status` repo-wide — matching
`brief-subtree-squash-leaks-memory-submodule.md`, already sitting in this
repo. Worked around locally the same way that brief documents
(`git rm --cached plugin-dev/memory`). Not re-reporting it here, just
noting both hit the same consumer in the same session — whatever ships to
close the squash-leak brief should probably also close this one, since
both are update-plugin-dev's-own-history-bleeding-into-the-consumer bugs.

Once whichever fix (or documented workaround) lands here, the
`brief-plugin-dev-vX.Y.Z.md` template that gets dropped into each of the
six consumer repos (handoff, gitmoji, onekeys, cwd-safety, shell-gotchas,
gitlore) should carry the bootstrap workaround explicitly for any consumer
still below v0.5.2, rather than the current "go straight to vX.Y.Z"
framing that doesn't actually work for them.

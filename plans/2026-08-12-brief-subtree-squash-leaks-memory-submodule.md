## Brief: subtree squash leaks the toolkit's own memory submodule into consumers

2026-08-12

### Decisions

- This toolkit mounts its own gitlore `memory` submodule (since commit
  `5235d96`, present from v0.5.1 onward). When a consumer runs
  `just update-plugin-dev vX.Y.Z` (`release.just`'s `update-plugin-dev`
  recipe, `git subtree pull --prefix=plugin-dev … --squash`), the squash
  carries that submodule's gitlink into the consumer's tree verbatim, as
  `plugin-dev/memory` (mode `160000`).
- The consumer's own `.gitmodules` has no entry for `plugin-dev/memory` —
  only for its own top-level `memory` submodule, if it has one. The result:
  `git submodule status` (and `git submodule update --init --recursive`)
  fails **repo-wide** with `fatal: no submodule mapping found in
  .gitmodules for path 'plugin-dev/memory'`, even though every submodule
  the consumer actually registered is fine. Breaks a fresh clone's
  `--recurse-submodules` and any tooling that walks all submodules.
- This needs a source-side fix: the `update-plugin-dev` recipe (or
  whatever feeds its squash) should keep `plugin-dev/memory` from ever
  landing in a consumer's tree. The toolkit's own memory has no business
  being vendored into a consumer.

### Constraints

- Distinct from the bug commit `0492652` (🐛 scope
  `fetch.recurseSubmodules=no` to `update-plugin-dev`'s subtree pull)
  already fixed. That commit's own comment in `release.just` explains it
  scoped a *fetch-time* collision: a consumer that **also** mounts its own
  top-level `memory` submodule sees `subtree pull`'s raw fetch resolve the
  gitlink against the consumer's `memory` remote instead of this repo's,
  failing with "not our ref". `fetch.recurseSubmodules=no` stops that
  fetch failure, but the squash still embeds the gitlink itself — the two
  are different failure modes at different stages of the same pull.
- Any fix must not disturb this repo's own use of gitlore memory
  in-place — only its propagation into a consumer's subtree squash needs
  to stop.
- A source-side fix is prospective only: consumers already vendored at
  v0.5.1+ carry the bad gitlink in their own history already and won't be
  cleaned up retroactively. Each fixes it locally with
  `git rm --cached plugin-dev/memory` (plus removing the now-empty
  directory) — this was applied downstream in `handoff` as a one-off
  workaround, not a fix here.

### Rejected approaches

- None yet formally weighed in this repo — this is a fresh finding from a
  consumer, not diagnosed against `update-plugin-dev`'s actual
  implementation options.

### Additional context

Found while running `/preflight` in the `handoff` repo (a consumer,
vendored at v0.5.3 via commit `d8684b95` — `Squashed 'plugin-dev/'
changes from d0b3a03..3de1862`, `git-subtree-split: 3de1862`). Reproduction
there:

```
$ git submodule status
fatal: no submodule mapping found in .gitmodules for path 'plugin-dev/memory'
```

Confirmed via `git ls-files -s plugin-dev/memory` → `160000
59ed7703924f4e3f360accc4ffbeafdfe47c7f07 0 plugin-dev/memory`, and via
`git log --oneline -- plugin-dev/memory` showing the entry first appears at
that same squash commit — it did not exist in `handoff` before this pull.
`handoff`'s own `plugin-dev/memory` submodule (the isolated one, `git
submodule status memory`) is unaffected; only the whole-repo, unscoped
`git submodule status` call fails.

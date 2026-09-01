# 2026-09-01 — `update.sh` owns the update flow: default ref resolution and migration notes

Three changes landed together, out of the install/update invocation
brainstorm.

**The ref argument is now optional at both call sites.** With no ref,
`install.sh` and the update flow resolve the newest `dist-` tag from the
remote (`git ls-remote --sort=-v:refname`), announce which tag they
picked, and proceed. The README's install block used to do that
resolution in its own shell snippet and pass the result in; the snippet
now only resolves the newest *source* tag for the bootstrap clone, and
`install.sh` handles the dist side itself. Resolution happens once, at
invocation, and the subtree commit records the exact tag — this is still
tag-pinning, not `main`-tracking. An empty resolution (no dist tags
reachable) is a hard error naming the explicit-ref fallback, never a
fall-through to a bogus pull.

**The `update-plugin-dev` recipe body moved to a new shipped
`update.sh`.** The recipe is now a one-line wrapper, the same shape as
`release` wrapping `release.sh`. Motivations: a recipe body escapes
`shellcheck`/`bash -n` (the precommit gate lints scripts), cannot be
executed directly by a test, and is subject to just's own parsing
quirks. The fixture in `tests/update-plugin-dev-test.sh` now ships the
real `update.sh` into its dist lineage, so the tests exercise the
vendored-copy-executes path — the copy under test is the one about to
ship. The dist-tag shape guard and the resolver are deliberately
duplicated between `install.sh` and `update.sh`: the bootstrap script
must stay runnable on its own from a fresh clone.

**Releases can ship migration notes; updates print them and change
nothing else.** A release needing a consumer-side step (the class the
per-release briefs described by hand — e.g. v0.4.0 requiring a
`prerelease` recipe) ships `migrations/vX.Y.Z.md` in its dist tree.
After the pull, `update.sh` prints every note in the crossed range (old
`VERSION` exclusive, new inclusive, `sort -V` order). A separate
`update.sh` that *applied* migrations was considered and rejected: an
upgrade must not touch files outside the subtree — a consumer's
justfile and settings are theirs. Known structural limit, shared with
the rejected leaked-path pruning: the consumer's existing vendored copy
executes the upgrade, so the release introducing this mechanism cannot
have its own note printed; notes take effect from the next upgrade on.
Most releases need no note, and `migrations/` need not exist;
`dist-tree-test.sh` allows exactly the `migrations/vX.Y.Z.md` shape
without per-file list edits.

Also decided, docs-only: the install instructions keep the
clone-to-`/tmp` bootstrap rather than assuming a sibling
`claude-plugin-dev` checkout — a local checkout is a local
optimisation, and the docs must work for someone who has only the
plugin repo in front of them.

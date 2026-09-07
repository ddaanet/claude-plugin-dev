## Current task

The README-absorbs-update-lore brief is implemented and the ddaanet memory entry reduced to what the shipped manual cannot own, alongside two authorized side changes: `bump_marketplace` now rolls its staged bump back when a consumer's gate refuses the commit, and `tests/doc-sync-test.sh` enforces the two-READMEs rule and CLAUDE.md's Layout list from `precommit`.

What remains is publishing memory to its tier remotes and a release-readiness pass over the toolkit. `toolkit/release.sh` and `toolkit/README.md` both changed, so none of it reaches a consumer until a new `dist-vX.Y.Z` split tag is cut — `just release` in this repo's own justfile, never `release.just`'s recipes.

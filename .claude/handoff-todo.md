## Open decisions

- Whether the toolkit release is `patch` or `minor`. The marketplace rollback changes `release.sh` behaviour on a failure path only, and `toolkit/README.md` gains a post-pull `just --list` step that is guidance rather than a required consumer-side edit — so nothing here breaks a consumer's justfile and no `toolkit/migrations/vX.Y.Z.md` note is owed. Patch is the straightforward reading; minor is defensible if the README's new required step counts as consumer-visible surface.

## Remaining

- Run the release-readiness pass, then cut the toolkit release with `just release [patch|minor]` from this repo's own justfile.
- Root `memory/MEMORY.md` is over Claude Code's loader cap — the gitlore hook reports 103% of its 25600-byte budget — so entries past the cutoff never reach a session. Parked deliberately; raise it only if asked.

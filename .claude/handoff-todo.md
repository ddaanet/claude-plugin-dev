## Remaining

- Execute `plans/2026-07-29-release-resume-plan.md` Tasks 1-8: `release.sh` with `--resume`, the offline test harness, the `release.just` wrappers, docs, then release 0.5.0.
- Run `just update-plugin-dev v0.5.0` in handoff, gitmoji and gitlore. handoff and gitmoji each need `prerelease: precommit` added in the same commit as the pull, or their justfiles fail to compile on arrival; gitlore already defines it.
- Check whether the consumer plugins' own justfiles have multi-line recipe doc comments, which just lists as trailing sentence fragments.

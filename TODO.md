## Open decisions

- 0.17.1 changes what a consumer release publishes: an untracked, non-ignored
  `TASK.md`/`TODO.md` in the plugin root now rides the release commit to `main`.
  Ship a migration note (non-breaking) saying so, and/or have `bump_commit_tag`
  name the handoff files it staged? Default: a non-breaking note in
  `toolkit/migrations/v0.17.1.md`, no new output line.

## Remaining

- Release `dev` as toolkit 0.17.1 through `edify:release`.
- Then update the consumers to `dist-v0.17.1`; their update merges to 0.17.0
  are still unpushed, and stay unpushed on my human partner's instruction.

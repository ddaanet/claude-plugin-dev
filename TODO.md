## Remaining

- `move_main` in `toolkit/release-publish.sh` fetches with `-q`, so a
  non-fast-forward prints nothing from git while its hint says "clear what git
  reported above".
- `scripts/self-release.sh` releasing from `dev` while another worktree holds
  `main` makes the commit and both tags before `move_main` is refused, and
  `docs/references/self-release.md` documents the resume hint as intended: the
  counterpart of the consumer's `branch_preflight` probe.

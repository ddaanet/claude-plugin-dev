## Remaining

- Amending a release commit after its tags are cut, which
  `docs/references/recovery.md` already advises against, has two rough edges
  left in `scripts/self-release.sh`. `ensure_dist_tag` keeps an existing local
  dist tag without comparing it to the tag, so a hand retag publishes
  `dist-vX.Y.Z` from the old `toolkit/` tree; comparing `$dist_tag^{tree}` with
  `$tag:toolkit` would close it, but adds a refusal, so propose it first. From
  `dev` after a failed push, the run stops at
  `local main is not an ancestor of HEAD` with no way out named; `main` has to
  move back by hand first.
- Two states where a consumer release loops on `just resume-release`, declined
  as rare in the review of the release-from-dev slice and awaiting my human
  partner's call on adding refusals: `main` checked out in another worktree
  (`move_main`'s fetch is refused after the commit and tag exist, and the undo's
  `git branch -f` fails); and a commit on local `main` after a failed push
  (`move_main` dies non-fast-forward and its hint names the same resume). A
  preflight refusal in `branch_preflight` and `resume_preflight` would close
  them, but adds surface.

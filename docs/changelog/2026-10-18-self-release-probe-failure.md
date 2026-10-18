# 2026-10-18 — Self-release: an unreadable origin refuses as itself

`require_prior_release_published` tested each origin tag with
`[ -n "$(ls_remote_sha …)" ] || missing+=(…)`. `ls_remote_sha` dies when
`git ls-remote` fails, but inside `$(…)` that only ends the substitution's
subshell: git's message reached stderr, the empty result read as "tag absent on
origin", and the hint listed `vX`, `dist-vX` and the GitHub release as
unpublished. A sandbox blocking `github.com:22` produced exactly that for a
release that was fully published. The comment above the code called this the
safe direction, since the run was refused either way. It is not: the refusal
sent the reader to `just resume-release` to repair tags that were never missing,
and hid that the real fault was the unreachable origin.

## Fixed

- **The prior-release guard.** Each probe is captured into a variable with
  `|| exit 1`, so a probe failure ends the run with `ls_remote_sha`'s own
  message (`git ls-remote origin refs/tags/vX failed`) and no missing-list hint.
  `gh` is not reached. The misleading comment is rewritten.
- **`resume_preflight`'s no-tag hint.** The same inline test chose between
  "origin already has the tag" and "no release was started". An unreadable
  origin fell into the second wording, which is a claim about the release. It
  now refuses as the probe failure too.
- **The test.** The existing dead-origin scenario asserted
  `release vX is unfinished`, which was the bug's own output; it now asserts the
  probe failure and the absence of the missing-list hint, the unfinished verdict
  and any `gh` call. A second scenario covers the resume path with no local tag.

`ensure_dist_tag`, `push_branch` and `push_tag` already captured their probes
into variables and are unchanged.

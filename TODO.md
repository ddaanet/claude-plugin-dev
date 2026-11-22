resume `/edify:release` at step 5 (medium loop), toolkit 0.17.1, bump `patch`,
on `dev`.

## Decided

- 0.17.1 ships no migration note. The GitHub release notes carry one line: an
  untracked, non-ignored `TASK.md`/`TODO.md` in the plugin root now rides the
  release commit to `main`, and `sentinel-guard` refuses a tree with unmerged
  paths.
- History of the fix commits since `b3ba958` stays as is (three of them have
  `toolkit/release-publish.sh` over the cap; `e920457` splits it).
- A release whose push is refused because origin's main moved is not undone: the
  hint is always `git merge origin/main` then `just resume-release`, from main
  and from dev. The tag stays on release commit R; resume pushes HEAD as main
  when HEAD contains R and origin's main O (refetch O before the hint); when O
  is inside R it pushes R as before; in the dev flow it fast-forwards local main
  to HEAD without checkout. Later commits in HEAD land on main by design. Tag,
  dist, GitHub release, marketplace stay on R. `print_undo` and what only it
  used are deleted. Same rule in `scripts/self-release.sh` for parity.

## Remaining

- Step 6 of `/edify:release`: push dev if `git ls-remote --heads origin dev`
  prints a line, `/ddaa:preflight`, `just release patch`, push dev again.
- Then update the consumers to `dist-v0.17.1`; their update merges to 0.17.0 are
  still unpushed, and stay unpushed on my human partner's instruction.
- Found in the 0.17.1 release review, predates it: when the pre-commit hook runs
  for `git commit -- <paths>`, git hands it a temporary index, so the blob
  `whitespace`/`format-docs` fix and `git add` never reaches the real index; the
  committed path is left `MM` with the unfixed blob staged, and a following
  commit on a cached gate puts the defect back. Decide whether to refresh the
  real index for fixed paths or document it.
- Design a recovery for `published_tags_check`'s refusal (another clone already
  published this version's tag at another commit): the run leaves a local
  release commit and tag that every later `just release` and
  `just resume-release` refuse, and the refusal names no next step.

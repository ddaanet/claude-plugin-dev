# Plan: release the toolkit from dev

2026-11-05. The self-release slice of the design in `TODO.md`:
`scripts/self-release.sh` only. Tasks are contracts, not code. Out of this
slice: the consumer flow in `toolkit/`, a second implementation that follows it,
and `ddaa:preflight`.

## Probed

- **gitlore's pre-push hook ignores the refspec.** By reading, not a live push:
  `pre-push` takes no stdin and no arguments, and `gitlore_push_stores` pushes
  each store's `live`. Its one use of `HEAD` runs only when memory is not
  checked out, so pushing a commit other than `HEAD` changes nothing here. The
  first real release from dev is the live check.
- **`git fetch . HEAD:main`** updates `main` from dev, exits 1 on a
  non-fast-forward, and exits 128 while `main` is checked out ("refusing to
  fetch into branch"), all measured in a scratch repo. The fast-forward
  therefore runs only when `main` lacks the commit, which never holds with
  `main` checked out unless the tag is off its history, and that case should
  die.

## Contract: `scripts/self-release.sh`

`release_commit` is `HEAD` after `bump_commit_tag`, and `$tag^{commit}` on
resume.

- **Branch.** Allowed: the default branch `main_branch` and the literal `dev`.
  Anything else, and a detached `HEAD`, refuses as today, naming both.
- **Fetch first.** `common_preflight` runs `git fetch origin`; a failed fetch
  dies before any check reads `origin/main`.
- **Ancestry.** Refuses unless local `main_branch` and `origin/main_branch` are
  both ancestors of `HEAD`, naming which one is not. Nothing has been written at
  that point.
- **Moving main.** After the tags, `main_branch` is fast-forwarded to
  `release_commit` with `git fetch . "$release_commit:refs/heads/$main_branch"`,
  skipped when it already contains that commit. A refusal (another worktree
  holds `main`) dies with the same `just resume-release` hint as a failed push.
- **Push.** `git push origin "$release_commit:refs/heads/$main_branch"`. Already
  pushed when `release_commit` is an ancestor of origin's `main_branch`, so a
  resume after later dev commits publishes the tag's commit and none of them.
- **Invariants.** The checkout does not change branch, `dev` is never pushed by
  this script, and every other step keeps its probe. A release from `main`
  behaves as now, apart from the new early refusal when `origin/main` has
  commits `HEAD` lacks.

## Steps

1. **Red: new suite `tests/self-release-branch-test.sh`**, with its own fixture
   holding a `dev` branch and a bare origin whose `main` can move on its own,
   and its line in `tests/CLAUDE.md`. `tests/self-release-refusal-test.sh` is at
   16221 bytes and cannot take these under the 20000 cap. Scenarios:
   - a release from dev moves local and origin `main`, leaves `dev` checked out
     and leaves `dev` off origin;
   - a branch `side` refuses;
   - a local `main` with a commit `HEAD` lacks refuses, with no tag cut;
   - an `origin/main` with a commit `HEAD` lacks refuses, with no tag cut;
   - a resume after a later dev commit lands the tag's commit on `main`, not
     `HEAD`;
   - a resume of a complete release with a later dev commit says complete and
     pushes nothing.
2. **Red review** by a different agent: each scenario fails against the
   unchanged script on a failed assertion.
3. **Green** in `scripts/self-release.sh`, updating the two existing suites only
   where they pin the old wording or the old resume push.
4. **Docs**, present tense: `docs/references/self-release.md`, the "Default
   branch detection" section of `docs/references/release-flow.md`, `CLAUDE.md`
   "Releasing the toolkit", and the matching hub line if `docs/design.md`
   carries one. The narration goes in the commit body.
5. **`just precommit`, one commit, `/code-review medium`**, per the standing
   loop.
6. **`TODO.md`**: drop what this slice settles; the consumer flow and
   `ddaa:preflight` stay.

## Sequencing

`ddaa:preflight` fails its branch rule on dev, so a preflight run still needs
`main` checked out until that skill changes in `/Users/david/code/skills`. The
recipe itself works from dev once this lands. Writing there needs its own
go-ahead.

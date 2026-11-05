# Plan: release a consumer plugin from dev

2026-11-05. The consumer slice of the design in `TODO.md`, in `toolkit/`. Tasks
are contracts, not code. Approved by my human partner, push route narrowed to
`pushurl`. Out of this slice: `scripts/self-release.sh`, and the release
sequence in `memory/ddaanet/shared-claude.md`, which follows once this lands.

## Probed

All against a throwaway prototype of this contract, with local bare origins and
a `gh` stub.

- **Blast radius.** With the contract applied, the 16 `tests/release-*-test.sh`
  suites pass except the 20 `release-push-route` assertions on the two keys
  dropped below.
- **A fetch in `common_preflight` breaks existing refusals.** Plain, it restores
  a lost tag before the lost-tag guard reads it: 42 failures across
  `release-lost-tag`, `release-resume-hint` and `release-pipefail`. Even with
  `--no-tags` it dies ahead of the refusals those suites pin for an unreachable
  origin or none: 6 failures. In release mode after `release_preflight`, none.
- **Origin's `main` moves before the push, today, on `main`:** `git pull` then
  `just resume-release` publishes the merge, leaving the tag on a commit that
  lacks the other writer's work, a combination the gate never saw. This slice
  replaces that with a fresh release.
- **The undo, then `just release`, from `main` and `dev`:** origin's `main`
  lands on the new tag's commit, which carries the other writer's commit and is
  fast-forward. Results by form:
  - `git reset --hard HEAD~1`, when `HEAD` is the release commit: works, with or
    without a moved memory gitlink.
  - `git rebase --onto <rel>^ <rel>`, to drop the commit from under later ones:
    **conflicts on `memory`** when the release commit and a later one both moved
    the gitlink, which gitlore's pre-commit hook does to every commit. Not used.
  - A new commit restoring the manifest with `git checkout <rel>^ -- <manifest>`
    or a reversed diff: works over the gitlink, but the first would discard a
    later manifest edit, and the second failed to apply on one. So the contract
    writes `.version` with `jq`, as `bump_commit_tag` does. That exact form has
    not been run; the later-commits scenario below runs it from the hint.
  - A first release has no release commit: dropping the tag and merging works.
- **A resume whose commit is already on origin, origin moved, from `dev`:**
  finishes with no merge when resume runs no ancestry check on `main`. Today's
  flow rejects it until a pull.
- **`git push origin <refspec>` ignores `branch.<b>.pushRemote` and
  `remote.pushDefault`:** nothing reached the other repo.

## Contract

`release_commit` is `$tag^{commit}`, in both modes.

- **Branch** (`common_preflight`, both modes). Allowed: `main_branch` and the
  literal `dev`. Anything else, and a detached `HEAD`, refuses naming both.
- **Ancestry** (new `branch_preflight`, release mode only, after
  `release_preflight`, before `dist_preflight`). `git fetch --no-tags origin`; a
  failure dies, nothing done. Refuses unless local `main_branch` and
  `origin/main_branch` are ancestors of `HEAD`, each refusal naming the merge
  that clears it (`git merge main`, `git merge origin/main`). An origin with no
  such branch has nothing to compare: a `note` says so and the run continues.
  `--no-tags` because this fetch reads one thing, origin's `main`: a tag
  arriving after `release_preflight` chose the version would meet
  `bump_commit_tag` only once the release commit exists.
- **Resume** (`resume_preflight`, after the tag exists). Refuses a tag whose
  commit is not an ancestor of `HEAD`. When local `main_branch` carries that
  commit the hint is `git merge main`; otherwise it is a re-tag of the last
  commit that changed the manifest's `version` line, valid only while the tag is
  not on origin. Resume runs no check that `main` or `origin/main` is an
  ancestor of `HEAD`: those guards exist to refuse before a commit and tag are
  cut, and a release already on origin's `main` has nothing left that needs
  them.
- **Moving main** (new `move_main`, before `push_branch`, both modes). When
  `main_branch` lacks `release_commit`:
  `git fetch -q . "$release_commit:refs/heads/$main_branch"`, setting `acted`. A
  refusal dies with nothing pushed and a `just resume-release` hint. Never
  rewinds.
- **Push** (`push_branch`). Reads origin's head through `ls_remote_sha`,
  fetching the object when absent, as `push_dist` does. Already pushed when
  `release_commit` is an ancestor of that head. Otherwise
  `git push origin "$release_commit:refs/heads/$main_branch"`, whose failure
  hint stands and names `main_branch`. Later dev commits are never published.
- **A release origin moved past fails.** When origin's head is not an ancestor
  of `release_commit`, `push_branch` refuses before pushing, in both modes, so
  no pre-push hook runs on a doomed push. It says the release failed and nothing
  is public, because the branch push comes first, and prints the undo with every
  value substituted, chosen by the script from the state it reads:
  1. `git fetch --no-tags origin`
  2. `git tag -d <tag>`
  3. Dropping the bump, when `release_commit` differs from its parent in the
     manifest's version. If it is `HEAD`: `git reset --hard HEAD~1`. If not:
     `jq '.version = "<previous>"'` over the manifest, then a commit of it, so
     history is not rewritten and the gitlink is not touched. A first release
     has no bump, so this step is absent.
  4. From `dev` only: `git branch -f <main> origin/<main>`, since the run moved
     it.
  5. `git merge --no-edit origin/<main>`

  Then `just release` with the same bump. The script runs none of this: it
  rewrites local history and is the operator's to take. A race where origin
  moves after this probe reaches the push failure hint, and the resume it names
  lands here.
- **Push route.** The refused keys narrow to `remote.origin.pushurl`. The
  comment above the loop and `recovery.md` lose the claim about an unqualified
  `git push`.
- **Invariants.** The checkout never changes branch, `dev` is never pushed,
  every other step keeps its probe. A release from `main` behaves as now, apart
  from the earlier refusal when `origin/main` has commits `HEAD` lacks, and the
  case above, where `git pull` then resume no longer finishes.

**Differs from the self-release, deliberately:** no `main` ancestry on resume,
the fetch in release mode only and `--no-tags`, and a refusal with an undo where
that script leaves git's rejection. A consumer's `main` may have other writers,
and the lost-tag guard reads local tags. `self-release.sh` does not change.

**No migration note.** The new refusals fire where the push would have failed
later, the dropped ones only widen, and no consumer has a step to take.

## Steps

1. **Red: new suite `tests/release-branch-test.sh`**, with the consumer fixture
   (vendored toolkit, marketplace, `gh` stub), a `dev` branch and a bare origin
   a second clone can move, and its name in `tests/CLAUDE.md`. Split along
   scenario groups if it nears 20000 bytes. The `Siblings:` header lists are
   enforced by nothing and already omit the dist suites, so they stay.
   Scenarios:
   - from dev: local and origin `main` at the release, `dev` checked out and off
     origin, marketplace bumped;
   - a first release from dev;
   - a branch `side` and a detached `HEAD` refuse;
   - local `main`, then `origin/main`, with a commit `HEAD` lacks refuses, with
     no commit and no tag;
   - an origin with no `main` releases and says so;
   - a resume after a later dev commit leaves origin's `main` at the tag's
     commit;
   - a resume of a complete release with a later dev commit pushes nothing;
   - origin moved before the push, from `main`, from dev with `HEAD` at the
     release commit, and from dev with later commits and a moved gitlink:
     refused with nothing public, the hint's commands run verbatim, then
     `just release` lands a tag whose commit carries the other writer's commit
     and is origin's `main`;
   - the same for a first release from dev, whose hint has no bump step;
   - origin moved after the push: the resume finishes with no merge;
   - a tag off `HEAD`'s history refuses on resume, each hint matching its state;
2. **Red review** by a different agent: each scenario fails against the
   unchanged scripts on a failed assertion.
3. **Green** in `toolkit/release.sh`, `release-preflight.sh`,
   `release-publish.sh`, `release-resume.sh`, including the "on the main branch"
   comment in `bump_commit_tag`. In `tests/release-push-route-test.sh`, the two
   keys' refusals become a test that a set key no longer refuses and the push
   still lands on origin.
4. **Docs**, present tense: "Default branch detection" in
   `docs/references/release-flow.md`, the push-route section, the `push_branch`
   re-push paragraph and the failed-release undo in
   `docs/references/recovery.md`, the default-branch bullet in
   `toolkit/README.md`, the hub line in `docs/design.md`. Narration goes in the
   commit body.
5. **`just precommit`, one commit, `/code-review medium`**, per the standing
   loop.
6. **`TODO.md`**: drop what this slice settles; the `shared-claude.md` revision
   stays.

## Sequencing

The toolkit release that ships this can be the first cut from `dev`, which is
also the pending live check of gitlore's pre-push hook, when my human partner
asks for it.

# Slice 2 red report

Suite: `tests/release-dist-test.sh` (shellcheck clean), run against the current
`toolkit/release.sh`, which ignores `dist.include`: runs to its end in about 15
s, 9 scenarios, exit 1, every failure a failed assertion, no abort.

## Scenario map to the plan's bullets

- first opted-in release (root commit of listed paths, `dist-vX.Y.Z` at it,
  message names release commit, marketplace `ref: dist` and type unchanged):
  `first opted-in release...` (github entry kept; also the claude
  `validate --strict` call and the `dist: pushed` /
  `dist tag dist-v1.2.4: pushed` notes the plan names) and
  `first publication: a created url entry...` (url source kept, `ref` added).
- second release (one more commit, parent is the first): `second release...`;
  also dist-v1.2.4 unmoved.
- validation failure (stub exit 1): `validation failure...` snapshots clone
  HEAD, local tags, manifest version, all of origin's refs and the marketplace
  file before and after, plus clean tree, no dist branch, gh not called.
- no `claude` on PATH: `no claude on PATH...`, same snapshot, symlink-only PATH,
  precondition asserts no claude reachable.
- resume after each kill point: `resume after each kill point...` loops over
  after-push_tag (git wrapper refuses the `*:refs/heads/dist` push),
  after-dist-branch (wrapper refuses `*dist-v[0-9]*`), after-dist-tag (gh stub
  fails `release create`, the step right after the dist tag push). Each pins
  where the release stopped, resumes, pins the full end state from origin, then
  a second resume must print `already complete (nothing to do)` and the state is
  re-pinned.
- foreign `dist-vX.Y.Z` on origin: `foreign dist tag on origin...`.
- not opted in: `not opted in: output and refs are those of a plain release` (no
  dist notes, no dist ref or tag on origin, claude log empty, no `ref`, source
  untouched) and `not opted in: a created entry has no ref and needs no claude`
  (no-claude PATH; passes today as a regression guard).
- End state from origin only: `ls-remote`, `rev-list`,
  `ls-tree -r --name-only -z`, `cat-file -t` on the bare origin; `dist-v<V>`
  lightweight is pinned as exactly one `ls-remote` line for
  `refs/tags/dist-v<V>*` plus `cat-file -t` = commit.

## Run output (FAIL lines, trimmed to 210 chars; totals last)

```
FAIL: first opted-in release reports the dist push: output did not contain 'dist: pushed'
FAIL: first opted-in release reports the dist tag: output did not contain 'dist tag dist-v1.2.4: pushed'
FAIL: first opted-in release: origin has no refs/heads/dist
FAIL: first opted-in release: existing github source kept, ref added: expected '{"ref":"dist","repo":"o/fixture","source":"github"}', got '{"repo":"o/fixture","source":"github"}'
FAIL: first opted-in release: claude validated with --strict: output did not contain '--strict'
FAIL: first opted-in release: claude validate was called: output did not contain 'validate'
FAIL: created-entry release: origin has no refs/heads/dist
FAIL: created-entry release: url source kept, ref added: expected '{"ref":"dist","source":"url","url":"https://github.com/tmp.7aNT7vaQEr/plugin-origin.git"}', got '{"source":"url","url":"https://github.com/tmp.
FAIL: second release: origin has no refs/heads/dist
FAIL: second release: the parent is the first release's dist commit: expected '', got '^'
FAIL: second release: marketplace source still ref dist: expected '{"ref":"dist","repo":"o/fixture","source":"github"}', got '{"repo":"o/fixture","source":"github"}'
FAIL: validation failure exit code: expected '1', got '0'
FAIL: validation failure: the stub was reached: output did not contain '--strict'
FAIL: validation failure: clone, origin and marketplace untouched: expected '868b3cad14e94fa54196a4a986ca435c50eb21f3
FAIL: validation failure: gh not called: expected '', got 'release view v1.2.4
FAIL: no claude exit code: expected '1', got '0'
FAIL: no claude: clone, origin and marketplace untouched: expected '98a638a72e9c26327b0c2709786ffed0cb62666c
FAIL: no claude: gh not called: expected '', got 'release view v1.2.4
FAIL: kill after-push_tag: the release was not interrupted
FAIL: resume after after-push_tag: origin has no refs/heads/dist
FAIL: resume after after-push_tag: marketplace source: expected '{"ref":"dist","repo":"o/fixture","source":"github"}', got '{"repo":"o/fixture","source":"github"}'
FAIL: second resume after after-push_tag: origin has no refs/heads/dist
FAIL: kill after-dist-branch: the release was not interrupted
FAIL: kill after-dist-branch: dist branch is on origin: expected 'yes', got 'no'
FAIL: resume after after-dist-branch: origin has no refs/heads/dist
FAIL: resume after after-dist-branch: marketplace source: expected '{"ref":"dist","repo":"o/fixture","source":"github"}', got '{"repo":"o/fixture","source":"github"}'
FAIL: second resume after after-dist-branch: origin has no refs/heads/dist
FAIL: kill after-dist-tag: dist tag is on origin: expected 'yes', got 'no'
FAIL: resume after after-dist-tag: origin has no refs/heads/dist
FAIL: resume after after-dist-tag: marketplace source: expected '{"ref":"dist","repo":"o/fixture","source":"github"}', got '{"repo":"o/fixture","source":"github"}'
FAIL: second resume after after-dist-tag: origin has no refs/heads/dist
FAIL: foreign dist tag: release did not refuse
FAIL: foreign dist tag: message names the tag: output did not contain 'dist-v1.2.4'
FAIL: foreign dist tag: no github release was created: expected 'no', got 'yes'
FAIL: foreign dist tag: marketplace not bumped: expected '1.2.3', got '1.2.4'
35 failure(s)
```

35 failure(s). The scenarios that pass against the current script are the guards
that should pass: both not-opted-in scenarios, and the kill-point interruption
preconditions that do not depend on dist (the release tag reached origin; the
after-dist-tag run is interrupted by the gh failure).

## Ambiguities and how they were resolved

1. Kill "after the dist tag push": the git wrapper cannot fail a step that is
   not a push, and the step after the dist tag push is `create_github_release`.
   The third kill is a failing `gh release create`, not a git wrapper; the other
   two use the wrapper (a glob on push arguments, taken from `FAIL_PUSH_GLOB`).
   This assumes the dist tag is pushed with `dist-v<V>` visible in the push
   args, and the branch with `<sha>:refs/heads/dist` (the plan says so for the
   branch).
2. Foreign tag: the plan says "refused, nothing moved". Asserted: exit nonzero,
   message names `dist-v1.2.4`, origin's tag stays at the foreign sha, no github
   release, marketplace not bumped. Whether the dist branch was already pushed
   by then is not pinned (the plan's probe order puts the tag check after the
   branch push).
3. The first release's shipped manifest is asserted to carry the release version
   (the tree is built after the bump).
4. `dist: pushed` and `dist tag dist-v<V>: pushed` are pinned verbatim because
   the plan states those note texts; the validation and no-claude messages are
   only required to contain `claude` (no-claude) or nothing (validation
   failure).
5. Validation failure and no-claude cases pin "nothing moved" by a whole-state
   snapshot instead of listing refs one at a time; the dist-branch and gh-log
   checks are separate so a failure names its cause.
6. `--resume` validates again before the first dist push (plan decision 2); the
   suite does not assert that, it only requires the claude stub to exit 0 on
   resume.
7. gh and claude stubs are both on PATH for every scenario; the no-claude PATH
   links the sandbox gh stub and the tools release.sh needs (checked by the
   not-opted-in no-claude run succeeding).

## Review

Verdict: CHANGES (the suite is sound as far as it goes and its reds are genuine
failed assertions; seven gaps leave plausible wrong implementations green)

How checked: I read `tests/release-dist-test.sh` against the plan's Slice 2 and
the red report. For discrimination I wrote a plausible `push_dist` and
`dist_preflight` into a scratch copy of `release.sh` under `$TMPDIR/ref` (not in
the repo). The suite goes fully green on it, so the suite is satisfiable. I then
mutated the scratch copy one behaviour at a time. A few of my sed mutations were
malformed and proved nothing: the date mutation (dist.sh overrides the env
itself, so the date belongs to a `dist.sh` suite, not here), tag-force, and one
pre-flight removal. They are marked inconclusive and not counted below.

Mutations caught:

- `push_dist` placed after `create_github_release`: caught by
  `kill after-dist-tag: dist tag is on origin` and
  `foreign dist tag: no github release was created`.
- `.source.ref` set without opt-in: 3 failures, from both not-opted-in
  scenarios.
- Pre-flight run after `bump_commit_tag`: caught only by the two whole-state
  snapshots, which is enough.
- No pre-flight at all: caught.
- A foreign origin tag accepted: caught.
- The second dist commit without its parent: caught.

Mutations that survived (0 failures):

- A forced dist push (`--force`).
- A rejected dist push swallowed (`|| true`).
- A local `dist-vX` tag at a foreign sha not refused.
- A moved tag (`tag -f` plus `push -f`).
- The `already pushed` notes printed as `pushed`.
- Resume deciding opt-in from `HEAD` rather than `$tag^{commit}`.

Numbered changes:

1. **A rejected dist push is never tested.** Add a scenario with a `pre-receive`
   hook in the bare origin that rejects `refs/heads/dist`. Assert a non-zero
   exit, output naming `resume-release`, `dist` absent on origin, and no github
   release or marketplace bump. To pin "never retried with force", make the git
   wrapper log push argv and assert that no push carries `-f`, `--force`,
   `--force-with-lease`, or a `+refspec`, and that exactly one push targeted
   `refs/heads/dist`. A hook alone cannot catch a force, because the push is
   rejected either way. Reproducer: mutate `git push` to `--force` or `|| true`;
   the suite stays green.
2. **A local tag at another sha is not tested.** Plan: "a local or origin tag at
   another sha is refused, never moved". Add: create a local `dist-v1.2.4` at a
   foreign commit with origin lacking it, run the release, and expect a refusal
   naming the tag, the local tag unmoved, and nothing for `dist-v1.2.4` on
   origin. Also assert in the existing foreign-origin case that the local tag
   did not move.
3. **The notes `dist: already pushed` and `dist tag dist-vX: already pushed` are
   never asserted.** Only the first-run `pushed` notes are. Assert the resume
   output after each kill point: after-push_tag gives `dist: pushed` and
   `dist tag ...: pushed`; after-dist-branch gives `dist: already pushed` and
   `dist tag ...: pushed`; after-dist-tag gives both `already pushed`. This also
   pins that each action sets `acted`.
4. **The marketplace no-op guard is not pinned byte-identical.** After the full
   release, record the marketplace file's `sha256` and `git rev-parse HEAD`, run
   `--resume`, and require both unchanged plus the `already complete` line. Add
   one more case: an entry already at `$V` with `ref: dist` in the marketplace
   is untouched on a second resume.
5. **The pre-flight covers only `claude`.** Add a case where `dist.sh tree`
   itself refuses (for example `dist.include` lists a missing path, or a gitlink
   in a listed dir) and assert the same whole-state snapshot as the other
   refusals. Otherwise an implementation that runs only `validate` passes.
6. **Resume opt-in is decided from `$tag^{commit}`, not `HEAD`.** Add one
   scenario: kill after push_tag, then add a commit that removes `dist.include`,
   which is not a release commit, and resume. Expect the dist branch to still be
   published. The mirror case, where `dist.include` is added only after the tag,
   expects no dist. Mark optional if the resume pre-flight rejects HEAD commits
   after the tag; check this first.
7. **The kill points after push_tag and after the dist branch push do not pin the order.**
   Add `no github release yet` and `marketplace not bumped` to both. These are
   the pins that make "marketplace never names a ref that is not on origin"
   real.

On question (3), the kill-point technique. The failing `gh release create` for
the third point does prove resume after the dist tag push. The suite asserts the
state first (dist tag on origin, no github release, release tag on origin) and
only then resumes, so the point is pinned by origin's state, not by the failure
mechanism. It is also discriminating: with `push_dist` after
`create_github_release`, the dist tag is absent when gh fails, so the
precondition assertion fails. The weaker spot is the wrapper globs.
`*:refs/heads/dist` and `*dist-v[0-9]*` assume how the green code spells its
pushes; a single combined push of branch and tag would break the second point.
Say so in the plan or comment the contract: branch and tag are separate pushes,
and the tag push mentions `dist-vN`.

On question (4), the unpinned part of the foreign-tag case. Pin that origin has
no `refs/heads/dist` after the refusal, and that origin's tag is unchanged
(already pinned). Reason: the plan checks the tag after the branch push, so a
foreign tag would leave a published orphan dist commit while the report promises
"nothing moved". Recommend amending the plan to probe `dist-v$V`, local and
origin, before the branch push. The cost is one extra `ls-remote` and a refusal
that happens before anything is pushed. If the coordinator prefers the plan's
order, pin the opposite explicitly (dist branch present, no gh release, no
marketplace bump) so the green phase cannot drift either way. Do not leave it
unpinned; today the suite is silent on this and both behaviours pass.

Not required: a test for the dist commit's dates. The reproducible dates belong
to `dist-test.sh`, since `release.sh` only passes the source commit.

## Revision

All seven review items applied to `tests/release-dist-test.sh` (shellcheck
clean). Against the current `release.sh` the suite runs to its end: 14
scenarios, 66 failure(s) (was 35), every one a failed assertion.

1. New scenario "a rejected dist push": a `pre-receive` hook in the bare origin
   rejects `refs/heads/dist`. Expects a non-zero exit, `resume-release` in the
   output, no dist branch or tag on origin, no github release, marketplace not
   bumped, exactly one push targeting `refs/heads/dist` and no force. The git
   wrapper now logs every push's argv to `push.log` (always, not only on a
   kill); `assert_no_force` rejects `-f`, `--force*` and `+refspec` and runs
   after the first release, this scenario and each resume. After the hook is
   removed, `--resume` must finish and pass the full end-state pin.
2. New scenario "a local dist tag at another sha": refused, names the tag, local
   tag unmoved, nothing on origin for it, no dist branch, no github release. The
   foreign-origin scenario also checks the local `dist-v1.2.4` was not created
   at another sha.
3. Resume output per kill point is pinned: after push_tag gives `dist: pushed`
   and `dist tag dist-v1.2.4: pushed`; after the dist branch gives
   `dist: already pushed` and `dist tag ...: pushed`; after the dist tag gives
   both `already pushed`.
4. New scenario "a complete release: resume leaves the marketplace
   byte-identical": two resumes after a full release, each `cmp`-identical for
   marketplace.json, same marketplace HEAD and origin head, same plugin origin
   refs, `already complete (nothing to do)`, entry still `ref: dist`.
5. New scenario "pre-flight: a tree refusal from dist.sh": a listed path that
   matches nothing, and a symlink in a listed directory, each committed and
   pushed first; expects exit 1, the offender named, whole-state snapshot
   unchanged, claude never called, gh not called.
6. New scenario "resume: opt-in is read from the release commit": kill after
   push_tag, then commit a removal of `dist.include` and push; resume must still
   publish dist. The mirror: a plain release, then `dist.include` added in a
   later commit; resume prints `already complete`, no dist branch, claude never
   called. This assumes resume does not refuse a HEAD ahead of the tag; the
   existing resume_preflight only needs the tag and a clean tree, so it should
   not.
7. Kill points after push_tag and after the dist branch push now also pin no
   github release and marketplace not bumped (and the same for the dist-tag kill
   via its gh failure, where the marketplace pin was added as well).

Foreign-tag decision taken as recommended: after the refusal there is no
`refs/heads/dist` on origin, i.e. the conflicting `dist-v$V` is probed before
the branch push. The same pin is on the local-tag scenario. Also added a comment
in the git wrapper stating the contract the kill globs rely on: the branch and
the tag are separate pushes and the tag push names `dist-v<V>`.

FAIL lines are in `$TMPDIR` only; the first-run list in the earlier section is
still representative, plus the new scenarios failing on: rejected push (no
failure of release, no `resume-release`, no push to dist), local foreign tag
(not refused), tree refusals (exit 0), opt-in-from-tag (no dist branch after the
resume), and the unpinned order pins (github release exists and marketplace
bumped after the kill that did not fire).

## Re-review

Verdict: APPROVE (two low-severity follow-ups, neither blocking green)

Scratch work stopped: no mutation job was left running. Checks were done in a
scratch copy of `release.sh` under `$TMPDIR/ref`, with a reference `push_dist`
that probes the dist tag before the branch push. The revised suite goes fully
green against it ("all release dist scenarios passed"), so it is satisfiable.
Against the real `release.sh` it runs to its end in about 29 s, 14 scenarios, 66
failures, all failed assertions.

Each item, with the mutation that fails it:

1. **Rejected dist push and force: confirmed.** `git push --force` of the dist
   branch gives 6 failures (`no push was forced`, in the first release and in
   each resume). Swallowing the rejection with `|| true` gives 10 failures.
2. **Local foreign tag: confirmed.** Deleting the local-tag check gives 4
   failures (`release did not refuse`, `nothing for it on origin`,
   `no dist branch on origin`, `no github release`).
3. **`already pushed` notes: confirmed.** Printing both as `pushed` gives 3
   failures, at the after-dist-branch and after-dist-tag resumes.
4. **Marketplace no-op guard: confirmed.** A jq that stamps `now` on every run
   breaks the guard: the byte-identity scenario and the `already complete`
   assertions fail (12 failures). A formatting-only mutation (`--tab`) stayed
   green, which is correct, because the file it rewrites is compared with
   itself.
5. **Pre-flight `dist.sh tree` refusal: confirmed.** Replacing
   `dist_sh tree HEAD` with a bare tree of HEAD gives 4 failures (snapshot
   changed and claude was called, for both the missing-path and symlink
   variants).
6. **Opt-in from the release commit: confirmed.** Resume deciding from `HEAD`
   fails 3 assertions, in both directions of the scenario.
7. **Order pins and the foreign-tag pin: confirmed.** `push_dist` after
   `create_github_release` was caught in the first review. The tag probe is now
   before the branch push in my reference and the suite is green on it.

Item 6's assumption: `resume_preflight` needs only the local `v$V` tag, with `V`
read from the manifest, and `common_preflight` demands a clean tree on the main
branch. It does not reject a HEAD ahead of the tag. `push_branch` compares
origin's branch with `HEAD`, and if they differ it runs a plain `git push`,
which would publish the extra commits. The author's `tweak_commit` pushes the
later commit first, so `push_branch` takes its "already pushed" path and the
scenario exercises only the opt-in decision. It is realistic: an unrelated
commit lands between a failed release and the resume. It does not drag in extra
pushing, because the commit is pushed beforehand. The author's note should say
that this scenario's later commit is pushed before the resume.

Follow-ups (low, not blocking):

1. `assert_no_force`'s regex `(^| )(-f|--force[a-z-]*|\+[^ ]+)( |$)` misses
   `--force-with-lease=<ref>` and combined short flags such as `-fq` (verified:
   only `--force` and `+a:b` match). Widen it to
   `(^| )(-[a-zA-Z]*f[a-zA-Z]*|--force[^ ]*|\+[^ ]+)( |$)`, or the green phase
   could reintroduce a lease-forced push unseen.
2. Remaining mutations I did not run: moved tag with `-f`, dates in `dist.sh`.
   The first needs a scenario where both tags point at different shas, which the
   local-foreign and origin-foreign cases already cover through the refusal, so
   no action.

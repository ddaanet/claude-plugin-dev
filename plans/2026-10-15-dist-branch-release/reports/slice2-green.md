# Slice 2 green report

Changed: `toolkit/release.sh` only. `toolkit/dist.sh` untouched (no interface
gap). No test edited, nothing committed.

## git diff --stat

```
 toolkit/release.sh | 151 +++++++++++++++++++++++++++++++++++++++++++++++++++--
 1 file changed, 146 insertions(+), 5 deletions(-)
```

## Gates

- `bash -n toolkit/release.sh`: clean (no output, exit 0)
- `shellcheck toolkit/release.sh`: clean (no output, exit 0)
- `bash tests/release-dist-test.sh`: `all release dist scenarios passed` (0
  failures)
- `bash tests/release-test.sh`: `all release scenarios passed` (0 failures)

## What changed in release.sh

- Header comment: one paragraph on the dist opt-in.
- `dist_on` global, set by the opt-in helpers.
- `dist_preflight` (new, release mode): runs after `release_preflight` and
  before `bump_commit_tag`. It is a separate step because `release_preflight`
  returns early on a first release. It refuses without `claude` on PATH, then
  `dist.sh tree HEAD`, then `dist.sh validate`. Any failure dies before any
  commit or tag.
- `dist_opted_in <commit-ish>` (new helper, after its caller):
  `dist.sh enabled`; exit 0 sets `dist_on=1`, exit 1 sets `dist_on=0`, any other
  status dies. Release calls it with `HEAD`; resume calls it with
  `"$tag^{commit}"` after `resume_preflight`.
- `push_dist` (new, between `push_tag` and `create_github_release`): reads
  origin's `dist` tip, and if its subject is `dist v$V from <tag commit>` uses
  it as landed (fetching it when not local). Otherwise builds the tree from the
  tag commit, validates it on resume only, and runs `dist.sh commit` with the
  tip as parent (none when absent). It probes local and origin `dist-v$V` before
  any push and refuses a tag at another sha. Then it pushes
  `sha:refs/heads/dist` without force (a rejected push dies with a
  `just resume-release` hint), then creates and pushes the lightweight
  `dist-v$V`. Notes: `dist: pushed` / `dist: already pushed`,
  `dist tag dist-v$V: pushed` / `already pushed`.
- `bump_marketplace`: both jq paths take `--argjson dist`. Opted in, the
  existing entry gets `.source.ref = "dist"` and the created entry's `source`
  gains `ref: "dist"`. The no-op `cmp` guard is unchanged.
- Dispatch: `dist_preflight` after `release_preflight` in release mode;
  `dist_opted_in "$tag^{commit}"` in resume mode; `push_dist` only when
  `dist_on=1`.

## Deviations from the plan text, for the reviewer

1. A plugin with `dist.include` but a `release.sh` vendored without `dist.sh` is
   refused with `dist.sh is missing`, instead of releasing without the dist
   branch. This was needed because `release-test.sh`'s fixture copies only
   `release.sh` and `check-version.sh`, and a plain release must still pass
   there. Plugins without `dist.include` are unaffected.
2. `dist_preflight` is a separate function rather than code inside
   `release_preflight`, for the early-return reason above.

## Tests I believe are wrong

None found. `release-dist-test.sh` is satisfied as written; the only thing it
does not pin is the missing-`dist.sh` refusal from deviation 1, which the test
does not require either way.

## Green review

Verdict: APPROVE. No blocking finding; three optional notes below.

Probed with scratch runs (fixture of tests/release-dist-test.sh, scripts under
`$TMPDIR/rv`), beyond what the suites cover:

- Resume from a shallow, single-branch clone with no local dist objects, after a
  kill at the dist tag push: `git fetch -q origin dist` fetches the tip, the
  subject matches, the tag is created and pushed, release completes.
- Second release killed at the dist branch push, resumed from a shallow clone
  that lacks the first release's dist tip: the fetch succeeds and the rebuilt
  commit has the tip as parent (2 commits on origin, one new, no force).
- Gaps between commands: branch pushed / tag not (covered by the suite, and by
  the above); local tag created / push failed (probe takes
  `local_dist == dist_sha`, pushes); crash before any push (rebuild is date- and
  parent-reproducible). Each resumes with no manual repair.
- Not opted in: output of a patch release plus a resume-complete run, with shas
  and temp paths normalised, is byte-identical against HEAD's release.sh, both
  with `dist.sh` beside it and with `dist.sh` absent (24 lines each, diff
  empty).
- Deviation 1: with `dist.include` committed and `dist.sh` removed, release
  exits 1 with the "update the toolkit" message, HEAD unmoved, no tag. It is
  consistent with "allowlist read from the commit" (it reads `git ls-tree` of
  that commit, as `dist.sh enabled` does). A shipped toolkit always carries both
  scripts, so in production the branch is reachable only by a partial vendoring;
  refusing is the right behaviour there. Deviation 2 is sound:
  `release_preflight` returns early on a first release, so a separate step is
  the only way to cover that path.
- errexit: no `&&` list as a last command, no `local x=$(...)`,
  `if ...; then push_dist; fi` is used. shellcheck is clean per the report.

Notes (none required for approval):

1. Low, hardening. The "already landed" test trusts the tip's subject alone. A
   foreign commit on `dist` with subject `dist v$V from $src` (needs push access
   to origin, and `$src` is public once the tag is pushed) is accepted as this
   release's dist and is then tagged `dist-v$V`, whatever tree it holds.
   Reproducer: kill a release at the dist tag push, delete the local `dist-vV`
   tag, `update-ref refs/heads/dist` on origin to a commit with an empty tree
   and that subject, `release.sh --resume`. With the local tag left in place the
   run is refused (`local dist-v… points at …, not …`), which is what I saw; the
   no-local-tag variant I reasoned about but did not run. Cheap fix: also
   require `git rev-parse "$tip^{tree}"` to equal the tree `dist.sh tree "$src"`
   builds (build the tree before the landed test). Whether it matters is the
   owner's call: push access to origin already allows anything.
2. Low, no change needed. Resuming release V after a later release moved the tip
   (subject names V+1) does not match, so `push_dist` would build V on top of
   V+1. `release` refuses a new bump while the current version is unpublished,
   so the state is not reachable by the normal flow.
3. Nit. The missing-`dist.sh` refusal is the one new branch no suite pins.
   `parent="$tip"` is assigned and used once; the two `dist.sh commit`
   invocations could be one call with the optional parent. Neither blocks.

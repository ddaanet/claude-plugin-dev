# 2026-10-15 — release.sh is split into sourced siblings

`toolkit/release.sh` had grown to 1019 lines, past the 400-line cap on anything
a reader takes in at one go. Its functions fall into four groups, and each group
now has a file of its own. `release.sh` keeps the argument parsing, the `die`
and `note` helpers, the run's globals and the step sequence, and it sources the
four groups from its own directory (`$here`), the same way it already finds
`dist.sh`.

## What changed

- `release-preflight.sh` holds the checks every run makes before any side
  effect: `check_marketplace_writable`, the clean-tree check and its exemptions,
  and `common_preflight`.
- `release-tags.sh` holds the release-history reads (`semver_tags`,
  `release_tags`, `origin_release_tags`) and the two preflights that depend on
  them, `release_preflight` and `resume_preflight`.
- `release-publish.sh` holds the dist opt-in and its pre-flight,
  `bump_commit_tag`, `ls_remote_sha`, the branch, tag and dist pushes, and
  `create_github_release`.
- `release-marketplace.sh` holds `bump_marketplace`.
- The pieces are sourced rather than invoked because they communicate through
  globals (`V`, `tag`, `dist_on`, `acted`, `marketplace_entry_exists` and
  others). Invoking them would have turned those globals into cross-process
  signalling, which is a behaviour change. Sourcing also leaves a single `set`
  line in force, so the release suite's pipefail-stripped copies of `release.sh`
  still strip it for the whole flow.
- The function bodies moved unchanged. The only edits are to comments that said
  "this file" or "the top of the script" where they now mean `release.sh`.
- `tests/release-test.sh` and `tests/release-dist-test.sh` now copy every
  `toolkit/*.sh` into their fixture's `plugin-dev/` instead of a named list,
  which matches what a consumer vendors. No assertion changed.
- `precommit` runs shellcheck with `-x`, and `release.sh` carries
  `source-path=SCRIPTDIR`, so the sourced files are followed. Each sibling
  disables SC2034/SC2154 for the globals it shares.
- The comment in `version-guard.sh` and the matching argument in
  `docs/references/version-guard.md` used to say that `release.sh` "isn't
  written to be sourced". They now give the reason the filter is still
  duplicated: `semver_tags` lives in a file written for `release.sh`'s shell.
- `docs/design.md`'s comment-volume bullet counts the siblings too. It no longer
  says the dist tree ships no `docs/`, which stopped being true when the
  dist-branch chapter moved to `toolkit/docs/`.

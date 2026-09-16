# Item 1.1 slice 2 — GREEN report

Commit: `979e285` — "✨ Item 1.1/2 — non-semver v tags are not releases".

## Implementation

`toolkit/release.sh`, two new functions ahead of `release_preflight` (their
user, matching the file's existing pattern of `tree_is_clean` /
`clean_pathspecs` / `report_dirty` preceding `common_preflight`):

- `semver_tags()` — stdin-to-stdout filter,
  `grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$'`, with `|| [ "$?" -eq 1 ]` absorbing a
  no-match grep's exit 1 so an empty result is a value under
  `set -euo pipefail`, while a real grep error (status 2) still fails. Reason is
  in the code comment, per the runbook's standing constraint.
- `release_tags()` — `git tag --list 'v*' --sort=-v:refname | semver_tags`.

`release_preflight`'s detection predicate, `:224`, changed from
`[ -z "$(git tag --list 'v*')" ]` to `[ -z "$(release_tags)" ]`. Nothing else in
the function changed — `latest_tag` (`:249`, now a few lines further down) is
untouched, still built from unfiltered `git tag --list 'v*'`, per slice 3's
boundary. The header comment (`:11-14`) is untouched, also per slice 3.

Verified the pipeline's exit status under `pipefail`: `semver_tags`'s own
absorption makes it exit 0 on no match, so the `git tag --list | semver_tags`
pipeline's status is `semver_tags`'s, and `[ -z "$(release_tags)" ]` never dies
on an empty tag set.

## Slice 2 scenario

`tests/release-test.sh` — "release: non-semver v tags are not releases", as left
by the test review (strengthened HEAD-pinning tag assertion, plus the "manifest
untouched" / "makes no commit" checks). Not further modified.

## Verification

- `bash tests/release-test.sh` — full suite green, all 3 previously-red
  assertions in the new scenario now pass, and the three protected scenarios ("a
  first release publishes the manifest version verbatim", "tags with no
  marketplace entry is not a first release", "a non-v tag nearer than the
  release tag does not read as the latest release") stayed green.
- `bash -n toolkit/release.sh` and `shellcheck toolkit/release.sh` — clean.
- `just precommit` — green (hook suite, release suite, update-plugin-dev suite,
  dist-tree, docs, doc-sync all passed; the one `format-docs` MD013 note was in
  a slice-1 report file unrelated to this change and did not block the commit).

## Scope discipline

Touched only `toolkit/release.sh` (the two functions plus the one predicate
line). `tests/release-test.sh` carries only the test-review's fixes, not mine.
`latest_tag`'s filter routing and the `:11-14` header comment were left alone
for slice 3, as instructed.

## State on exit

Clean tree (`git status --porcelain=v1` empty, ignoring nothing — no
phantom-dotfile or memory-submodule noise present). One commit, `979e285`,
carrying `toolkit/release.sh`, `tests/release-test.sh`, and both slice 2 reports
(RED, test-review).

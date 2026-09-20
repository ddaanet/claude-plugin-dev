# Item 1.3 / Slice 1 — GREEN report

## Closing lines

Suite:

```
self-release.sh: ok
```

`just precommit`: final line `ok` (full run green — rumdl
whitespace/format-docs, shellcheck, `_import-check`, `version-guard-test.sh`,
`check-version-test.sh`, `release-test.sh`, `self-release-test.sh`,
`update-plugin-dev-test.sh`, `dist-tree-test.sh`, `docs-test.sh`,
`doc-sync-test.sh` all passed). The commit-msg hook re-ran `just precommit`
during `git commit` and it passed there too, before the commit was written.

Commit: `07b7ae9b4c7ac955f29a0fe212febfb20b7c2fcb`

```
commit 07b7ae9b4c7ac955f29a0fe212febfb20b7c2fcb
Author: David Allouche <david@ddaa.net>
Date:   Sun Sep 20 18:57:34 2026 +0200

    🐛 Item 1.3/1 — self-release lists and filters tags instead of git describe

 scripts/self-release.sh    | 29 ++++++++++++++++++++++++-----
 tests/self-release-test.sh | 19 +++++++++++++++++--
 2 files changed, 41 insertions(+), 7 deletions(-)
```

Only the two in-scope files rode along; no memory gitlink, no `.claude/` files,
no unrelated report files.

## What changed

`scripts/self-release.sh`'s `release_preflight` no longer calls
`git describe --tags --abbrev=0 --match 'v*'`. It now does:

```sh
tags=$(git tag --list 'v*' --sort=-v:refname) || die "git tag --list failed"
latest_tag=$(grep -m1 -E '^v[0-9]+\.[0-9]+\.[0-9]+$' <<< "$tags") || latest_tag=""
latest_tag=${latest_tag#v}
```

Capture-then-filter, not a pipe: the tag listing is assigned to `tags` and its
own exit status checked with `|| die`, mirroring `ls_remote_sha` above it in the
same file. The filter step reads `$tags` via a here-string into `grep -m1`, so a
listing failure cannot be absorbed by the filter's exit status — the same hazard
Item 1.1 fixed for `semver_tags`/pipeline status in `toolkit/release.sh` and
`scripts/self-release.sh`'s own `ls_remote_sha` comment already documents.

Only one test assertion in the change loop, since the batch handed off was
already the single new scenario
(`=== vnext on ancestry is not the latest tag ===`); it went green on the first
implementation, and the rest of the suite (all pre-existing scenarios) stayed
green on the same run — no regression loop was needed.

## The new comment

Placed above the capture-then-filter lines, in `release_preflight`, in the
file's own words (no citation into `toolkit/release.sh`):

- States `git describe`'s two failure modes: it returns the nearest tag of *any*
  name reachable from HEAD, so a non-release tag like `vnext` sitting on HEAD
  would be read as the latest release; and it only sees tags reachable from
  HEAD, so a release tag off HEAD's ancestry would be invisible rather than
  merely unranked.
- States that `--list 'v*' --sort=-v:refname` considers every `v*` tag
  regardless of reachability, ordered by version, and that the filter narrows
  that to the `X.Y.Z` shape — noting the `dist-v*` lineage is dropped by the
  filter, not by the glob.
- States the capture-then-filter/here-string reasoning, referencing
  `ls_remote_sha`'s own comment above in the same file (an in-file citation, not
  a cross-file one).
- States explicitly that duplicating the three-line tag listing
  `toolkit/release.sh` also does is **intentional**, not an oversight, per this
  file's own separation header at the top — three lines of listing is not worth
  a shared flow branching on which release this is. No line-number or path
  citation into `release.sh` is made; the point is argued from this file's
  header alone.

## The dist-tag-squatting comment, restated

Old text (explained the exclusion via the removed mechanism):

```
# The dist lineage, because `git describe --match 'v*'` ignores it: a squatting
# v0.2.0 reachable from HEAD is caught one guard earlier, by the drift check.
```

New text (same behaviour, restated on the surviving ground — the glob, now
filtered further):

```
# The dist lineage, because the X.Y.Z filter over the `v*` listing excludes it:
# a squatting v0.2.0 reachable from HEAD is caught one guard earlier, by the
# drift check.
```

## Scope confirmation

- `scripts/self-release.sh`: only `release_preflight`'s latest-tag determination
  and its comment changed. No other function touched.
- `tests/self-release-test.sh`: no assertion in the slice-1 scenario was edited;
  only the dist-tag-squatting comment above the `=== preflight refusals ===`
  block's squatting sub-scenario was restated. Slice 2's test was not written.
  None of the four fixtures Item 2.1 will strengthen (happy path's
  `tree left dirty` check, the dist-split scenario, the `.claude`/ `memory`
  clean-check exemptions, the ten refusals) were touched.
- `toolkit/release.sh`, `tests/release-test.sh`, `tests/version-guard-test.sh`,
  docs, README files, `justfile`: untouched.

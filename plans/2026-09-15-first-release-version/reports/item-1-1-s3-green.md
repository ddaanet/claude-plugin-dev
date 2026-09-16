# Item 1.1 slice 3 — GREEN report

Slice commit: `3fd4d648dd7da0af4308eb12f22772baf69cc848` — "Item 1.1/3 —
latest_tag skips non-semver tags". Carries the two red scenarios (from
`tests/release-test.sh`), the implementation in `toolkit/release.sh`, and the
RED and test-review reports.

## Implementation

`release_preflight` (`toolkit/release.sh`) no longer builds a second,
unfiltered tag listing for `latest_tag`. It reuses `release_tag_list` — the
semver-filtered, newest-first listing `release_tags` already produced and
`release_preflight` already captured earlier in the same function, with its
own `|| die` on a failed `git tag`/`semver_tags`:

```sh
latest_tag=$(printf '%s\n' "$release_tag_list" | sed -n '1s/^v//p')
```

Restated the header comment at `:11-14` (now `:11-16`) to state the detection
predicate — no tag matching `^v[0-9]+\.[0-9]+\.[0-9]+$` exists yet, and the
marketplace entry plays no part — rather than only naming the behaviour it
produces.

## Exit-status verification

The interface contract flagged the risk directly: `$(release_tags | sed -n
…)` would take `sed`'s exit status under `set -o pipefail`, not
`release_tags`'s, so a failed listing inside that pipeline could pass
silently. I avoided the pipeline call site entirely rather than reason about
it — `latest_tag` is built from `$release_tag_list`, a plain variable already
captured with its own `|| die` a few lines above (`release_tag_list=$(release_tags)
|| die "could not list this plugin's release tags — nothing was done"`). The
`printf '%s\n' "$release_tag_list" | sed -n '1s/^v//p'` pipeline that follows
operates only on that in-memory string: `printf` cannot fail here and `sed -n`
with no match exits 0, so there is no second git call and no second status to
lose. I confirmed there is exactly one `release_tags` invocation left in
`release_preflight` (`grep -n 'release_tags' toolkit/release.sh` shows the
function definition and the single call site above `release_tag_list=`), so
the capture-and-check discipline the slice-2 review established has one
enforcement point, not two.

## Test results

- `bash tests/release-test.sh` — full suite green, including both of this
  slice's scenarios ("a non-semver v tag above the release tag does not read
  as the latest" and "a non-semver v tag above the release tag does not
  suppress the drift check") and the three named standing-green scenarios
  ("a first release publishes the manifest version verbatim", "tags with no
  marketplace entry is not a first release", "a non-v tag nearer than the
  release tag does not read as the latest release").
- `just precommit` — green (shellcheck, bash -n, `_import-check`, hook tests,
  release tests, update-plugin-dev tests, dist-tree test, docs test, doc-sync
  test all passed).

## Scope

Only `toolkit/release.sh` was touched for the implementation, as scoped.
`tests/release-test.sh` was not modified beyond what was already red and
handed over — no test was weakened, skipped, or rewritten.

Tree is clean after the commit.

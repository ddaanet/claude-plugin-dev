# Item 1.1 slice 3 — RED report

Scenario added to `tests/release-test.sh`, between "non-semver v tags are not
releases" (slice 2) and "tags with no marketplace entry is not a first release":
**"a non-semver v tag above the release tag does not read as the latest"**.

```sh
echo "=== release: a non-semver v tag above the release tag does not read as the latest ==="
new_sandbox "1.2.3"        # fixture keeps v1.2.3, entry at 1.2.3
git -C "$plugin" tag vnext
git -C "$plugin" tag v1.2
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "0" "non-semver-latest-tag exit code"
assert_contains "$out" "Release v1.2.4 complete" "non-semver-latest-tag summary"
assert_eq "$(jq -r .version "$plugin/.claude-plugin/plugin.json")" "1.2.4" \
    "non-semver-latest-tag manifest bumped"
```

`new_sandbox "1.2.3"` seeds the fixture's usual `v1.2.3` tag and marketplace
entry, matching the runbook's one fixture tag set (`vnext`, `v1.2`, `v1.2.3`)
once `vnext`/`v1.2` are added. No push of the two new tags: `latest_tag` reads
local tags only, so leaving them local is sufficient and keeps the scenario
minimal.

## Red run

```
$ bash tests/release-test.sh
...
=== release: a non-semver v tag above the release tag does not read as the latest ===
FAIL: non-semver-latest-tag exit code: expected '0', got '1'
FAIL: non-semver-latest-tag summary: output did not contain 'Release v1.2.4 complete'
  --- output ---
check-version: in sync (1.2.3)
hint: plugin.json holds the LAST released version, never the next one.
      `just release <bump>` computes the next one from it, so a manifest
      ahead of the newest tag means the bump was already written by hand and
      this run would publish a version past the one that was intended.
      revert it with `git checkout HEAD -- .claude-plugin/plugin.json`, then re-run
      with the bump you want.
      if v1.2.3 was in fact released and only the tag is missing here,
      `git fetch --tags` and re-run.
error: plugin.json version (1.2.3) does not match latest tag (vnext)
  --------------
FAIL: non-semver-latest-tag manifest bumped: expected '1.2.4', got '1.2.3'
...
3 failure(s)
```

All three of the new scenario's assertions fail, and the captured stderr shows
exactly the predicted mechanism: `latest_tag` (`release.sh:275`, unfiltered
`git tag --list 'v*' --sort=-v:refname | sed -n '1s/^v//p'`) picks `vnext` as
the newest tag, and the manifest-versus-latest-tag check refuses with
`does not match latest tag (vnext)`. No other scenario in the suite failed — 27
prior `echo` sections all ran clean — so this is not a setup error or a
missing-function error; it is the exact refusal the runbook names as the red for
this slice.

## Overlap with "a non-v tag nearer than the release tag does not read as the
latest release" (`tests/release-test.sh`, originally `:771`, now further down
after this insertion)

No overlap — the two scenarios exercise different tag shapes and different
history:

- The pre-existing scenario uses `nightly-2026`, a tag with
  **no `v` prefix at all**. `git tag --list 'v*'` never matches it, with or
  without the semver filter, so it was never a candidate for `latest_tag` under
  the current code either. Its point is that `git describe`'s distance-based
  nearest-tag behavior (the bug this toolkit avoided by using `git tag --list`
  in the first place) doesn't resurface — it adds a later commit and tags that
  commit, checking that the *newer, non-v-prefixed* tag doesn't get read as the
  release. It passes today and must keep passing unmodified.
- Slice 3's scenario uses `vnext`, which **does** carry the `v` prefix
  `git tag --list 'v*'` matches, and relies on `--sort=-v:refname` ranking
  `vnext` above `v1.2.3` (verified in the outline, git 2.47.3) — the exact case
  the two-part conjunct's replacement (`release_tags`/`semver_tags`) fixed for
  `release_tags` in slice 2 but `latest_tag` still doesn't use.

The pre-existing scenario does not cover slice 3's contract; the new scenario is
not a near-copy of it.

## Amended by the test review

The test review ([item-1-1-s3-test-review.md](item-1-1-s3-test-review.md)) added
a second scenario to this slice, "a non-semver v tag above the release tag does
not suppress the drift check". The scenario above proves the junk tag is not
picked; it does not prove the newest real release tag still is, and by mutation
a `release.sh` that merely skips the manifest-versus-latest-tag comparison when
the newest `v*` tag is not semver passed the whole suite. The slice is now four
failing assertions across two scenarios, not three across one.

## State on exit

- `tests/release-test.sh` — only file modified (`git status --porcelain=v1`
  shows `M tests/release-test.sh` alone).
- `toolkit/release.sh` — unmodified (`git diff --stat toolkit/release.sh`
  empty).
- No commit made.

# Item 1.1 slice 2 — RED report

Scenario added to `tests/release-test.sh`, between "a marketplace entry does not
exempt a first release from refusing a bump" (slice 1's last scenario) and "tags
with no marketplace entry is not a first release" (the unmodified `:634` guard):

```sh
echo "=== release: non-semver v tags are not releases ==="
new_sandbox ""            # no marketplace entry
make_virgin "0.1.0"       # no v* tags, manifest seeded by an external scaffold
git -C "$plugin" tag vnext
git -C "$plugin" tag v1.2
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "0" "non-semver-tags exit code"
assert_contains "$out" "Release v0.1.0 complete" "non-semver-tags summary"
assert_eq "$(git -C "$plugin" rev-parse -q --verify 'refs/tags/v0.1.0^{commit}' >/dev/null && echo yes || echo no)" \
    "yes" "non-semver-tags tag created"
```

No other change to the file. `toolkit/release.sh` untouched.

## Red run

`bash tests/release-test.sh`, against `toolkit/release.sh` as it stands at
`HEAD` (slice 1's narrowest predicate, `[ -z "$(git tag --list 'v*')" ]`, with
`latest_tag` still unfiltered):

```
=== release: non-semver v tags are not releases ===
FAIL: non-semver-tags exit code: expected '0', got '1'
FAIL: non-semver-tags summary: output did not contain 'Release v0.1.0 complete'
  --- output ---
check-version: no fixture entry in .../marketplace/.claude-plugin/marketplace.json — skip
hint: plugin.json holds the LAST released version, never the next one.
      `just release <bump>` computes the next one from it, so a manifest
      ahead of the newest tag means the bump was already written by hand and
      this run would publish a version past the one that was intended.
      revert it with `git checkout HEAD -- .claude-plugin/plugin.json`, then re-run
      with the bump you want.
      if v0.1.0 was in fact released and only the tag is missing here,
      `git fetch --tags` and re-run.
error: plugin.json version (0.1.0) does not match latest tag (vnext)
  --------------
FAIL: non-semver-tags tag created: expected 'yes', got 'no'

3 failure(s)
```

All three assertions fail for the reason the runbook names:
`git tag --list 'v*'` matches both `vnext` and `v1.2` (the glob has no version
anchor), so the predicate reads the plugin as already released and falls through
to the manifest-versus-`latest_tag` check. `latest_tag` sorts unfiltered tags by
`-v:refname`, where `vnext` sorts above `v1.2` and `v1.2.3`-shaped tags, so it
becomes `latest_tag`; `0.1.0 != vnext` trips the drift refusal, naming `vnext`
verbatim. Not a setup error or a missing function — each failure is the
scenario's own assertion comparing an actual value to an expected one.

## Suite otherwise green

Full run output (58 scenario headers, this one included) shows exactly these 3
failures; every other scenario passed, including the three the runbook pins
unmodified:

- "a first release publishes the manifest version verbatim" (title match for
  `:592`)
- "tags with no marketplace entry is not a first release" (title match for
  `:634`)
- "a non-v tag nearer than the release tag does not read as the latest release"
  (title match for `:721`)

## State on exit

- `tests/release-test.sh` — modified, slice 2's scenario only. Not committed.
- `toolkit/release.sh` — untouched.
- No other file changed.

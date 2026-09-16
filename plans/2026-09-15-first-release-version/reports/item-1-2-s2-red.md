# Item 1.2, slice 2 — RED report

**Case 4 obtained.** The scenario, written exactly as the runbook specifies,
passed against unchanged `HEAD` — slice 1's probe already reads "any semver tag
on origin", which is the interface this scenario exercises, so there was no
ordinary red to get. It is a characterization guard from here on, and its red
evidence comes from a mutation of the wrong implementation the runbook names,
not from a failing assertion against unmodified code.

## The scenario

Added to `tests/release-test.sh`, after the two slice-1 lost-tag scenarios
(`lose_tag` fixtures) and before "non-semver v tags are not releases":

```sh
echo "=== release: a lost local tag refuses even when the manifest was hand-advanced past a different real origin release ==="
# The manifest/entry version (1.3.0) and the lost origin tag (v1.2.3) are
# different strings here — unlike the two lost-tag scenarios above, where the
# manifest and the origin tag agree. That is what lets this scenario tell
# apart "the hint names the origin tag" from "the hint names the manifest
# version": only the former can pass here.
new_sandbox "1.3.0"
jq '.version = "1.3.0"' "$plugin/.claude-plugin/plugin.json" > "$plugin/.claude-plugin/plugin.json.tmp"
mv "$plugin/.claude-plugin/plugin.json.tmp" "$plugin/.claude-plugin/plugin.json"
git -C "$plugin" add -A
git -C "$plugin" commit -qm "hand-advance to 1.3.0"
git -C "$plugin" push -q origin main
lose_tag "$plugin"
origin_head_before="$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "hand-advanced-lost-tag exit code"
assert_contains "$out" "v1.2.3" "hand-advanced-lost-tag names the lost origin tag, not the manifest version"
assert_contains "$out" "git fetch --tags" "hand-advanced-lost-tag names the fetch remedy"
assert_not_contains "$out" "never been released" "hand-advanced-lost-tag must not read as a first release"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "hand-advanced-lost-tag created no local tag"
assert_eq "$(git -C "$plugin" ls-remote origin refs/tags/v1.3.0 | wc -l | tr -d ' ')" "0" \
    "hand-advanced-lost-tag did not push v1.3.0 to origin"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$origin_head_before" \
    "hand-advanced-lost-tag did not advance origin main further"
assert_eq "$(cat "$GH_LOG")" "" "hand-advanced-lost-tag must not call gh"
assert_eq "$(market_version)" "1.3.0" "hand-advanced-lost-tag must not touch the marketplace"
```

`new_sandbox "1.3.0"` seeds the marketplace entry at `1.3.0` and the plugin at
manifest `1.2.3` / tag `v1.2.3`, pushed. The manifest is then hand-advanced to
`1.3.0`, committed, and pushed — matching the runbook's "manifest hand-advanced
to `1.3.0`, committed and pushed" — before `lose_tag "$plugin"` drops `v1.2.3`
locally only, leaving origin's copy. No bump argument.

## Run 1 — against unchanged `HEAD`

Baseline confirmed clean first (`git diff --stat toolkit/release.sh` empty).

```
$ bash tests/release-test.sh
…
=== release: a lost local tag refuses even when the manifest was hand-advanced past a different real origin release ===
…
all release scenarios passed
```

Full suite: exit 0, `all release scenarios passed`. All prior scenarios
including slice 1's two lost-tag scenarios and the four first-release scenarios
still pass. No ordinary red — this is Case 4.

## Run 2 — mutation of the wrong implementation the runbook names

Narrowed the guard to fire only when origin carries `v$manifest_version`
specifically, computing that version early (it is otherwise not read until after
`check-version.sh`, later in the function):

```diff
         origin_tag_list=$(origin_release_tags) \
             || die "could not verify this plugin's release history on origin — nothing was done"
-        if [ -n "$origin_tag_list" ]; then
+        # MUTATION PROBE (item-1-2-s2-red): narrow to v$manifest_version only,
+        # the wrong implementation the runbook names. Restored before commit.
+        mv_manifest_version=$(jq -r .version "$manifest")
+        if printf '%s\n' "$origin_tag_list" | grep -qx "v$mv_manifest_version"; then
```

```
$ bash tests/release-test.sh
…
FAIL: hand-advanced-lost-tag exit code: expected '1', got '0'
FAIL: hand-advanced-lost-tag names the lost origin tag, not the manifest version: output did not contain 'v1.2.3'
FAIL: hand-advanced-lost-tag names the fetch remedy: output did not contain 'git fetch --tags'
FAIL: hand-advanced-lost-tag created no local tag: expected '', got 'v1.3.0'
FAIL: hand-advanced-lost-tag did not push v1.3.0 to origin: expected '0', got '1'
FAIL: hand-advanced-lost-tag must not call gh: expected '', got 'release view v1.3.0
release create v1.3.0 --title Release 1.3.0 --generate-notes'
…
6 failure(s)
```

The mutated code finds no `v1.3.0` on origin (only `v1.2.3`), reads the state as
a first release, tags and publishes `v1.3.0` — the exact outcome the runbook's
red rationale describes. `git diff` output above confirms exactly 6 failures,
all belonging to this new scenario; every other scenario (including slice 1's
two lost-tag scenarios, which use the *same-string* fixture and so cannot
discriminate this mutation) still passed. The two assertions on
`$market_version` and "origin main not advanced further" did not fail under this
mutation, because the marketplace entry was already at `1.3.0` (no bump needed)
and origin main had no new commits pushed either way — those two assertions are
not the ones this mutation trips, and that is expected, not a gap.

File restored (`cp` from a pre-mutation copy) and verified:
`git diff --stat toolkit/release.sh` empty.

## Run 3 — a further mutation of my own choosing

Chosen because a reader might expect this scenario, which does exercise the
origin-listing path, to incidentally also catch the sort-order bug slice 3 owns:
flipped `origin_newest=$(printf '%s\n' "$origin_tag_list" | sed -n '1p')` to
`sed -n '$p'` (oldest instead of newest).

```
$ bash tests/release-test.sh
…
0 failures
```

**It does not catch it**, and that is expected rather than a gap in this slice:
the fixture here carries exactly one origin tag (`v1.2.3`), so `1p` and `$p`
select the same line. Discriminating the sort requires two origin semver tags,
which is slice 3's `v1.9.0`/`v1.10.0`/`v1.11.0` fixture, not this one's. This
scenario's discrimination is *identity* (which tag the guard reads at all is
decided independently of the manifest), not *order* (which of several origin
tags is newest) — those are different bugs and this slice only closes the first.

File restored (`cp` from a pre-mutation copy) and verified:
`git diff --stat toolkit/release.sh` empty.

## `bash -n` / shellcheck

```
$ bash -n tests/release-test.sh   # OK, no output
$ shellcheck tests/release-test.sh   # OK, no output
```

## State on exit

- `toolkit/release.sh` — **untouched.** `git diff --stat toolkit/release.sh` is
  empty; both mutations were applied and reverted from pre-mutation copies in
  `/tmp/claude-1000` (this shell's `$TMPDIR` was unset — the environment
  caveat's documented failure mode — so absolute paths were used instead; no
  stray files were left in the repo root).
- `tests/release-test.sh` — **modified, uncommitted.** One new scenario added,
  no existing scenario weakened or touched. `git status --short` shows only this
  file.
- **Nothing committed.**
- `bash tests/release-test.sh` against the unmodified tree — green,
  `all release scenarios passed`.
- `bash -n` and `shellcheck` on `tests/release-test.sh` — both clean.

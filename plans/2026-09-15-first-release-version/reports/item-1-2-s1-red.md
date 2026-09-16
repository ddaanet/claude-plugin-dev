# Item 1.2, slice 1 — RED report

## Helper added

`lose_tag()`, placed right after `make_virgin` in `tests/release-test.sh`:

```sh
lose_tag() {
    # $1=repo path (default $plugin), $2=tag (default v1.2.3). Deletes the tag
    # from the local clone only, leaving origin's copy in place: the "lost
    # tags" state Item 1.2's origin probe exists to catch — a clone whose local
    # tag went missing while origin's release history did not. Contrast
    # make_virgin, which drops origin's copy too: a plugin that was truly
    # never released. Used by slices 1-4.
    local repo="${1:-$plugin}" tag="${2:-v1.2.3}"
    git -C "$repo" tag -d "$tag" >/dev/null
}
```

Contract: unlike `make_virgin` (deletes locally and pushes the deletion to
origin), `lose_tag` deletes the local tag only — origin keeps its copy. Both new
scenarios call it as `lose_tag "$plugin"` (an explicit arg, not relying on the
default, to keep shellcheck's SC2119/SC2120 quiet — see below).

## Scenarios added

Both live between the existing "a marketplace entry does not exempt a first
release from refusing a bump" scenario and "non-semver v tags are not releases",
next to the other `make_virgin`/first-release scenarios.

### Scenario 1 — explicit bump on a lost tag

```sh
echo "=== release: an explicit bump on a lost local tag refuses as unverifiable, not as a first release ==="
new_sandbox "1.2.3"
lose_tag "$plugin"
git -C "$plugin" commit --allow-empty -qm "later work"
origin_head_before="$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)"
run_in "$plugin" bash plugin-dev/release.sh patch
assert_eq "$rc" "1" "lost-tag-bump exit code"
assert_contains "$out" "v1.2.3" "lost-tag-bump names the lost tag"
assert_contains "$out" "git fetch --tags" "lost-tag-bump names the fetch remedy"
assert_not_contains "$out" "never been released" "lost-tag-bump must not read as a first release"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "lost-tag-bump created no local tag"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$origin_head_before" \
    "lost-tag-bump did not advance origin main"
assert_eq "$(cat "$GH_LOG")" "" "lost-tag-bump must not call gh"
assert_eq "$(market_version)" "1.2.3" "lost-tag-bump must not touch the marketplace"
```

### Scenario 2 — no bump argument on a lost tag

```sh
echo "=== release: a lost local tag with no bump argument refuses as unverifiable, not published as a first release ==="
new_sandbox ""
lose_tag "$plugin"
git -C "$plugin" commit --allow-empty -qm "later work"
origin_head_before="$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)"
run_in "$plugin" bash plugin-dev/release.sh
assert_eq "$rc" "1" "lost-tag-no-bump exit code"
assert_contains "$out" "v1.2.3" "lost-tag-no-bump names the lost tag"
assert_contains "$out" "git fetch --tags" "lost-tag-no-bump names the fetch remedy"
assert_not_contains "$out" "never been released" "lost-tag-no-bump must not read as a first release"
assert_eq "$(git -C "$plugin" tag --list 'v*')" "" "lost-tag-no-bump created no local tag"
assert_eq "$(git -C "$plugin" ls-remote origin refs/heads/main | cut -f1)" "$origin_head_before" \
    "lost-tag-no-bump did not advance origin main"
assert_eq "$(cat "$GH_LOG")" "" "lost-tag-no-bump must not call gh"
assert_eq "$(market_version)" "" "lost-tag-no-bump must not touch the marketplace"
```

Both fixtures carry "one unpushed commit on main" as the runbook specifies
(`git commit --allow-empty -qm "later work"`, never pushed) — that is what makes
the "origin main unmoved" assertion meaningful rather than trivially true, and
is what `push_branch` will find and push in scenario 2 today.

## Full red output (both scenarios, verbatim)

```
=== release: an explicit bump on a lost local tag refuses as unverifiable, not as a first release ===
FAIL: lost-tag-bump names the fetch remedy: output did not contain 'git fetch --tags'
  --- output ---
check-version: in sync (1.2.3)
hint: a first release publishes the manifest version as-is — there is no
      previous release to bump forward from. Re-run with no bump argument
      to publish v1.2.3.
      to publish some other version instead, set .version in .claude-plugin/plugin.json
      to it and commit that edit, then re-run with no bump argument. That
      edit is the one the version-guard hook refuses from an agent: it is
      the maintainer who decides what a plugin first ships as.
error: 'patch' bump refused: this plugin has never been released
  --------------
FAIL: lost-tag-bump must not read as a first release: output contained 'never been released'
  --- output ---
[same output as above]
  --------------
=== release: a lost local tag with no bump argument refuses as unverifiable, not published as a first release ===
FAIL: lost-tag-no-bump names the fetch remedy: output did not contain 'git fetch --tags'
  --- output ---
check-version: no fixture entry in <marketplace>/.claude-plugin/marketplace.json — skip
first release: publishing the manifest version 1.2.3 as-is (no bump)
tag: v1.2.3 created locally (manifest already at 1.2.3)
To <plugin-origin.git>
   4e45c81..d338772  main -> main
branch main: pushed
error: v1.2.3 on origin points at 6d5fc9ae7661efa0d36926a9cccb67045a818584, not 42fa91402df6714d7d3b45f10fb77503923848a1 — refusing to move a published tag
  --------------
FAIL: lost-tag-no-bump created no local tag: expected '', got 'v1.2.3'
FAIL: lost-tag-no-bump did not advance origin main: expected '4e45c81f296fd816ffa02c5786ae040b9d255985', got 'd338772ff17e5104478433bbb3e41c30b2927d9c'

5 failure(s)
```

(shas are non-deterministic across runs; the shapes above are representative of
a real run captured during this dispatch.)

## Discriminating vs. pass-today assertions

**Scenario 1** (`patch`, entry present):

- Discriminating (fail today): `git fetch --tags` present; `never been released`
  absent. Today's code refuses in Item 1.1's bump-refusal branch
  (`release_preflight`, empty `release_tags` + non-empty `bump_arg`), which
  names `v1.2.3` and says "never been released" — the exact wrong-reason refusal
  the runbook calls out.
- Pass today, kept as regression guards for the green implementation:
  - `rc=1` — already true, for the wrong reason; not discriminating alone.
  - `v1.2.3` present — already true (the bump-refusal hint says "to publish
    v1.2.3"); kept because the eventual fetch hint must also name it.
  - `git tag --list 'v*'` empty — the bump refusal dies in `release_preflight`
    before any tag is created, so this is trivially true today. Guards that the
    origin probe's refusal also stays preflight-only, no side effects.
  - origin `refs/heads/main` unmoved — true today (nothing pushes before the
    refusal). Guards the same property once the probe replaces the bump refusal
    as the first thing that fires.
  - `$GH_LOG` empty, marketplace untouched — true today for the same reason;
    guard that the origin probe stays side-effect-free on refusal.

**Scenario 2** (no bump, entry absent):

- Discriminating (fail today): `git fetch --tags` present; `git tag --list 'v*'`
  empty; origin `refs/heads/main` unmoved. Today's code treats the empty local
  tag list as first-release, tags HEAD (the unpushed "later work" commit),
  pushes the branch (this is what moves origin's `main`), and only then dies in
  `push_tag` because the newly-created local tag's object doesn't match origin's
  existing `v1.2.3`.
- Pass today, kept as regression guards:
  - `rc=1` — already true, but for the wrong reason (`push_tag`'s "refusing to
    move a published tag", not a lost-tags refusal). The runbook calls this out
    explicitly: exit code alone is not red here.
  - `v1.2.3` present — true today via `push_tag`'s die message, which names the
    tag; kept because the fetch hint must also name it.
  - `never been released` absent — already true today (this path never says it);
    kept as the same discriminator scenario 1 uses, for symmetry and as a
    green-implementation regression guard should some future refactor pull that
    wording in here too.
  - `$GH_LOG` empty — true today (`push_tag` dies before `create_github_release`
    runs).
  - marketplace untouched — true today (`push_tag` dies before
    `bump_marketplace` runs).

## Quality gates

- `bash -n tests/release-test.sh` — clean.
- `shellcheck tests/release-test.sh` — clean. (Initial version triggered
  SC2119/SC2120 on `lose_tag` because both call sites omitted the optional `$1`;
  fixed by passing `"$plugin"` explicitly at both sites rather than relying on
  the default.)

## State on exit

Modified: `tests/release-test.sh` only (added `lose_tag` helper and the two new
scenarios above). No other file touched, nothing committed.

`git diff --stat toolkit/release.sh` — empty, confirming the SUT is untouched.

## Amended by the test review

`lose_tag`'s first parameter is now required rather than defaulted to `$plugin`:

```sh
local repo="$1" tag="${2:-v1.2.3}"
```

The default could never be taken — shellcheck's SC2119 fires on the bare
`lose_tag` call, which is why both call sites pass `"$plugin"` explicitly — so
documenting it advertised an affordance slices 2-4 cannot use. The comment also
now records that `git tag -d` on an absent tag exits non-zero and aborts the run
under `set -e`, which is the helper's loud-failure guarantee.

The review re-ran the suite after the change: the same five assertions fail,
`bash -n` and `shellcheck` stay clean, and `toolkit/release.sh` is still
untouched. The mutation evidence behind the judgement — including that scenario
1 alone catches a probe placed behind the explicit-bump refusal, and that the
origin-tag identity, the `check-version.sh` ordering and the failed-listing case
are pinned by slices 2, 4 and 5 rather than here — is in
`item-1-2-s1-test-review.md`.

Scenarios pinned by the dispatch as must-stay-green throughout Phase 1 — "a
first release publishes the manifest version verbatim", "a marketplace entry
does not disqualify a first release", "a non-semver v tag above the release tag
does not suppress the drift check" — all still pass; none appear in the failure
list above.

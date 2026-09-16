# Item 1.2, slice 6 — GREEN report

## Implementation

`toolkit/release.sh`, `release_preflight()`:

- New local `verifiably_unpublished=0`, declared alongside the function's other
  locals.
- Set to `1` at the end of the lost-tags guard's
  `if [ -z "$release_tag_list" ]; then` block, immediately after the origin
  probe (`origin_release_tags`) comes back empty and the branch that would `die`
  on a non-empty origin listing is skipped. Reached only when there is no semver
  tag locally **and** none on origin — the guard's own definition of "verifiably
  unpublished" — so the flag is set exactly where the probe already proved the
  fact, with no second `git ls-remote`.
- `manifest_version=$(jq -r .version "$manifest")` moved up, from just after the
  `check-version.sh` call to just before it (previously computed once, after;
  now computed once, before — same single read, different point in the
  function). It is needed by decision 1's hint, which fires inside the
  `check-version.sh` failure block.
- The `check-version.sh` failure block now branches on `$verifiably_unpublished`
  before printing a hint:
  - `1` — decision 1's hint (below). No `just resume-release`.
  - `0` (the pre-existing behaviour, now the `else` path) — the unchanged
    `` `just resume-release` completes a release that landed partially. ``

### How "origin was tagless too" reaches the later branch point

The lost-tags guard's `if` block already runs the origin probe and captures its
result in `origin_tag_list` (landed in slice 1). That variable is `local` to
`release_preflight` as a whole — bash locals are function-scoped, not
block-scoped, so a `local` declared inside an `if` is visible for the rest of
the function once that `if` has executed — but the guard's own control flow
means the block runs at most once per call and its non-empty branch always
`die`s. So `origin_tag_list` itself would work as a signal, but reading it
directly at the failure point would require re-deriving "was it empty" from a
variable whose declaration is conditional on a branch that may never have run (a
call where `release_tag_list` was non-empty skips the whole block, and
`origin_tag_list` is then unset — `set -u` would fault on referencing it). A
dedicated flag declared unconditionally at the top of the function, defaulting
to `0` and flipped to `1` only on the path that proves the fact, avoids that: it
is always defined, and reading it needs no knowledge of which branch set it.
This is the "read the probe's status exactly once" route the dispatch asked for
— no second network call, and no re-inspection of a conditionally-declared
variable's definedness.

## Full hint text

```
hint: no release is recorded at 0.1.0 or 1.2.3 — this plugin has never been
      published under either version, so there is nothing to resume.
      correct the marketplace entry to match plugin.json (a successful
      first release would write 0.1.0 there anyway), or if 1.2.3 was the
      intended version, set .version in .claude-plugin/plugin.json
      to it and commit that edit, then re-run.
```

(`0.1.0`/`1.2.3` are the RED scenario's fixture values — `$manifest_version` and
`$market_version` in the general case.)

## Full-suite result

`bash tests/release-test.sh` — exit 0, `all release scenarios passed`, 48
scenarios. Slice 6's six previously-failing assertions now pass; the guard
scenario ("version drift on a plugin that HAS been released still offers
resume") stays green.

## `just precommit` result

Exit 0, `ok`. `shellcheck`, `bash -n`, `_import-check`, `tests/hook-test.sh`,
`tests/release-test.sh`, `tests/update-plugin-dev-test.sh`,
`tests/dist-tree-test.sh`, `tests/docs-test.sh`, `tests/doc-sync-test.sh` all
pass. `format-docs` (rumdl) reported 3 pre-existing `MD013` line-length hits in
`item-1-1-s1-red.md`, `item-1-1-s3-green.md` and `item-1-2-s1-test-review.md` —
all outside this slice's scope, none modified by this dispatch, and non-fatal to
the gate (`just precommit` still exits 0).

## Commit

Staged: `tests/release-test.sh`, `toolkit/release.sh`,
`plans/2026-09-15-first-release-version/reports/item-1-2-s6-red.md`,
`plans/2026-09-15-first-release-version/reports/item-1-2-s6-test-review.md`,
`plans/2026-09-15-first-release-version/reports/item-1-2-s6-green.md`.

Commit: `<filled in after commit>`.

## Tree state after commit

Clean, apart from any pre-existing staged `.claude/` files unrelated to this
slice (per the environment caveat — `.claude/` is exempt from the plugin's own
clean-tree check).

# Item 1.2, slice 1 — GREEN report

## Implementation

`toolkit/release.sh`:

- New `origin_release_tags()`, placed right after `release_tags()`. Mirrors its
  contract (semver tags, newest first via `--sort=-v:refname`) but reads
  `git ls-remote --tags --sort=-v:refname origin` instead of the local clone.

  Exit-status reasoning: `git tag --list` essentially never fails, but
  `git ls-remote` reaches the network and fails routinely (unreachable origin,
  no origin, auth). Piping it straight into `cut | sed | semver_tags` would be
  the fail-open shape the dispatch warned against: `semver_tags` absorbs a
  no-match `grep`'s status 1, so under `set -o pipefail` a failing `ls-remote`
  followed by filters that see empty input would still report the *pipeline* as
  succeeding — pipefail reports the last non-zero exit among the stages, and
  every stage after a failed `ls-remote` here legitimately exits 0 on empty
  input. So the function captures `git ls-remote`'s own output into a variable
  first and reads *that* command's status directly
  (`listing=$(git ls-remote …) || return 1`), then filters the captured text.
  This is the same shape Item 1.1 used for `semver_tags` itself and the pattern
  the dispatch pointed at explicitly.

- `release_preflight()` restructured:
  `release_tag_list=$(release_tags) || die …` now runs first, before
  `check-version.sh`. When it is empty, a new block runs before
  `check-version.sh`:

  ```sh
  if [ -z "$release_tag_list" ]; then
      local origin_tag_list origin_newest
      origin_tag_list=$(origin_release_tags) \
          || die "could not verify this plugin's release history on origin — nothing was done"
      if [ -n "$origin_tag_list" ]; then
          origin_newest=$(printf '%s\n' "$origin_tag_list" | sed -n '1p')
          printf 'hint: origin already has release tags for this plugin — the newest is\n' >&2
          printf '      %s, missing from this clone. Run `git fetch --tags` to catch up,\n' "$origin_newest" >&2
          printf '      then run the same command again.\n' >&2
          die "local release tags are missing — refusing to guess whether $origin_newest was published"
      fi
  fi
  ```

  Capture rule applied the same way as `origin_release_tags` itself: the
  `origin_tag_list=$(origin_release_tags) || die …` line reads the function's
  own status directly — never `[ -n "$(origin_release_tags)" ]`, which would
  discard a broken listing's status and let a network failure read as "origin
  has no tags either", a fail-open path into publishing a duplicate release on
  top of a history the probe could not actually see. A failed listing dies here
  instead, closed: `push_branch` and `push_tag` need origin anyway, so
  continuing would only move the failure past the point where a local tag could
  still have caught it.

  The guard reads "any semver tag on origin", not `v$manifest_version` only —
  `origin_tag_list` is the whole filtered listing and the die fires on any
  non-empty result, so a tagless clone hand-advanced past a real release
  (manifest at `1.3.0` over a published `v1.2.3`) is caught too, per the
  runbook's stated reason.

  `check-version.sh` and the rest of `release_preflight` are otherwise
  unchanged; the first-release branch further down now just tests the
  already-captured `release_tag_list` instead of recomputing it (previously it
  was computed once, after `check-version.sh`; now it's computed once, before).

## Full suite result

`bash tests/release-test.sh` — full run, exit 0, `all release scenarios passed`.
Both new scenarios ("an explicit bump on a lost local tag …", "a lost local tag
with no bump argument …") pass; all previously-green scenarios still pass,
including the three protected ones named in the dispatch ("a first release
publishes the manifest version verbatim", "tags with no marketplace entry is not
a first release", "a non-v tag nearer than the release tag does not read as the
latest release") and the four standing first-release scenarios ("a first release
publishes the manifest version verbatim", "a first release refuses an explicit
bump", "a marketplace entry does not disqualify a first release", "a marketplace
entry does not exempt a first release from refusing a bump").

## `just precommit` result

Green. `format-docs` reflowed both new report files (`item-1-2-s1-red.md`,
`item-1-2-s1-test-review.md`) at 80 columns before staging — run ahead of
`git add`, so nothing was left dirty by the hook afterward. `shellcheck`,
`bash -n`, `_import-check`, `tests/hook-test.sh`,
`tests/update-plugin-dev-test.sh`, `tests/dist-tree-test.sh`,
`tests/docs-test.sh`, `tests/doc-sync-test.sh` all pass.

## Left for slices 2-6

- **Slice 2**: origin-tag *identity* (fixture where manifest version and the
  lost origin tag differ, e.g. manifest hand-advanced to `1.3.0` over origin's
  `v1.2.3`) is not separately exercised here — `assert_contains "$out" "v1.2.3"`
  in slice 1 cannot distinguish "names the origin tag" from "names the manifest
  version" because both scenarios use the same string. The implementation
  already reads any semver tag on origin (not just `v$manifest_version`), per
  the runbook, but slice 2 is what will pin that behaviorally.
- **Slice 3**: no change to `resume_preflight`'s no-tag refusal or its hint
  ladder. Untouched.
- **Slice 4**: the probe's placement *before* `check-version.sh` is implemented
  (see above) but not separately pinned by a drift fixture here; slice 4 owns
  that fixture (origin `v1.2.4`, manifest `1.2.4`, entry `1.2.3` → fetch hint,
  not drift hint).
- **Slice 5**: the failed-listing path
  (`die "could not verify … — nothing was done"`) is implemented per the capture
  rule but not exercised by any red scenario here — no fixture in this slice
  breaks origin. Slice 5 is where an unreachable/absent origin gets tested; the
  current message is a narrowest-correct placeholder, not validated against
  slice 5's exact wording requirements. It's plausible slice 5 will want the die
  message reworded (e.g. to explicitly suggest `git fetch --tags` or name why
  origin couldn't be reached) — this implementation did not attempt to
  anticipate that wording.
- **Slice 6**: `check-version.sh`'s failure hint (`release.sh:301-305`, formerly
  `:202-206`) is untouched — still offers `just resume-release` unconditionally.
  Decision 1's branch (verifiably-unpublished plugins get a different hint) is
  not implemented.
- **Item 1.4** (the resume-side origin probe) is untouched — `resume_preflight`
  has no origin check.

## Commit

`bash tests/release-test.sh` and `just precommit` both green as reported above.
Staged and committed: `tests/release-test.sh`, `toolkit/release.sh`,
`plans/2026-09-15-first-release-version/reports/item-1-2-s1-red.md`,
`plans/2026-09-15-first-release-version/reports/item-1-2-s1-test-review.md`.

Commit: `9d4b9f1` — "✨ Item 1.2/1 — lost-tags origin probe refuses an
unverifiable local tag list"

## Tree state after commit

Clean except pre-existing staged `.claude/handoff-task.md` and
`.claude/handoff-todo.md`, which were already staged before this dispatch
started and are out of this slice's scope — left untouched.

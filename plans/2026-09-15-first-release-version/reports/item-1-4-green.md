# Item 1.4 — GREEN

Commit: `0c8d3ce` — "Item 1.4 — origin-aware hint ladder for resume_preflight's
no-tag refusal". Carries the implementation, `tests/release-test.sh`, and Item
1.4's RED and test-review reports in one commit.

## Ladder as implemented (`toolkit/release.sh:500-550`, inside
`resume_preflight`'s no-tag `||` group)

Four branches, in order, each producing the hint and then falling through to the
unchanged `die "no tag $tag for plugin.json version $V"`:

1. `printf '%s\n' "$origin_tag_list" | grep -qx -- "$tag"` (origin's listing
   contains `$tag` itself, tested by exact-line membership) → hint:
   `origin already has $tag — this clone is just missing it.` then
   `` run `git fetch --tags`, then run `just resume-release`. ``
2. `elif [ -n "$origin_tag_list" ]` (origin's listing is non-empty but didn't
   match branch 1 — some other semver tag) → hint:
   `origin has release tags, but none matching $tag.` then
   `` run `git fetch --tags`, then run `just release <bump>`. ``
3. `elif [ -z "$release_tag_list" ]` (no local semver tags at all) → hint:
   `no release was started at this version.` then
   `` run `just release` instead. `` (closing backtick immediately after
   `release`, no bump argument).
4. `else` (local tags exist, none matching, origin silent) → hint:
   `no release was started at this version.` then
   `` run `just release <bump>` instead. `` — today's pre-existing wording,
   unchanged.

## The single `origin_release_tags` read

`toolkit/release.sh:512`:

```bash
origin_tag_list=$(origin_release_tags) || origin_tag_list=""
```

This is the only call to `origin_release_tags` in the function — branches 1 and
2 both test the already-captured `$origin_tag_list` variable, never re-invoking
the probe. A failed listing (no `origin` remote, unreachable URL) is absorbed by
the `|| origin_tag_list=""` into the same value an empty-but- successful listing
produces, so it falls through to branches 3/4 exactly as a verified-empty origin
would — no `die`, no probe-failure wording, matching the outline's "the probe
only improves the advice." This is the opposite of `release_preflight`'s
neighboring origin probe, which `die`s on a failed listing because there a side
effect (tag/push) is still pending; here the refusal already happened (no local
tag) before the probe runs, so there's nothing left to protect.

`release_tag_list=$(release_tags)` is a plain, unguarded capture —
`release_tags` is `git tag --list`, which the codebase's existing comment
(`:277-282`) documents as essentially never failing, so no `||` fallback is
added there; consistent with how the rest of the file treats that call.

## Full hint text, verbatim

Branch 1:
```
hint: origin already has v1.2.3 — this clone is just missing it.
      run `git fetch --tags`, then run `just resume-release`.
```

Branch 2:
```
hint: origin has release tags, but none matching v1.3.0.
      run `git fetch --tags`, then run `just release <bump>`.
```

Branch 3:
```
hint: no release was started at this version.
      run `just release` instead.
```

Branch 4:
```
hint: no release was started at this version.
      run `just release <bump>` instead.
```

## Results

- `bash -n toolkit/release.sh` and `shellcheck toolkit/release.sh`: clean.
- `bash tests/release-test.sh`: all 52 scenarios pass, including all 7 Item-1.4
  scenarios (slices 1, 2, 3, 4a, 4b, plus the two test-review additions
  "origin's copy of v$V outranks a local tag this clone still has" and "v$V
  among origin's tags counts even when a newer tag sorts above it").
- `just precommit`: green — shellcheck, `bash -n`, `_import-check` (plain +
  widened + missing-gate), `tests/hook-test.sh` (13 scenarios),
  `tests/release-test.sh` (52 scenarios), `tests/update-plugin-dev-test.sh` (8
  scenarios), `tests/dist-tree-test.sh`, `tests/docs-test.sh`,
  `tests/doc-sync-test.sh`, `format-docs`. All passed; the pre-commit hook ran
  this same gate again on the commit itself and it passed there too.
- `format-docs` left 7 pre-existing MD013 overlength lines unwrapped in
  unrelated report files (`item-1-1-s1-red.md`, `item-1-1-s3-green.md`,
  `item-1-2-s1-test-review.md`, `item-1-3-s1-green.md`,
  `item-1-3-s2-test-review.md`, and two lines in this run's own
  `item-1-4-test-review.md`) — `rumdl fmt` exits 0 leaving what it cannot wrap
  in place; none of these are files this dispatch touched or is scoped to fix.

## Tree state after commit

`git status --porcelain` empty; `git log --oneline -1` is `0c8d3ce`.

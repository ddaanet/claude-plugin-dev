# Item 1.1 slice 2 — code review

Reviewed `979e285`'s change to `toolkit/release.sh`: `semver_tags()`,
`release_tags()`, and `release_preflight`'s detection predicate routed through
them. Verdict: the regex, the status-absorption idiom and the placement are all
correct, and the tests genuinely bind the filter — proved by mutation, not by
reading. One defect fixed: the predicate discarded the listing's exit status, so
a failed listing read as "never released" and would have tagged and published.
Two comments corrected, both of which asserted something false as written.

## 1. Exit-status behaviour, established by running

The dispatch asks what `semver_tags` actually produces in each failure mode.
Probed with a stub `grep` on `PATH` exiting 2, and outside a git repo, under
`set -euo pipefail`:

| situation | `semver_tags` status | `release_tags` status | reached the caller? |
| --- | --- | --- | --- |
| no matching line | 0 | 0 | n/a (success) |
| empty stdin | 0 | 0 | n/a |
| real grep error (2) | **1** | 1 | **no — discarded** |
| `git tag` fails (128) | 0 | 128 (pipefail) | **no — discarded** |

The absorption is exactly right: `{ grep -E '…' || [ "$?" -eq 1 ]; }` turns
status 1 into 0 and leaves status 2 as a non-zero (1, not 2, which does not
matter — what matters is that it is not success). Under `pipefail` a failing
`git tag` upstream sets the pipeline status even though `semver_tags` itself
exits 0.

**But none of that reached the caller.** `[ -z "$(release_tags)" ]` throws the
command substitution's status away entirely — `set -e` never sees it, because
the only status the `if` reads is `[`'s. Both failure modes produce empty
output, so both were read as "this plugin has no release tags", setting
`first_release=1` and falling through to `bump_commit_tag`, which tags `HEAD`
and publishes the manifest version. Verified directly:

```
--- with stub grep exiting 2:
grep: fake hard error
READ AS EMPTY (first release)
reached end
```

This is a fail-open in the one place the slice's whole contract is decided, and
it contradicted the comment the slice had just written ("a real grep error
(status 2) still fails the script" — it did not).

### Fix applied

`release_preflight` now captures the listing, so the status is read:

```sh
release_tag_list=$(release_tags) \
    || die "could not list this plugin's release tags — nothing was done"
if [ -z "$release_tag_list" ]; then
```

A bare `x=$(f)` assignment takes the substitution's status, so `|| die` catches
it and errexit is not relied on for the message. Re-probed: the stub-grep and
not-a-repo cases now both die with that message and exit 1, before any side
effect. `local manifest_version latest_tag` gained `release_tag_list` — declared
on the existing `local` line and assigned separately, never `local x=$(...)`,
which would mask the status behind `local`'s own 0.

**Reachability, and why no test was added.** `common_preflight` runs first and
needs a working repo (`git diff HEAD`, `git symbolic-ref HEAD` against
`origin/HEAD`), so a `git tag` that fails after it means git broke mid-run; a
grep exiting 2 on pipe input is equally improbable. The path is not reachable
through the fixture harness, so this is defence in depth rather than a scenario.
Pre-existing in kind — `[ -z "$(git tag --list 'v*')" ]` had the same hole
before the slice — but the slice is where a filter that can itself fail was
introduced, and where the comment claiming the opposite was written.

## 2. Comments corrected

- **`semver_tags`.** "a real grep error (status 2) still fails the script" was
  false at the only call site. Restated: a real grep error exits non-zero, and
  that only reaches the caller if the caller reads the status — capture into a
  variable, never `[ -z "$(…)" ]`. Written as the calling rule rather than a
  bare fact, since Items 1.2 and 1.4 add callers.
- **`release_tags`.** "Every caller names the newest tag, so the order is
  load-bearing" is not true of today's one caller, which tests emptiness. A
  reader checking it would conclude the comment is stale. Restated as a contract
  ("the order is part of the contract, since a caller naming a release takes the
  first line. Fixed here rather than at each call site") — true now, and it is
  what slice 3's `latest_tag` and Item 1.4's resume hint will rely on.

## 3. The `--sort=-v:refname` question

**It does nothing today.** The only consumer of `release_tags` is the emptiness
test, which is order-blind. Nothing in the suite pins the local sort either: the
runbook's "origin newest ≠ lexicographic first" scenario pins
`origin_release_tags`' sort (Item 1.2), and the local one becomes observable in
slice 3, when `latest_tag` takes the first line and the "`vnext` beside
`v1.2.3`" scenario distinguishes the orders. Keeping it here is correct — the
contract has to hold before the caller that needs it exists, or slice 3 would
have to add it and re-argue it — and it now says so in words rather than by
asserting something about callers. No change to the code.

Filtering after sorting preserves the relative order of the surviving lines, so
the non-semver tags that `-v:refname` sorts above real releases (`vnext` sorts
above `v9.9.9`, verified in the test-review's probe) do not perturb it.

## 4. Whitespace and globbing

Clean. A git tag name cannot contain whitespace, but the code would not split on
one anyway: the listing is consumed only as `release_tag_list=$(release_tags)`
(assignment — no word splitting, no globbing) and tested with `[ -z ... ]` on a
quoted expansion. No `for` over the output, no unquoted expansion, no `read`
without `-r`. Nothing here needs a NUL-delimited form; when Item 1.2 splits
`ls-remote` output into fields that will be the place to check again.

## 5. Mutation probe — the tests bind the filter

Ran once, in place, per the protocol: `toolkit/release.sh` copied aside, the
regex weakened from `^v[0-9]+\.[0-9]+\.[0-9]+$` to `^v[0-9]`, suite run, file
restored, `git diff` verified to show only my fix.

```
FAIL: non-semver-tags exit code / summary / tags HEAD
3 failure(s)
```

Under the weaker anchor `v1.2` survives the filter, the plugin reads as
released, and the run dies on manifest-versus-latest-tag naming `vnext`. So the
scenario is not merely green against the intended implementation — it
discriminates it from the nearest wrong one. This reproduces the test-review's
section 2 finding against the real SUT rather than a scratch copy.

## 6. Reviewed and not changed

- **Placement.** `semver_tags`/`release_tags` sit between `common_preflight` and
  `release_preflight`, matching the file's established helper-before-user layout
  (`tree_is_clean` / `clean_pathspecs` / `report_dirty` ahead of
  `common_preflight`). Both are called at runtime from the bottom of the file,
  so definition order is not a mechanical constraint; consistency with the file
  decides it.
- **The redundant inner `{ … }` in `semver_tags`.** A function body is already a
  group, so the braces buy nothing mechanically. Kept: they are the runbook's
  prescribed idiom verbatim, and Phase 2 duplicates this line into
  `version-guard.sh`, where the grouping is not optional. A difference between
  the two copies would be the drift the plan says the shared fixture set is
  meant to make visible.
- **The `git tag --list 'v*'` / `git describe` comment above the predicate**
  (`:239-241`). Still accurate — `release_tags` is built on `git tag --list`.
  Left alone rather than churned.
- **Naming.** `semver_tags` and `release_tags` are snake_case like every other
  function here, and `release_tags` reads as the thing rather than the action,
  matching `clean_pathspecs`.
- **`latest_tag`'s unfiltered listing (`:267`) and the header comment
  (`:11-14`).** Slice 3, correctly absent.

## 7. Seam noted, not acted on

`toolkit/release.sh` is 533 lines. The tag-listing group — `semver_tags`,
`release_tags`, and Item 1.2's `origin_release_tags` — is the one cohesive unit
in the file with no dependency on the release flow's globals, so it is the
natural seam if the file is split after Phase 1. The cost is not internal: every
shipped path is enumerated in `tests/dist-tree-test.sh` and CLAUDE.md's Layout
list, so a second file is a distribution change, not a refactor. Recorded for
the deferred decision; nothing split.

## 8. State on exit

- `toolkit/release.sh` — the only modified file, uncommitted.
  `git status --porcelain=v1` shows `M toolkit/release.sh` and nothing else.
- `bash -n toolkit/release.sh` — clean.
- `shellcheck toolkit/release.sh` — clean, no new `disable` directives.
- `bash tests/release-test.sh` — all scenarios passed.
- `just precommit` — green (hook, release, update-plugin-dev, dist-tree, docs,
  doc-sync).
- The mutated SUT was restored from the backup and the backup deleted; the regex
  line reads `'^v[0-9]+\.[0-9]+\.[0-9]+$'` again, confirmed by grep and by the
  diff above showing no change to it.
- Not committed, per the dispatch.

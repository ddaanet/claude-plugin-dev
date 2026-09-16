# Item 1.1 slice 3 — test review

Reviewed the RED tests for slice 3 (`latest_tag` routed through the semver
filter). The mechanical check passes: the slice's assertions fail on their own
assertions and nothing else in the suite moved. One real gap found and fixed by
mutation, not by reading — the scenario proved only half the contract, and a
plausible wrong implementation passed the entire suite. A second scenario now
pins the other half. The suite is still red, on four assertions across two
scenarios.

## 1. Mechanical check

`bash tests/release-test.sh` against unchanged `toolkit/release.sh`, as handed
over:

```
=== release: a non-semver v tag above the release tag does not read as the latest ===
FAIL: non-semver-latest-tag exit code: expected '0', got '1'
FAIL: non-semver-latest-tag summary: output did not contain 'Release v1.2.4 complete'
FAIL: non-semver-latest-tag manifest bumped: expected '1.2.4', got '1.2.3'
3 failure(s)
```

All three are assertion failures inside the new `echo` section. No scenario
errored during setup, none failed on a missing function (`release_tags` and
`semver_tags` both exist at `HEAD` from slice 2), and every other section ran
clean — the three named as standing green ("a first release publishes the
manifest version verbatim", "tags with no marketplace entry is not a first
release", "a non-v tag nearer than the release tag does not read as the latest
release") among them. The captured stderr shows the predicted mechanism
verbatim:
`error: plugin.json version (1.2.3) does not match latest tag (vnext)`, i.e.
`latest_tag` (`toolkit/release.sh:275`) picking `vnext` out of the unfiltered
listing. Red for the stated reason.

That also settles empirically, on this box's git, the ordering claim the
scenario rests on: `vnext` does sort above `v1.2.3` under `--sort=-v:refname`,
or the refusal would have named a different tag.

## 2. Discrimination probes

Each probe mutated `toolkit/release.sh` in place from a backup and restored it;
`git status` and `git diff --stat toolkit/release.sh` confirm the SUT is
untouched now.

| implementation under test | slice-3 scenario | rest of suite |
| --- | --- | --- |
| intended: `latest_tag=$(release_tags \| sed -n '1s/^v//p')` | pass | all pass |
| filter applied, `--sort=-v:refname` dropped | pass | all pass |
| weak anchor `^v[0-9]` throughout, routing intact | **pass** | slice 2's scenario fails (3) |
| unfiltered `latest_tag`, drift check skipped when the newest `v*` tag is not semver | **pass** | **all pass** |

Readings:

- **`v1.2` is inert in this scenario, and the RED report says so plainly** —
  correctly. Under a weakened `^v[0-9]` anchor `v1.2` survives the filter but
  still sorts below `v1.2.3`, so `latest_tag` is `1.2.3` either way and the
  scenario stays green. The anchor is pinned by slice 2's "non-semver v tags are
  not releases", which goes red under exactly that mutation (reproduced above,
  matching the slice-2 code review's own probe). No work was invented for
  `v1.2`; the comment now names where the anchor actually is pinned, and why the
  tag is nonetheless carried here (one fixture tag set across the two suites).
- **The local sort is not pinned by this scenario either.** With only one semver
  tag in the fixture, filtering alone decides the answer. That is a correction
  to the slice-2 code review's §3, which expected slice 3 to "distinguish the
  orders": it distinguishes filtered from unfiltered, not one sort order from
  another. Pinning the local sort needs two semver tags whose version order
  differs from their lexicographic order (`v1.10.0` beside `v1.2.3`), which is
  Item 1.2's "origin newest ≠ lexicographic first" scenario, for the remote
  listing. Left alone here — widening slice 3's fixture would duplicate that
  item.
- **The fourth row is the gap.** Routing `latest_tag` through the filter has two
  halves: the junk tag must not be picked, *and* the newest real release tag
  must still be picked and compared. The scenario proved only the first. An
  implementation that leaves `latest_tag` unfiltered and instead skips the
  manifest-versus-latest-tag comparison whenever the newest `v*` tag is not
  semver passed every scenario in the suite — and it is not a contrived mutation
  but the naive reading of "don't compare against a tag that isn't a release".
  Under it, a hand-bumped manifest over `v1.2.3` publishes a version past the
  intended one whenever some `vnext`-shaped tag exists, which is the precise
  failure `release.sh:275-290` exists to stop.

## 3. Fix applied

One scenario added to `tests/release-test.sh`, immediately after slice 3's
scenario:
**"a non-semver v tag above the release tag does not suppress the drift check"**.
Fixture: `new_sandbox "1.3.0"`, manifest hand-bumped to `1.3.0` and pushed (so
`check-version.sh` is in sync and the manifest-versus-tag check is the one that
fires — the same setup the pre-existing drift scenario uses), then `vnext`
tagged above the fixture's `v1.2.3`. Run `patch`; assert exit 1,
`does not match latest tag (v1.2.3)`, no `v1.3.1` tag, no `gh` call.

It is red today on its own assertion:

```
=== release: a non-semver v tag above the release tag does not suppress the drift check ===
FAIL: non-semver-latest-drift names the newest release tag, not the junk one:
      output did not contain 'does not match latest tag (v1.2.3)'
  --- output ---
  ...
  error: plugin.json version (1.3.0) does not match latest tag (vnext)
```

One assertion, not four: today's code already exits 1 here, creates no tag and
never calls `gh` — it refuses for the wrong reason, naming `vnext`. The other
three are the guard that the *green* implementation does not buy the right
message by moving the refusal somewhere later, and they are what turns red under
the fourth-row mutation (all four fail there). Re-probed after the addition:
intended fix → whole suite green; skip-the-check mutation → this scenario fails
on all four assertions.

No assertion on `vnext`/`v1.2` surviving the run, and none on the created tag
object in the positive scenario: `Release $tag complete` is the last line
`release.sh` prints (`:532`), after `push_branch`, `push_tag`,
`create_github_release` and `bump_marketplace`, so asserting the summary already
covers the whole publication and names the tag. That is recorded in the
scenario's comment rather than spent on a redundant assertion.

## 4. Overlap claim, verified against the file

The RED report's claim holds. `tests/release-test.sh`'s "a non-v tag nearer than
the release tag does not read as the latest release" tags `nightly-2026` — no
`v` prefix — on a later commit. `git tag --list 'v*'` never matches it, with or
without the semver filter, so it was never a `latest_tag` candidate and the
scenario cannot go red on slice 3's change; it passed in every run above,
including under all four mutations. It exercises `git describe`'s distance
ordering, a different mechanism from version ordering. The two scenarios are not
near-copies and neither subsumes the other.

## 5. Reviewed and not changed

- **Leaving `vnext` and `v1.2` local, unpushed.** `latest_tag` reads
  `git tag --list`, local only; pushing them would exercise nothing. Matches
  slice 2's scenario, which also tags locally.
- **Placement**, between slice 2's scenario and "tags with no marketplace entry
  is not a first release" — the tag-shape scenarios stay together.
- **Fixture tag set.** Both scenarios use only `vnext`, `v1.2` and the fixture's
  `v1.2.3`. The drift scenario carries `vnext` alone, since `v1.2` would be
  inert there for the same reason it is inert in the positive one, and a second
  inert tag reads as load-bearing to anyone who does not re-derive the sort.
- **File length.** `tests/release-test.sh` is now 845 lines; the 400-line
  question over this suite is a recorded open item and out of scope here.

## 6. State on exit

- `tests/release-test.sh` — the only file modified for the suite;
  `git status --porcelain=v1` shows it plus the two report files.
- `toolkit/release.sh` — untouched, `git diff --stat` empty. Every mutation was
  restored from its backup and the backups deleted.
- `bash -n tests/release-test.sh` — clean. `shellcheck tests/release-test.sh` —
  clean.
- `bash tests/release-test.sh` — **4 failure(s)**, all assertion failures in the
  slice's two scenarios; no other scenario fails.
- `plans/2026-09-15-first-release-version/reports/item-1-1-s3-red.md` — an
  "Amended by the test review" section added, so the RED report does not
  under-report the slice.
- Not committed, per the dispatch.

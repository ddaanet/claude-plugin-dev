# Item 1.1 slice 2 — test review

Reviewed: the single scenario slice 2 adds to `tests/release-test.sh`, "release:
non-semver v tags are not releases". Verdict: red for the right reason, and the
`v1.2` tag is load-bearing rather than decorative — proved by mutation probe,
not by reading. Three fixes applied: a weakened tag assertion replaced, a
fixture comment that the next two lines falsify, and no record of why either tag
is in the fixture. The scenario is still red after them.

## 1. Mechanical check

`bash tests/release-test.sh` re-run against `toolkit/release.sh` as it stands at
`HEAD`, before any edit of mine:

- **3 failures, all in this scenario, all assertion failures.** No setup error,
  no "command not found", no failure attributable to a function the
  implementation has not written yet.
- Every other scenario in the suite passed, including the three the runbook pins
  unmodified: "a first release publishes the manifest version verbatim", "tags
  with no marketplace entry is not a first release", and "a non-v tag nearer
  than the release tag does not read as the latest release".
- The failing path is the one the runbook names: `git tag --list 'v*'` has no
  version anchor, so `vnext` and `v1.2` make the slice-1 predicate read the
  plugin as released; `latest_tag` then sorts the unfiltered set by
  `-v:refname`, where `vnext` sorts first, and the run dies with
  `plugin.json version (0.1.0) does not match latest tag (vnext)`.

`shellcheck tests/release-test.sh` and `bash -n` are clean, before and after my
edits.

## 2. Mutation probe — does `v1.2` do any work?

The dispatch asks whether this scenario distinguishes the intended full-semver
filter from cheaper wrong ones, and whether `v1.2` is inert. Reading cannot
settle that, so I built the implementation in a scratch tree — `tests/` and
`toolkit/` copied to `$TMPDIR`, `semver_tags`/`release_tags` inserted and the
predicate at `release.sh:224` routed through them — and ran the suite there
under three filter regexes. Nothing in the repository was touched; the scratch
tree is deleted.

| filter regex | this scenario |
| --- | --- |
| `^v[0-9]+\.[0-9]+\.[0-9]+$` (intended) | passes, suite fully green |
| `^v[0-9]` | **fails** — `v1.2` survives, plugin reads as released |
| `^v[0-9.]+$` | **fails** — same, `v1.2` survives |
| `v[0-9]+\.[0-9]+\.[0-9]+` (unanchored) | passes |

So `v1.2` is not inert: it is the only thing separating the three-part anchor
from a `^v[0-9]`-shaped one, and a wrong implementation of that class is caught.
`vnext` covers the weaker case of a tag the `v*` glob matches and no version
filter should.

**Accepted bound, not fixed.** The unanchored row shows this scenario does not
pin either anchor. The left anchor is untestable here in any case: the local
listing is `git tag --list 'v*'`, whose glob already imposes it — it matters
only for `origin_release_tags`, where stripping `refs/tags/` can yield
`foo/v1.2.3`, and that is Item 1.2. The right anchor would need a suffixed tag
(`v1.2.3-rc1`) or a peeled `v1.2.3^{}` line, and the plan fixes one fixture tag
set across both suites — `vnext`, `v1.2`, `v1.2.3` — which neither is in.
Widening the set unilaterally would desynchronise `tests/hook-test.sh`, so this
stays a bound of the plan rather than a defect of the slice.

## 3. Fixes applied

**3.1 The tag assertion was the weakest available form.** It read

```sh
assert_eq "$(git -C "$plugin" rev-parse -q --verify 'refs/tags/v0.1.0^{commit}' >/dev/null && echo yes || echo no)" \
    "yes" "non-semver-tags tag created"
```

which asserts only that some ref by that name exists, and is very nearly implied
by the `Release v0.1.0 complete` assertion above it — two assertions buying one
fact. Replaced with the form the neighbouring first-release scenario uses,
pinning where the tag landed:

```sh
head_before="$(git -C "$plugin" rev-parse HEAD)"
…
assert_eq "$(git -C "$plugin" rev-parse -q --verify 'refs/tags/v0.1.0^{commit}')" \
    "$head_before" "non-semver-tags tags HEAD"
```

Also added `non-semver-tags manifest untouched` and
`non-semver-tags makes no commit`. These two pass in the red state — today's
code refuses in preflight, before writing anything — and that is correct: they
are not this slice's red assertions but the contract FR-1 states, which a green
implementation must satisfy and which a later slice could otherwise break
silently. The scenario's red rests on the exit code, the summary line and the
tag placement, all three of which fail today.

**3.2 A fixture comment falsified two lines later.** The `make_virgin` line
carried `# no v* tags, manifest seeded by an external scaffold`, copied from the
`:592` scenario, immediately followed by `git tag vnext` and `git tag v1.2`. It
now describes only what `make_virgin` itself establishes.

**3.3 Nothing recorded why either tag is present.** Section 2's finding is
exactly the kind that gets lost: a later reader sees two tags testing "not a
version" and deletes one as redundant, silently dropping the anchor coverage.
Added a comment above them naming what each one catches, including that the
weaker anchor makes the run refuse on manifest-versus-latest-tag.

## 4. Considered, not changed

- **No assertion that the run avoids the drift refusal**
  (`assert_not_contains "$out" "does not match latest tag"`). Implied by
  `rc == 0`; the file does not add negative assertions where the exit code
  already carries them.
- **No "tag pushed to origin", "gh release created" or marketplace assertion.**
  The full first-release contract is pinned by "a first release publishes the
  manifest version verbatim" forty lines above, against the same fixture minus
  the two tags. What is new here is that the tags change nothing, so the
  scenario asserts the outcome and leaves the publication steps to the scenario
  that owns them.
- **No assertion that `vnext` and `v1.2` survive the run.** No plausible
  implementation deletes tags; the assertion would guard nothing.
- **The scenario title matches what it asserts** — "non-semver v tags are not
  releases" is FR-2's predicate stated positively, and the assertions are that
  the first release proceeds.
- **Placement.** Between slice 1's last scenario and the unmodified `:634`
  guard, i.e. with the other detection scenarios. Correct, and it leaves
  `new_sandbox`/`make_virgin` state local to itself.
- **Forward compatibility.** After Item 1.2 lands, this fixture reaches the
  `origin_release_tags` probe with an origin carrying no tags at all
  (`make_virgin` deletes `v1.2.3` on both sides, and the two non-semver tags are
  never pushed), so it takes the initial-release branch and stays green. Item
  1.3's three diverged-push-route settings are unset in the fixture.
- **Slice 3's coverage was not pulled forward.** `latest_tag` is still reached
  by no assertion here — the first-release branch returns before it — which is
  correct for the slice boundary.

## 5. Report accuracy

`reports/item-1-1-s2-red.md` is accurate on every checkable claim: the three
failures, their assertion-failure character, the `vnext` sort explanation, the
untouched `toolkit/release.sh`, and the three protected scenarios staying green.
Its quoted scenario body and its "3 failure(s)" block predate the fixes in
section 3; the count is unchanged at 3, but the third failure is now
`non-semver-tags tags HEAD` rather than `non-semver-tags tag created`. Not
corrected in that file — a dated record is not revised.

## 6. State on exit

- `tests/release-test.sh` — the only modified file. Not committed.
- `toolkit/` untouched; `git status --porcelain=v1` shows
  `M tests/release-test.sh` and the two untracked report files, nothing else.
- `bash tests/release-test.sh` → **3 failure(s)**, all in this scenario, all
  assertion failures. Every other scenario green.
- `shellcheck tests/release-test.sh` clean.
- The scratch probe tree under `$TMPDIR` was removed.

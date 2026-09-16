# Item 1.1 slice 1 — test review

Reviewed: `tests/release-test.sh` (uncommitted), against the slice 1 spec and
`plans/2026-09-15-first-release-version/outline.md`. Verdict: the RED report's
mechanical claims hold; one gap fixed; tests remain red.

## 1. Mechanical verification

Re-ran `bash tests/release-test.sh` from the repo root myself rather than
trusting the report.

- 13 failures before my fix, matching the report's count exactly.
- Every failure is an assertion failure reported through `fail()`. None is a
  setup error, a missing-function error, or a non-zero exit from the harness.
  The suite ran to its own summary line each time.
- No test in the slice PASSED where it should have failed. The only assertions
  in the three scenarios that passed are the ones not expected to distinguish
  the implementations: `entry-agrees-no-tags exit code` (today's bump path also
  exits 0), and the four pre-existing assertions in the bump-refusal loop.
- Every other scenario stayed green, including the three the runbook protects.
  Confirmed those against `git show HEAD:tests/release-test.sh`: `:592` is "a
  first release publishes the manifest version verbatim", `:634` is "tags with
  no marketplace entry is not a first release", `:721` is "a non-v tag nearer
  than the release tag does not read as the latest release". All three are
  byte-identical to HEAD (they only moved in line number) and all three pass.
- `toolkit/release.sh` unmodified — `git diff --stat -- toolkit/` is empty.
- `shellcheck tests/release-test.sh` is clean.

## 2. Red for the right reason

Checked each test both ways: that today's code fails it for a behavioural
reason, and that the intended implementation can actually make it pass.

**Test 1 (inverted `:625`, no argument) — sound.** The fixture genuinely
establishes the state the slice describes: `make_virgin "1.2.3"` deletes the tag
locally and on origin, and stages nothing (the fixture manifest is already
`1.2.3`), so `HEAD` is the `init` commit and origin's `main` is at it. Today's
output shows `check-version: in sync (1.2.3)` followed by the whole ordinary
bump path — a behavioural difference, not a broken fixture.

I verified the assertions are reachable by the intended implementation rather
than over-constraining it. The two marketplace assertions were the risk:
`bump_marketplace` is still called on a first release, and if it committed a
no-op rewrite, "marketplace HEAD unmoved" could never go green. It cannot —
`toolkit/release.sh:408` short-circuits on `cmp -s` when the entry already holds
`$V`, so with the entry at `1.2.3` nothing is written, staged, committed or
pushed. The assertions are achievable.

`Release v1.2.3 complete` is load-bearing rather than incidental: the summary is
printed only after `push_branch`, `push_tag`, `create_github_release` and
`bump_marketplace` have all run under `set -e`, so it also pins that the tag
reached origin and the GitHub release was created. No separate assertion for
those is needed.

**Test 3 (bump-refusal loop, `commit that edit`) — sound.** The three failures
are isolated to the new assertion; the four older assertions in the same
iteration still pass, which rules out a setup problem. The remaining three
`0.1.0`-fixture assertions cover FR-3's "names the version it would publish".

**Test 2 (inverted `:625`, `patch`) — gap found and fixed.** The four assertions
the slice lists (exit 1, `never been released`, no `v*` tag, empty `$GH_LOG`)
all fail today, but as a set they would also pass a wrong implementation that
raises the refusal *after* `bump_commit_tag` and `push_branch` — the two
irreversible steps that precede tagging and the `gh` calls. FR-3 and the
outline's standing refusal contract ("the named hint, no local tag created,
origin `main` not advanced, `gh` not called, marketplace untouched") require the
refusal to sit in preflight, before any side effect.

Added four assertions, with a comment stating why:

- manifest still `1.2.3`
- `HEAD` unchanged from a `head_before` captured before the run
- origin's `refs/heads/main` still at that `head_before`
- `market_version` still `1.2.3`

All four fail today for the same behavioural reason as the rest of the scenario
(the ordinary bump path runs to completion), and all four are satisfied by a
preflight refusal.

## 3. Considered and deliberately not changed

- **No `assert_contains "$out" "1.2.3"` on test 2.** It would pass vacuously:
  `check-version.sh` runs before the refusal and prints
  `check-version: in sync (1.2.3)` into the captured output. FR-3's
  version-naming requirement is already covered by the `0.1.0` assertion in the
  bump-refusal loop, where the bumped alternative (`0.1.1`/`0.2.0`/ `1.0.0`) is
  distinguishable.
- **No "tag pushed to origin" / "gh release created" assertion on test 1.**
  Implied by the summary line, as argued above; adding them would be redundant.
- **`.` as a regex metacharacter in `assert_contains` needles** (`1.2.3`
  matching `1x2x3`). Present throughout the existing suite; matching the file's
  convention beats an inconsistent one-off escape.
- **Scenario titles match their assertions.** "a marketplace entry does not
  disqualify a first release" and "a marketplace entry does not exempt a first
  release from refusing a bump" both state what is asserted, and both state rule
  2 rather than its negation.
- **`make_virgin`'s comment** no longer mentions the conjunct and accurately
  describes the `new_sandbox "1.2.3"` pairing. A grep over the file found no
  other surviving reference to the two-part predicate.
- **Forward compatibility with later slices**, checked but not acted on: after
  Item 1.2 lands, both fixtures reach the `origin_release_tags` probe with an
  origin that has no tags, so they take the initial-release branch and stay
  green. Item 1.3's diverged-push-route settings are unset in the fixture.

## 4. Report accuracy

`reports/item-1-1-s1-red.md` is accurate on every checkable claim: the failure
count, the per-test failure lists, the untouched `toolkit/`, and the three
protected scenarios staying green. One imprecision, not corrected because a
dated record is not revised: it says "the other three assertions in the same
loop iteration" where there are four (it omits `names the remedy`). The report
predates my four added assertions, so its 13-failure count is now 17.

## 5. State on exit

- `tests/release-test.sh` is the only modified file; no commit made.
- `bash tests/release-test.sh` → **17 failure(s)**, all assertion failures in
  the three slice-1 scenarios. Every other scenario green.
- `shellcheck tests/release-test.sh` clean.
- `toolkit/` untouched.

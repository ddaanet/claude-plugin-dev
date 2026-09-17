# Phase 1 boundary review — release.sh

**Verdict: PASS with two fixes applied and three findings referred up.** The
four items compose correctly; no item's refusal is reached out of order by
another's path, and no two hints contradict each other about the same state. Two
fixes landed (a comment-vs-message overclaim in Decision 1's hint; a scenario
closing the resume-with-work push-route gap). Three findings are reported rather
than fixed, all outside the phase's diff.

**Fail-open family sweep: 5 fixed this phase; 10 sites remain in
`toolkit/release.sh`, of which 1 is a live latent defect, 3 are the recorded
`ls-remote | cut` captures, and 6 are benign by construction.** Details in
section 2.

`bash tests/release-test.sh` green, 57 scenarios. `just precommit` green.
`bash -n` and `shellcheck` clean on both files. Nothing committed.

---

## 1. Interactions between items

Checked by running, not by reading. Every claim below was measured against a
fixture.

**Ordering is sound.** `common_preflight` runs unconditionally before the
`release`/`resume` branch, and the push-route loop (Item 1.3) sits after the
clean-tree and branch checks and before every `MARKETPLACE_DIR` check including
`check_marketplace_writable`. That ordering is right: a diverged push route is
reported as itself rather than surfacing later as a marketplace-writability
error. Neither of the two checks it precedes has a side effect, so nothing is
stranded by losing the race.

**Item 1.3 is what makes Items 1.2 and 1.4 evidence, and it does reach them
first.** Measured across all three settings, in both modes. Item 1.3's refusal
fires before either origin probe runs, so `origin_release_tags` is never read
against a repository the release would not publish to. This is the dependency
Decision 1 rests on and it holds.

**`release_preflight` and `resume_preflight` do not disagree.** Both now read
origin, with deliberately opposite failure policies — release-mode dies on a
failed listing, resume-mode absorbs it — and the comments at `release.sh:345`
and `:508` each state the asymmetry and its reason. Run against the same
lost-tags fixture, release mode says "fetch, then run the same command again"
and resume mode says "fetch, then run `just resume-release`"; both are correct
for their own mode and neither is reachable from the other.

**Finding 1 (major, referred up): both of the phase's new hint branches
terminate in a pre-existing drift refusal whose two remedies are dead ends.**
Measured, twice:

- Release mode, lost tags over a *committed* hand-advance (manifest 1.3.0,
  origin `v1.2.3`) — Item 1.2's hint says `git fetch --tags`, then run the same
  command again. After the fetch the run reaches `release_preflight:474` and
  refuses with "revert it with
  `git checkout HEAD -- .claude-plugin/plugin.json`" — a **no-op**, because the
  hand-advance is committed. Its second remedy is "if v1.3.0 was in fact
  released and only the tag is missing here, `git fetch --tags` and re-run" —
  the fetch the operator has just performed on the previous hint's own
  instruction, and which the lost-tags guard had already established would not
  help (it named `v1.2.3` as origin's newest).
- Resume mode, same fixture — Item 1.4's branch 2 says `git fetch --tags`, then
  `just release <bump>`, and lands on the identical refusal.

The committed hand-advance is not a corner case: it is the fixture the phase's
own scenarios use at `tests/release-test.sh:908` and `:412`. The drift hint
(`release.sh:475-486`) is **outside the phase's diff** — `git diff` shows those
lines as context — and its text is asserted by two scenarios at `:1186-1188`.
Rewording it is a decision about a message this phase did not write, so it is
referred up rather than applied. Recommendation: the hint should branch on
whether the manifest differs from HEAD (`git diff --quiet HEAD -- "$manifest"`),
offering the revert only when there is something to revert, and dropping the
fetch sentence when a fetch has demonstrably already happened — or, cheaper,
Phase 3 records it in `docs/references/recovery.md` as a known dead end.

**No duplicated logic drifted.** The two origin reads share one function; the
two local reads share `release_tags`; the semver anchor exists once. The only
duplication is the deliberate one in `version-guard.sh` (Phase 2), unaffected
here.

**Finding 2 (minor, referred up): FR-6 names three keys; git has a fourth
redirect.** `url.<base>.pushInsteadOf` rewrites push URLs and is not consulted.
The refusal's own wording ("push route diverges from origin") reads as
exhaustive while the check is not. FR-6 and Decision 3 both enumerate exactly
three keys, so adding a fourth is a spec change, not a review fix. Worth one
comment line recording the bound, or a Decision 3 amendment.

## 2. The fail-open family, as a family

Family defined as: a command whose non-zero status is discarded, so failure is
indistinguishable from a benign empty-or-false answer. Swept the whole file,
including code this phase did not touch.

**Fixed this phase: 5** (the five the brief enumerates).

**Remaining: 10 sites, all pre-existing and all outside the phase's diff.**

Live latent defect — **1**:

- `release.sh:235`, `if jq -e … "$marketplace_json"`. Measured: jq exits **5**
  on a malformed file and **1** on a clean no-match, and the `if` reads both as
  "no entry", setting `marketplace_entry_exists=0`. In `release` mode
  `check-version.sh` catches the malformed file first. In
  **`--resume` mode it does not run**, so the run proceeds through
  `push_branch`, `push_tag` and `gh release create`, then dies inside
  `bump_marketplace`'s entry-creating jq with jq's own status and no `error:`
  line — after everything is public. Narrow trigger, bad landing. Fix would be
  `jq -e … || { [ "$?" -eq 1 ] || die …; }`.

The recorded `ls-remote | cut` captures — **3** (`:610`, `:638`, `:734`):

- Measured both ways: under `pipefail` a bare `v=$(git ls-remote … | cut -f1)`
  exits 128 and errexit kills the run; with `pipefail` off it yields `''` and
  status 0. So they **fail closed today**, and the risk is unchanged in kind.
  What the phase changed is the *inconsistency*: the file now carries a 14-line
  comment at `:298-311` arguing at length that this exact shape is unsafe and
  that `origin_release_tags` must capture-and-check instead — while three sites
  a few hundred lines down use the shape that comment rejects. A reader who
  trusts the comment will assume the file does not contain the pattern. The live
  risk is a bare `fatal: …` with no `error:` line as the last word, not a wrong
  answer. Out of scope to fix, as instructed.

Benign by construction — **6**:

- `:105` `git config --get submodule.gitlore-memory.path`. Measured: on a
  doubled key it prints the **last** value and exits **0** — the identical
  defect Item 1.3 fixed for the push keys, still present here. Also `|| mem=""`
  absorbs every status, not only 1, so an unparseable `.gitmodules` silently
  drops the memory exemption. Both fail closed (a wrong or missing exempt path
  makes the release *refuse*), so this is consistency, not correctness.
- `:127` process-substitution status unread in `report_dirty` — refusal path
  only; a failed `git diff` prints an empty path list under a header promising
  one. Message quality.
- `:535` `grep -qxF` error status reads as "no match" — advice-only path.
- `:654` `gh release view` failure reads as "no release" — `gh release create`
  then fails loudly.
- `:691` `cmp -s` error reads as "differ" — proceeds to write, fails loudly.
- `:709` `git diff --cached --quiet` error reads as "differ" — fails loudly.

In `tests/release-test.sh`: **45** assertions compare a substitution against the
empty string and would pass vacuously if the command failed. None is a live
family member — every one reads a file the same `new_sandbox` call just created
(`$GH_LOG`, the fixture manifest) or runs `git tag --list`, which does not fail
on a working fixture; a fixture broken enough to make them fire would fail the
surrounding `assert_contains` loudly first. The one new assertion this review
added deliberately avoids the shape (see section 4).

## 3. Requirements coverage

Verified against the landed code, not the reports.

- **FR-1** — met. `release_preflight:454` sets `V="$manifest_version"` and
  `bump_commit_tag:576` tags without committing. Pinned at `:742` and `:777`.
- **FR-2** — met *as a decision*, with a caveat the runbook's one-line statement
  hides. The predicate at `:442` is purely local (`release_tag_list` empty) and
  the marketplace entry genuinely plays no part. But `:442` is only *reachable*
  once the Item 1.2 probe has cleared origin, so the effective rule is "no
  semver tag locally **and** none on origin **and** origin was readable". That
  is FR-4's contribution and is correct; FR-2 as literally worded ("exactly when
  no tag matches …") describes neither the lost-tags refusal nor the
  unreachable-origin refusal. Phase 3 should state the conjunction, not the bare
  predicate. The header comment at `:11-16` has the same gap — it says "no tag
  matching `^v…$` exists yet" without saying which tag set.
- **FR-3** — met, `:444-452`, and the `commit that edit` clause is asserted at
  `:770`. Its vocabulary now matches Decision 1's hint ("set .version in … and
  commit that edit"), which is the one place the phase deliberately unified
  wording across items.
- **FR-4** — met and well covered: 7 scenarios, including both failure modes of
  the listing and the probe-before-drift ordering.
- **FR-5** — met, and **better covered than the runbook specifies**: the
  runbook's four slices pin the four branches, and two code-review additions
  (`:477`, `:498`) pin the ladder's *order* and the first branch's
  *membership-not-newest* semantics. Both are load-bearing — their comments
  record that a permutation and a newest-only implementation each passed the
  four-scenario suite.
- **FR-6** — met for the three named keys, in both modes, before any side effect
  (now measured rather than inferred; see section 4). Thinner than the refusal's
  wording implies, per Finding 2.
- **FR-8** — met, `:389-430`, pinned at `:812`. One fix applied to it, below.

No requirement is asserted-but-absent.

## 4. The suite as an artifact

**No duplicate scenarios.** Every one of the eight resume-ladder scenarios and
seven lost-tags scenarios carries a comment naming the branch it selects and why
the neighbouring scenarios do not cover it; I checked those claims against the
branch conditions and they hold. The closest pair — `:876` and `:892`, both
lost-tag refusals — differ in what they discriminate (`:876` pins the probe
ahead of the bump refusal via `assert_not_contains "never been released"`;
`:892` exercises the no-argument path, where unchanged code tagged and pushed
before dying). Keep both.

**No vacuous assertions found** beyond the 45 empty-string comparisons
characterised in section 2, none of which is live.

**One real gap, now closed (fix applied).** The recorded open item was right:
the resume-mode push-route scenario at `:1057` used a *healthy* fixture where
resume has nothing left to do, so `push_branch` and `push_tag` would report
"already pushed" even with the check deleted, and `$GH_LOG` empty pinned
"refused before gh" rather than "refused before any side effect". Added
`tests/release-test.sh:1104` — "resume: a diverged push route is refused before
a resume that HAS work to do" — which stops a release after the local commit and
tag (refusing pre-push hook), then sets each of the three redirects and resumes,
asserting the **redirect target's ref list is empty**.

Verified red by mutation: with the push-route loop deleted from
`toolkit/release.sh`, the resume completes with `rc=0` and the target repo gains
`refs/heads/main` (all three settings) plus `refs/tags/v1.2.4` under `pushurl`.
Restored and confirmed by `git diff --stat`.

The new assertion deliberately captures into a variable
(`push_target_refs="$(git -C "$other" for-each-ref …)"`) rather than
substituting inside `assert_eq`, so the suite's own `set -euo pipefail` catches
a failed `for-each-ref` instead of letting it pass as `""` — the family
discipline applied to the test that was added to enforce it.

## 5. Lifecycle audit

Every refusal the phase added was run, and the resulting state inspected:

- Item 1.3's refusal, both modes, all three settings, with and without pending
  work: no local tag created or moved, no ref in the redirect target, `gh`
  uncalled, marketplace unmoved, and the pre-existing local tag object
  unchanged.
- Item 1.2's refusals (lost tags, unreachable origin, absent origin): no tag,
  origin `main` not advanced, `gh` uncalled, marketplace untouched — all
  asserted by the suite and re-confirmed by hand for the unreachable case.
- Item 1.4's refusals: no side effect exists to protect; `resume_preflight`
  refuses before `push_branch`.
- Decision 1's refusal: manifest, HEAD, origin `main`, marketplace and tag list
  all unchanged (`:838-849`).

No stray tag, no half-written manifest, no `MERGE_HEAD`, no lock file on any
path the phase added. `check_marketplace_writable` leaves no probe file behind:
on the failing path `mktemp` created nothing.

One pre-existing residual, outside the diff: `bump_commit_tag:587` and
`bump_marketplace:665` each `mktemp` before a `jq` that errexit can kill,
leaving a temp file in `$TMPDIR`. Harmless, unchanged by this phase.

## 6. Comment and message consistency

**One real mismatch found and fixed.** Decision 1's hint claimed more than the
probe established. The comment above it said the message "must not deny" a
plugin released under some other tag scheme; the message then said "this plugin
has no **release tag at all**, here or on origin" — which denies exactly that.
Fixed at `toolkit/release.sh:419-431`: the message now says "this plugin has no
**vX.Y.Z tag**, here or on origin", and the comment is restated to say the
message names the shape it actually looked for. The suite asserts line 1 of the
hint (`no release is recorded at`), not line 2, so nothing was weakened.

**Everything else is consistent.** Checked the phase's vocabulary end to end:
both listing failures use the same "could not … — nothing was done" shape; both
origin-tag hints use "origin … release tags" and `git fetch --tags`; the two
hints advising a manifest edit both say "set .version in … and commit that
edit". No hint contradicts another about the same state (Finding 1 is a chain
ending in stale advice, not two hints disagreeing).

**Measured claims in the new comments, re-verified independently:**

- `common_preflight:188-190` — `$?` in the `elif` condition is the failed `if`
  condition's status: confirmed, exit 2 and 128 reach the `elif` body, exit 1
  does not.
- `common_preflight:176` — `--get-all` exits 1 on an unset key: confirmed.
- `origin_release_tags:305-311` — captured refuses either way, piped refuses
  only under `pipefail`: confirmed both ways.
- `common_preflight:227-229` — the `&&` list is not the function's last command:
  confirmed.

Two cosmetic inconsistencies left alone, both pre-existing: `:365` capitalises
"Run" mid-hint where `:140` lowercases after a full stop, and `:448` starts a
sentence lowercase. Neither is phase-introduced; touching them is churn.

## 7. Recorded open items

**The `toolkit/release.sh` split — recommendation: do not split.** Measured: 791
total lines, **380 code, 381 comment, 30 blank**. The executable artifact is
already under the 400-line cap; the overage is entirely the argument for why
each line is shaped as it is, which is this repo's house style and the thing
CLAUDE.md explicitly forbids shaving to meet the cap. Against that, a split
costs a **new shipped path** — `tests/dist-tree-test.sh`'s allowlist, the
CLAUDE.md Layout list, and every consumer's vendored tree. The toolkit's shipped
surface is its API; widening it for readability is the wrong trade.

The measured seam is also the wrong one. The tag-listing trio
(`semver_tags`/`release_tags`/`origin_release_tags`, `:261-321`, 61 lines) is
the most self-contained part of the file and extracting it removes 8% of the
lines while making `release.sh` unable to run without a sibling. Growth is in
the three preflights — `common_preflight` 124, `release_preflight` 176,
`resume_preflight` 73 — and those share nine globals (`mode`, `branch`,
`manifest`, `plugin_name`, `marketplace_json`, `V`, `tag`, `first_release`,
`marketplace_entry_exists`). Splitting there needs either `source`, which the
file's top-level flow forbids, or a parameter-passing refactor far larger than
the cap justifies.

If relief is wanted later, the cheaper lever is moving the two longest arguments
(the `pipefail` essay at `:298-311`, the `--get-all` essay at `:168-177`) into
`docs/references/release-flow.md` behind one-line pointers — about 60 lines, one
shipped file, at the cost of the adjacency those comments exist for. My advice
is to record the 380/381 measurement in the design node so the next review does
not re-open this a fifth time.

**The marketplace-writability false refusal — still present; leave the code,
record it in docs.** Reproduced: a first release whose entry already agrees,
with `MARKETPLACE_DIR/.claude-plugin` at mode 555, refuses with advice about
replacing `marketplace.json` — and the same state with the directory writable
completes reporting "marketplace: already at 1.2.3" with the marketplace `HEAD`
unmoved, confirming no write happens. It fails closed and recovery is a `chmod`
or `/add-dir`, so the harm is a message that describes a write that would not
occur. The code and its comment (`:216-226`) already agree that this is a
deliberate bound — which of the two cases applies is only settled in
`release_preflight`, after `common_preflight` runs. Moving the check later to
fix it would cost release mode its fail-fast, which is the check's whole point.
The gap is that the bound is nowhere in `docs/`. Phase 3 item.

**Resume "before any side effect" coverage — gap was real, now closed.** See
section 4. Fix applied and verified red by mutation.

**The three `ls-remote | cut` captures — current risk.** Unchanged in kind: they
fail closed via `pipefail`, measured. The phase raises the *consistency* cost
rather than the risk: the file now argues at length against the shape it still
uses in three places, and more code depends on origin reads than before, so a
future edit that touches the `set` line or reaches for one of these as a
template has a wider blast radius. Not urgent; worth a follow-up item that
converts all three to the captured form the phase established.

## State on exit

Modified, uncommitted:

- `/Users/david/code/claude-plugin-dev/toolkit/release.sh` (+8 −5) — Decision
  1's hint and its comment, section 6.
- `/Users/david/code/claude-plugin-dev/tests/release-test.sh` (+51) — one new
  scenario, section 4.

**Nothing was committed.** `git status --porcelain` shows exactly those two
modified files. The throwaway SUT mutation used for the red proof was restored
and the restore confirmed by `git diff --stat`. Scratch trees under
`/tmp/claude-1000` were deleted; nothing was left in the repo root.

`bash tests/release-test.sh` green, 57 scenarios (the brief said 52; the file
carried 56 before this review and 57 after — the 52 appears to be a stale count,
not a missing scenario). `just precommit` green. `bash -n` and `shellcheck`
clean on both files.

Phase 2 (`toolkit/version-guard.sh`) and Phase 3 (`docs/`) were not touched, no
release was run, and the pre-existing `ls-remote | cut` captures were left
alone.

# Runbook review — deliverable-review fix pass (fix-all)

Reviewed 2026-09-19 against the tree at `bc0b962`, which still carries every
production file at `8d3fbf5`. All findings below were verified by reading the
cited code, not by trusting the outline or the proof verdicts.
**Eleven fixes applied**, listed with their evidence; nothing was left as a
recommendation.

Gate after the edits: `just format-docs` clean and re-run,
`bash tests/docs-test.sh` green, nested-bullet field shape intact (10
`Requirements:` bullets in the hub, 8 in the node = the 18 items). `runbook.md`
359 → 395 lines, `runbook-test-suites.md` 233 → 253. Both under the 400 cap; the
hub has five lines of headroom, which is the one thing worth watching if the
proof gate adds anything.

## The three questions asked hardest

**Requirements coverage — complete and correct.** I re-derived the 15 Minors
from `reports/deliverable-review.md` independently and got exactly the runbook's
`N1`–`N15` in the same order. All 6 Majors, all 15 Minors and `BD` map to an
item; all 21 outline items (`A1`–`A3`, `B1`–`B7`, `C1`–`C11`) are claimed by an
item, plus Item 2.1 for `N7`. No requirement is double-owned in a way that
splits responsibility: `N4`/`N6` share Item 3.2 and `M6`/`N15` share Item 4.1,
and both items state their internal ordering. No fix needed.

**Ordering — one constraint held only by transitivity, now explicit; one
mislabelled.** All six of `outline.md`'s "Dependencies and ordering" rules
survive. Rule 6 (`B7` last on `version-guard-test.sh`) is Item 3.4's
`Depends on: Items 3.2 and 3.3 — runs last on this file`, correct. Rule 2 (`A3`
before the `:296-297` comment update) is inside Item 1.3 as an `Also update:`,
correct — I verified the comment at `tests/self-release-test.sh:296-297` does
explain the squatting scenario in terms of `describe --match 'v*'`. Of the three
line-level overlaps, `B2 ↔ B3` and `A3 ↔ B3` were correctly on Item 2.4;
`B5 ↔ C4` was not stated anywhere and was reachable only through 3.4. Fixed.
Separately Item 2.3's `Depends on: Item 2.2` was labelled "line-level overlap"
and carried the *2.3 ↔ 2.4* explanation — 2.2's scenario is at `:210-222` and
2.3's is at `:267-271`, so that pair is plain serialization. Fixed.

**Assertion quality in Phase 1 — two slices were not falsifiable as written.**
Item 1.3 slice 1 asserted "the drift guard compares against `v0.1.0`", which
names no observable. Item 1.3 slice 2's stated present-day behaviour was wrong
for the fixture it describes. Both fixed; details below. Items 1.1 and 1.2's
four slices each name a test and its assertions and are sound as written, bar
the `release_tags` return-shape correction that changes slice 1's needle.

## Fixes applied

### 1. Item 1.1 prescribed `|| die` where only `|| return 1` is safe (major)

The runbook said "assign … to a local, `|| die` on its status". `release_tags`
has exactly two call sites, both inside a command substitution, and both already
handle a non-zero status:

- `toolkit/release.sh`, `release_preflight`'s opening:
  `release_tag_list=$(release_tags) || die "could not list this plugin's release tags — nothing was done"`.
  A `die` inside the callee makes that message dead code and emits two `error:`
  lines.
- `toolkit/release.sh`, `resume_preflight`'s hint ladder:
  `if release_tag_list=$(release_tags) && [ -z "$release_tag_list" ]`. The
  comment directly above it states that a *failed* listing must fall through to
  the last branch, "whose advice is safe either way". `die` is
  `printf … >&2; exit 1`, so inside `$( )` it ends the subshell only — the
  script does not abort, it prints `error: …` into the middle of a deliberately
  non-fatal hint ladder.

`origin_release_tags`, the shape the outline told this item to copy, uses
`|| return 1`. The runbook's `die` was a departure from its own stated model.
Changed to `|| return 1`, with the reason inline, and the `Interfaces:` line
rewritten from "`die`s on a failed `git tag --list`" to "returns 1 … both call
sites keep the handling they already have".

Consequence for slice 1: with `return`, the message the test sees is
`release_preflight`'s existing `die`, and a `git` stub prints nothing of its
own. The needle is now stated as `could not list this plugin's release tags`
rather than the unlocatable "names the `git tag --list` failure".

### 2. Item 1.2's in-repo precedent does not exist as described (minor)

The runbook said "`toolkit/version-guard.sh`'s own `grep -qxF` herestring is the
in-repo precedent". There is no `grep -qxF` herestring in the repo: the only two
`grep -qxF` sites are `toolkit/install.sh:105` and the defect site itself,
`toolkit/release.sh:577`, and both are non-herestring. The actual herestring
precedent is `toolkit/version-guard.sh`'s tag filter,
`grep -E '…' <<<"$listing"`. Reworded to cite that, and to say the `-qxF` flags
are this site's own.

### 3–4. Item 1.3's two slices (major for slice 1, moderate for slice 2)

Slice 1 asserted the run "does not print `does not match latest tag (vnext)` and
that the drift guard compares against `v0.1.0`" — the second half names no
observable. Traced the fixture: `new_sandbox` leaves `v0.1.0` on the only commit
with `toolkit/VERSION` at `0.1.0`, `v0.1.0` and `dist-v0.1.0` pushed and the
GitHub release stubbed in, so `require_prior_release_published` is satisfied and
a passing drift guard lets the release complete. The slice now says to add one
ordinary commit and tag *it* `vnext`, and asserts `rc` 0,
`assert_tag v0.2.0 local`, and
`assert_not_contains "$out" "does not match latest tag"`.

Slice 2 claimed "Today `latest_tag` comes back empty and the drift guard is
skipped entirely". Not true of the fixture it describes: it keeps `v0.1.0`,
which *is* reachable from `HEAD`, so `describe` returns it, it matches
`toolkit/VERSION`, and the guard passes silently — the off-ancestry `v0.9.0` is
invisible rather than merely mis-ranked. (The review's "comes back empty"
describes a repo with no reachable tag at all.) The slice now states the real
present-day behaviour and pins the assertion to `rc` 1 plus
`does not match latest tag (v0.9.0)`. `v0.1.0` must stay in the fixture, since
`require_prior_release_published` runs downstream of the guard.

### 5. "Eight items across four test suites" (trivial)

Three: `self-release-test.sh` (Phase 2), `release-test.sh` (3.1),
`version-guard-test.sh` (3.2–3.4). Fixed.

### 6. Item 3.2 left an unresolved implementation choice (moderate)

`N4` said "Re-invoke the hook for that assertion, **or** add the note" — the
outline's fork, carried into the runbook unresolved. The runbook now takes
re-invoke: a note only discloses the hazard while a fresh run removes it, and
the cost is one hook invocation. Flagged here so it can be overturned at the
proof gate; the note-only option is the weaker one, not a wrong one.

### 7. Item 3.2 falsifies a comment it does not update (moderate)

`tests/version-guard-test.sh`'s no-tags block carries "Asserted over the no-tags
reason alone: the steady-state message names the recipe legitimately". Item
3.2's `N6` half adds `assert_not_contains "$reason" "just release"` to the
`vnext` block, which makes that sentence false. Per `commit-bundling` the
comment rides with the change; added as an `Also update:`.

I verified the two new `vnext` assertions do pass against unchanged code: the
initial-release deny reason contains the no-bypass sentence, names neither
`settings.json` nor `version-guard`, and contains no `just release` — so the
item is correctly `general` with a mutation gate rather than `tdd`.

### 8. Item 3.4's call-site count is off by two (moderate)

The runbook (and the outline, and the proof verdict) say "20 call sites — nine
`assert_contains` and eleven `assert_not_contains`". Counted:
`tests/version-guard-test.sh` has **8** `assert_contains` and **10**
`assert_not_contains` call sites — 18 — plus the two helper *definitions* at
`:36` and `:44`, which is where 20 comes from. Three of the 18 are inside
`assert_no_escape_hatch`'s body, which is easy to miss when converting. The
runbook now carries 18/8/10 and says explicitly that the outline is a frozen
dated artifact and is not being corrected there.

### 9. Item 3.4 checked one axis of the glob→BRE change, not two (major)

The runbook's re-read instruction covers BRE-live characters only. The glob form
`[[ "$1" != *"$2"* ]]` also matches **across newlines**; `grep` matches within a
line. Both haystacks here are multi-line deny reasons, so this is live. It also
inverts the runbook's own risk asymmetry: under BRE widening
`assert_not_contains` gets stricter and fails loudly, but under the newline
change a needle spanning a line break makes `assert_not_contains` a
*silent false pass*. No current needle spans a newline —
`assert_no_escape_hatch`'s long needle stops at "…alter version state by",
exactly the deny reason's line break, which reads as deliberate — but a reader
following the old instruction would not have checked. The item now names both
axes and corrects the asymmetry paragraph.

### 10. Item 4.1 rewrites an asserted surface without saying so (moderate)

`M6` edits the file header, which nothing asserts. `N15` edits the steady-state
deny reason, which `tests/version-guard-test.sh` reads through
`assert_contains "$reason" "last released version"` and `assert_no_escape_hatch`
(no-bypass sentence present; no `settings.json`, no `version-guard`). By Phase 4
those call sites are in Item 3.4's `grep` form and the `vnext` block carries
3.2's additions. Added as a constraint on the item rather than leaving it to
`precommit` to discover. I confirmed `N15`'s narrowness holds: no assertion
requires `just release` to be *present* in the steady-state reason, and
`assert_not_contains "$reason" "just release"` is scoped to the no-tags reason —
so the rewrite is free as long as those needles survive.

### 11. The hub's closing open decision had no owner (moderate)

"An open decision the pass has not taken, and which no item here resolves:
whether Item 4.6's citation convention also belongs as a bullet in `CLAUDE.md`'s
Conventions section." As written, an executor reaching the end of the runbook
has a live question and no instruction. Rewritten to state the executor default
(no — it lands in Item 4.7's dated entry and nowhere else) and to route the
question to the proof gate, the way Item 2.1 is already routed. The decision
itself is left to my human partner; only the executor's ambiguity is removed.

## The two deliberate departures — both endorsed, neither reverted

**Phases 2 and 3 typed `general`, not `tdd`.** Correct, and I checked it item by
item rather than accepting the general argument. Every one of the eight
strengthens a fixture whose new assertions pass against the current tree: 2.1's
untracked check (nothing is left untracked today), 2.2's `git show`/`ls-tree`
(the tag and `HEAD` coincide in the scenario that builds the tag), 2.3's
exemption fixtures, 2.4's `rc`/`$GH_LOG`/tag properties, 3.1's four properties,
3.2's two `vnext` assertions (verified green above), 3.3's stub log, and 3.4's
pure harness conversion. A `tdd` RED step has nothing to fail on in any of them,
and each carries a mutation gate naming the edit, the assertion and the revert.
Keeping the outline's `tdd` typing would have produced eight dispatches
manufacturing a fake red.

**Item 2.1 for `N7`.** The finding is real — `tests/self-release-test.sh:149` is
`git -C "$repo" diff --quiet HEAD || fail "happy: tree left dirty"`,
tracked-only — and it is genuinely unclaimed by any outline item. Carrying it
flagged, with the drop routed to the proof gate, is the right call; dropping it
silently would have lost a Minor the review verified.

## Verified and left alone

These were checked against code and are correct as the runbook states them, so
they are recorded rather than changed:

- Item 2.4's "ten, not nine": the `=== preflight refusals ===` block holds
  exactly nine refusals (the `.claude` scenario inside it is an *allow*, rc 0,
  which is why 2.3 owns it separately), and `=== resume refusals ===` supplies
  the tenth. The `$GH_LOG`-truncation warning about the pair sharing one sandbox
  is right: the second run in that sandbox succeeds and does call `gh`.
- Item 3.1's targets: `tests/release-test.sh:935-947` and `:949-964` are the
  origin-sort and probe-before-drift scenarios, and `hand-advanced-lost-tag`
  three lines above does apply all four properties. The set-comparison phrasing
  is necessary — scenario 1's fixture loses all local tags and scenario 2's
  origin already holds `v1.2.4`.
- Item 3.3's mutation site: `toolkit/version-guard.sh:80` is
  `[[ -z "$proposed" || "$proposed" == "$current" ]] && exit 0`, and the listing
  block does absorb every outcome into `listing_failed`/`grep_status` with
  stderr to `/dev/null` — so the proof verdict's conclusion that a bare
  `assert_allow` cannot pin the ordering is correct, and the recording stub is
  required.
- Item 4.6's four citation sites, all confirmed: `toolkit/release.sh:254` cites
  `:780-785` while the mode dispatch is at `:838-843`; `version-guard-test.sh`'s
  `:340` and `:341`; and `tests/release-test.sh:1248`'s accurate
  `release.sh:138`.
- Item 1.1's harness:
  `=== the origin probes fail closed with pipefail stripped ===` is at the end
  of `tests/release-test.sh` and does `sed`-strip the `set -o pipefail` line, so
  "extend it with a second scenario" is the right shape.
- Item 4.5's hazard note: `CLAUDE.md:73-76` is the ragged bullet and holds no
  `` `toolkit/...` `` token, so `tests/doc-sync-test.sh` does pass trivially on
  it — the runbook is right that the gate does not cover 4.4 or 4.5.
- "All eight suites" in the Gate section: `tests/` holds exactly eight `*.sh`.

## One observation, deliberately not acted on

The three suites this pass converges on implement `assert_contains` as
`printf '%s' "$1" | grep -q -- "$2"` — a `printf` piped into an early-exiting
`grep -q`, which is structurally the same EPIPE hazard Item 1.2 removes from
`toolkit/release.sh:577`. It is inert here (haystacks are a few hundred bytes,
and the suites do not all set `pipefail`), and converging *toward* that form is
my human partner's decision taken at the proof gate. Recording it so a later
pass does not read the convergence as an endorsement of the pipe.

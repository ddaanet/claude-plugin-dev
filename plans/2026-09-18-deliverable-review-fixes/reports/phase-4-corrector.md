# Review: Phase 4 (prose) — boundary checkpoint

**Scope**: Items 4.1–4.5 and 4.7 of
`plans/2026-09-18-deliverable-review-fixes/runbook.md`, commits `00e3f17`,
`745e9b1`, `2379180`, `8c60f7d`, `a551463`, `a9484ef` — diff `1df5ffd..HEAD`.
**Date**: 2026-09-20 **Mode**: review + fix

## Summary

Six prose items across eight files. Every requirement the phase carries (M5, M6,
N9–N15, BD) is satisfied, and every factual claim the new prose makes was
checked against `toolkit/release.sh` and `toolkit/version-guard.sh` rather than
against the runbook's description of them — all hold. Three defects found, all
introduced by this phase's own edits and all in prose: one dangling ordinal left
by the N10 trim, one internal contradiction inside Item 4.3's new `recovery.md`
paragraph, one ungrammatical clause in Item 4.2's edit. All three fixed.

**Overall Assessment**: Ready

## Verification performed

- `bash tests/version-guard-test.sh` — 16 scenarios, all pass. Item 4.1's deny
  edit keeps `assert_contains "last released version"` and
  `assert_no_escape_hatch` satisfied on the steady-state branch, and
  `assert_not_contains "just release"` still holds on the no-tags branch (Item
  4.1 did not touch that branch).
- `bash tests/doc-sync-test.sh` — output read, not just the status:
  `doc sync ok (5 shared command blocks, Layout matches toolkit/)`. Item 4.5's
  re-wrap split no backticked `toolkit/...` token; the target bullet holds none,
  as the runbook's Gate section predicted.
- `just precommit` — green after the fixes, including `format-docs`, which
  reflowed the three edited paragraphs.
- `wc -l docs/changelog/2026-09-20-deliverable-review-fixes.md` → **79**, well
  under the 400-line cap. `docs/design.md` 241, `recovery.md` 370,
  `version-guard.md` 174, `toolkit/README.md` 202, `CLAUDE.md` 206.

### Claims checked against source, not against the prose

| Claim | Source | Verdict |
|---|---|---|
| Probe keys on an *entirely* empty local list | `release_preflight`, `if [ -z "$release_tag_list" ]` | true |
| Partial loss: `latest_tag` read from a stale local newest, drift check compares against it | `latest_tag=$(printf … sed -n '1s/^v//p')` | true |
| Refusal advises setting the manifest *back* to the stale tag and committing | `set .version in %s back to %s, commit that` | true |
| That refusal's own "a fetch can never have anything left to fetch" reasoning does not hold there | the comment above the drift refusal | true |
| Manifest matching the stale tag: only the marketplace check stands in the way, and it reads the state as a partial release | `check-version.sh` call precedes the drift check; `verifiably_unpublished=0` so the hint is the `just resume-release` one | true |
| Hook lists local tags only; recipe falls through to `origin_release_tags` on an empty local list | `version-guard.sh`'s `git -C "$project" tag --list`; `release_preflight`'s `origin_release_tags` branch | true |
| Hub's trimmed arguments live in the nodes | `version-guard.md` (non-blocking-exit mechanism); `recovery.md` (three push keys, `pushInsteadOf` as the fourth) | true |
| "as the fourth push route below is" — it is below | `recovery.md`, "The push route has to agree with the probe" follows the edited section | true |
| README's "Conventions below" spell out the first-release exception and the hook's refusal of an agent's edit there | `toolkit/README.md` Conventions, the first-release bullet | true |
| Comment figures: `release.sh` 871 lines / 451 comment-only (52%); `version-guard.sh` 187 / 86 (46%) | `wc -l` and `tail -n +2 … grep -c '^[[:space:]]*#'` | exact |
| Citation gate scope is `git ls-files -z` minus `plans/` and `docs/changelog/`; three forbidden forms `.sh`, `.just`, `justfile`; `.md` target never flagged | `tests/citation-test.sh` header and `$citation_pattern` | true |
| `tests/version-guard-test.sh` cites the executed outline by line number and is meant to stay | `tests/version-guard-test.sh`, `see outline.md:118-121` | true |
| "Four of the five citations pointed at different code than when they were written" | reconstructed: `release-test.sh:8-13` was **accurate** at its introducing commit `df2c4c0` (those lines are exactly the leaked-env header block); the other four are stale per `phase-1-corrector.md` and `item-3-5.md` | true — and matches the runbook's own "1 → 4 stale of 5" |
| BD: `outline.md:262` says the no-tag refusal has three hints; code/runbook/`recovery.md` say four | `plans/2026-09-15-first-release-version/outline.md:262`; `recovery.md` "Four cases" | true |

Note for the record: `item-3-5.md`'s section heading calls the
`release-test.sh:8-13` citation "stale", which its own opening line
("stale/accurate") contradicts. The changelog entry's 4-of-5 is the correct
number; the report heading is the loose one. No action — `plans/` is frozen.

## Issues Found

### Critical Issues

None.

### Major Issues

None.

### Minor Issues

1. **`docs/design.md` — the N10 trim left a dangling ordinal**
   - Location: `docs/design.md`, "A push redirected away from origin is refused"
     bullet under "Recovery and the pre-flight state checks"
   - Problem: the trim removed the enumeration of `remote.origin.pushurl`,
     `branch.<name>.pushRemote` and `remote.pushDefault`, but the replacement
     sentence still said "which **fourth** one is a stated bound instead". With
     the first three gone from the hub, a reader of the hub alone meets a fourth
     of nothing. The bullet also opened "**… is refused** — refused when the
     config key is set at all", repeating the verb across the em dash.
   - Fix: drop the ordinal to "which further one", and drop the repeated
     "refused".
   - **Status**: FIXED

2. **`docs/references/recovery.md` — the new paragraph contradicts its own
   section eight lines above**
   - Location: `docs/references/recovery.md`, the second new paragraph of "Why
     the lost-tags probe runs before the drift check"
   - Problem: the cost of closing the bound was stated as "a listing whose
     failure **has to be** absorbed". The same section states, just above, that
     a failed origin listing "refuses outright here" — and `release_preflight`
     does exactly that
     (`die "could not verify this plugin's release history on origin"`). The
     claim is not false as an argument, but it skips the step that makes it
     true: absorbing is forced only because refusing *on every release* would
     put every release behind a working network, whereas refusing on the rare
     empty-local path is cheap. As written, a reader hits an apparent
     contradiction with no bridge.
   - Suggestion: name the step.
   - **Status**: FIXED — now reads "a listing whose failure could not refuse the
     way the empty-list probe's does — that would put every release behind a
     working network — so its status would have to be absorbed instead."

3. **`docs/references/version-guard.md` — ungrammatical clause in the M5 edit**
   - Location: `docs/references/version-guard.md`, the predicate sentence in
     "The deny message branches on whether the plugin has ever released"
   - Problem: "read here against the local clone, with the bound that carries
     noted below" — "the bound that carries" has no object, and two past
     participles stack. The sentence is the one a reader arrives at from the
     hub's parity conclusion, so it is the worst place for a parse failure.
   - Fix: "read here against the local clone only, a bound stated below."
   - **Status**: FIXED

## Fixes Applied

- `docs/design.md`, push-route bullet — "refused — refused when" → "— when";
  "which fourth one" → "which further one". The hub no longer references an
  enumeration it dropped.
- `docs/references/recovery.md`, partial-tag-loss closing paragraph — the
  absorb-vs-refuse asymmetry stated rather than assumed, so the paragraph stops
  contradicting the section it sits in.
- `docs/references/version-guard.md`, predicate sentence — clause rewritten to
  parse.

`just precommit` re-run after all three: green, all nine suites plus
`_import-check`, the 400-line cap, doc-sync, `whitespace` and `format-docs`.
`bash tests/version-guard-test.sh` was re-run separately as the item's own
constraint requires; `toolkit/version-guard.sh` was not among the fixed files,
so its deny wording is unchanged from the committed state.

## Requirements Validation

| Requirement | Status | Evidence |
|---|---|---|
| M6 — header restated for both release cases | Satisfied | `toolkit/version-guard.sh` header now says a first release's version is "the maintainer's own committed hand edit -- the hook refuses there too, because it governs agent edits and not the maintainer's". The false clause is gone; the header agrees with the deny branch, `release_preflight`'s first-release branch and `toolkit/README.md`. |
| N15 — conditional framing dropped, identifier kept | Satisfied | `If the goal is to ship a release, invoke the recipe instead` → `The release recipe owns this version -- invoke it instead of editing this file`. No `if … then`, no escape hatch. `just release {patch\|minor\|major}` retained earlier in the steady-state reason; `assert_not_contains "just release"` on the no-tags branch unaffected. M6 landed before N15 (`00e3f17` header, same commit ordering as the runbook requires). |
| M5 — parity claim recorded as a bound | Satisfied | `version-guard.md` predicate sentence no longer concludes the two cannot disagree; the new "A second bound is accepted on the same terms" paragraph states the disagreement, why local-only is right for a `PreToolUse` hook, and that it selects wording and never whether the refusal happens. |
| N10 — hub trimmed to conclusions | Satisfied | Non-blocking-exit mechanism removed from the deny bullet (lives at `version-guard.md` "The listing can never turn a deny into an allow"); three push keys and `pushInsteadOf` removed from the push bullet (live at `recovery.md` "The push route has to agree with the probe"). |
| N11 — partial tag loss in both files | Satisfied | `design.md` lost-tags bullet, final sentence; `recovery.md`, two new paragraphs. |
| N14 — proportion in the hub, figures in the entry | Satisfied | `design.md` Limitations: "Roughly half of `release.sh` is comment-only" — no figures. Measured 52% / 46% appear only in the dated entry. |
| N12 — README names the `vX.Y.Z` tag | Satisfied | `toolkit/README.md` component bullet, now also naming the first-release exception and pointing at Conventions. |
| N13 — `CLAUDE.md` bullet hand-wrapped | Satisfied | Word-for-word identical to the pre-edit text; only line breaks moved. `doc-sync-test.sh` output read and green. |
| N9 / N14 / BD — dated record | Satisfied | `docs/changelog/2026-09-20-deliverable-review-fixes.md`, three sections, plus the index line in `docs/changelog.md` (title matches the entry's H1, no terminal period — consistent with every sibling bullet). All three carried items verified above. |

**Gaps:** none.

## Positive Observations

- Item 4.3's `recovery.md` addition does not merely assert the bound — it traces
  the failure to the exact refusal an operator would meet and names the one
  state where that refusal's own recorded reasoning breaks. That is the kind of
  claim a later reader can falsify, which is what makes it worth writing.
- Item 4.7 kept the figures out of the hub and in the dated entry for the stated
  reason, and said so in the entry. That is N14's defect avoided one layer up
  rather than merely fixed one layer down.
- The N10 trim genuinely moved arguments rather than deleting them: both
  destinations were checked and both already carried the material.
- Item 4.4 did more than the requirement asked — the README bullet now points at
  the Conventions section instead of leaving the two sixty lines apart with no
  thread between them.

## Recommendations

None blocking. One standing item, unchanged by this phase and out of its scope:
`toolkit/release.sh`'s comment above the drift refusal still claims "the
lost-tags probe above has already established that local and origin agree on the
newest one", which the partial-tag-loss bound Item 4.3 just recorded shows to be
false. The bound is now documented in two places while the shipped comment
asserting its negation is not — worth a line in a later pass.

## Deferred Items

- **`toolkit/release.sh`'s drift-refusal comment** — Reason: named in the
  dispatch's Scope OUT as a known residual already recorded for the user, and
  outside Item 4.3's two files.
- **`tests/release-test.sh`'s intermittent failure under a combined
  `just precommit`** — Reason: Scope OUT; the standing finding of this pass. Not
  observed in this review's run.

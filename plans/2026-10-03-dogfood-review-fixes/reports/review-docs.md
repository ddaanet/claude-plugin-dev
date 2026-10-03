# Review: dogfood review fixes — documentation group

**Scope**: `git diff f7a9bcf..HEAD` over `docs/design.md`,
`docs/references/dogfood.md`, `docs/changelog.md`,
`docs/changelog/2026-10-03-dogfood-review-fixes.md`, `README.md`,
`toolkit/README.md`, `toolkit/migrations/v0.9.0.md` and the Next steps output of
`toolkit/install.sh`. The prose was checked against
`git diff f7a9bcf..HEAD -- toolkit/bin/claude toolkit/dogfood.sh`. The
`CLAUDE.md` Layout was checked for statements this diff made false.

**Date**: 2026-10-03

**Mode**: review + fix

## Summary

The docs carry every Scope IN requirement. D4 and D9 are rewritten in place in
the hub and the node, in the present tense, with no strike-through and no
narrated history. The history is in the dated record only, and that record
refers to my human partner and never by name. The shim's sync condition, the
failed-sync line and its exit status, the `jq` exit 1, the zero-byte mask
behaviour and the `/reload-plugins` liveness list agree across the hub, node,
manual, front page, migration note and record, and they match the code.

There were five defects:

- the node's "The migration is a note" summary was stale, as flagged in Item
  2.2;
- a `CLAUDE.md` Layout bullet this diff made false;
- the A→B effect was worded so that it depended on PATH, in the node and in the
  record;
- the hub's D4 rationale did not name the repository;
- one 85-column line in the manual.

All five are fixed. `just format-docs` and `just precommit` are green.

**Overall Assessment**: Ready

## Issues Found

### Critical Issues

None.

### Major Issues

1. **`CLAUDE.md` Layout says the shim always syncs**
   - Location: `CLAUDE.md`, the `toolkit/bin/claude` Layout bullet
   - Problem: it read "Runs `dogfood.sh sync`, then execs …". Since Major 1 the
     shim skips the sync when `CLAUDE_CODE_PLUGIN_DIRS` already equals its own
     copy. The bullet is the repo's own description of the shipped file, and the
     diff made it false.
   - Fix: the bullet now says the sync runs unless the variable already names
     that copy, as it does for a `claude` started inside a dogfood session of
     the same repo. The rest of the bullet is unchanged. `doc-sync-test.sh`
     matches paths only, so it could not catch this.
   - **Status**: FIXED

### Minor Issues

1. **The node's migration summary still says "any recipe line naming it"**
   (specific attention 1)
   - Location: `docs/references/dogfood.md`, "The migration is a note"
   - Problem: the section still summarized step 2 as deleting "any recipe line
     naming it". The note now removes the `.bin` reference and deletes a line
     only when that reference is all it checks.
   - Fix: the summary now reads "delete any hand-copied `.bin/claude` and its
     `PATH_add`, and drop the `.bin` reference from each recipe line, deleting
     the line only when that reference is all it checks". The fix adds no
     reasoning and shaves none. After `just format-docs` the node is 399 lines
     against the 400 cap, at the formatter's 80-column wrap, with no long lines
     added. That leaves one line of headroom: the next addition to this node
     should come with a split.
   - **Status**: FIXED

2. **The A→B effect is stated as if any `claude` typed in B reaches B's shim**
   - Location: the effects list in `docs/references/dogfood.md`, "A `claude`
     started inside a dogfood session does not promote", and the same sentence
     in `docs/changelog/2026-10-03-dogfood-review-fixes.md`
   - Problem: the text read "a session in repository A running `claude` in
     repository B syncs B". The shim takes its root from its own location. An
     agent's Bash in A inherits A's PATH, so a `claude` it runs from B's
     directory reaches A's shim, which skips the sync and loads A's copy. B is
     synced only when B's shim is reached. The node's own bound, "Children
     inherit the variable", already said this, so the two passages disagreed.
   - Fix: both passages now read "a session in repository A whose `claude`
     reaches repository B's shim syncs B". The record is new in this diff, so
     the edit does not revise a dated entry.
   - **Status**: FIXED

3. **The hub's D4 rationale does not name the repository**
   - Location: `docs/design.md`, the D4 conclusion bullet
   - Problem: it said "A `claude` started inside a dogfood session already
     carries the variable naming this copy". A session of another repository
     carries a different value, and the shim syncs then.
   - Fix: the bullet now says "inside a dogfood session of the same repository",
     matching the bold conclusion directly above it and the node.
   - **Status**: FIXED

4. **An 85-column line in the manual's Launching**
   - Location: `toolkit/README.md`, the failed-sync paragraph ("does not end in
     `plugin-dev/bin/claude`. That session does not load the copy, and the")
   - Problem: the line was introduced by this diff. Item 2.2 claimed every line
     was at most 80 columns, and `format-docs` does not cover `toolkit/`.
   - Fix: re-wrapped this one paragraph's tail. This is not the out-of-scope
     README reflow.
   - **Status**: FIXED

## Fixes Applied

- `CLAUDE.md`, the `toolkit/bin/claude` Layout bullet: added the sync condition.
- `docs/references/dogfood.md`, "The migration is a note": step 2's summary now
  follows m5.
- `docs/references/dogfood.md`, the effects list: the A→B bullet now says the
  `claude` reaches B's shim.
- `docs/changelog/2026-10-03-dogfood-review-fixes.md`, "The shim promoted on
  every `claude` it fronted": the same A→B wording.
- `docs/design.md`, the D4 bullet: "inside a dogfood session of the same
  repository".
- `toolkit/README.md`, Launching: re-wrapped the overlong line.
- `just format-docs` re-wrapped the edited docs.
- `just precommit` ran in the foreground and exited 0. The lines below were in
  its output:
  - `release.just import: ok`;
  - `self-release.sh: ok`;
  - `dist tree ok`;
  - `docs ok (cap 400 lines, pointers resolve)`;
  - `doc sync ok (5 shared command blocks, Layout matches toolkit/)`;
  - `citations ok`;
  - the version-guard, check-version, release, install, dogfood sync,
    sync-refusal, pre-tool, session-start and launcher suites;
  - the final `ok`.

## Requirements Validation

| Requirement | Status | Evidence |
| --- | --- | --- |
| Major 1 — D4/D9 in the hub and node | Satisfied | Hub Requirements bullet; the D4 and D9 conclusions. Node: "Sync only on deliberate promotion" and its new subsection, "The shim", and the "Children inherit the variable" bound. All rewritten in place, in the present tense. |
| Major 1 — manual, and the front page if it says when sync happens | Satisfied | `toolkit/README.md`: the Contents bullet, the Launching list and Promoting changes. The front page does not state when the shim syncs; its m8 paragraph says only that a deliberate promotion changes the copy, which stays true. |
| m2 — zero-byte masks, the manual's scoping, the node's Risk settled | Satisfied | The manual now says to promote from your own shell "whether or not your plugin ships a `.mcp.json`". The node's `.mcp.json` bound says "probed with a simulated mask on rsync 3.5.0". This was verified against `deliverable-review-code.md` m2, whose probe environment was rsync 3.5.0. How Claude Code treats an empty `.mcp.json` stays marked unprobed or unverified. |
| m4 — Next steps and both READMEs point at Setup | Satisfied | `install.sh` step 3. Both READMEs have the paragraph after the Commit block. `doc-sync-test` is green. |
| m5, m6 — migration note | Satisfied | Step 2 removes the reference and deletes a line only when the reference is all it checks. The intro names rsync. The closing paragraph gives the `which -a claude` fallback. |
| m7 — liveness list | Satisfied | Commands, `.mcp.json` and output styles are listed. Every `/reload-plugins` claim not backed by a source is marked unverified. The claim that a relaunch makes them live is given with its reason. |
| m8 — the problem stated in the hub and the front page | Satisfied | The third-problem paragraph in the hub's Motivation, and the same paragraph in `README.md`'s "Why it exists". |
| m9 — "four repositories" | Satisfied | The node's sync-on-edit rejection. |
| Changelog record and index bullet | Satisfied | `docs/changelog/2026-10-03-dogfood-review-fixes.md`, and the first bullet in `docs/changelog.md`. |
| Code behaviours m1 and m3 described accurately | Satisfied | Node and record: `pre-tool` exits 1 on any `jq` failure with `jq`'s stderr kept. The failed-sync line comes after the sync's own stderr, and the exit status is the sync's. This matches `toolkit/dogfood.sh` and `toolkit/bin/claude`. |

**Gaps:** none.

## Positive Observations

- The node argues the rejected venues in the place a reader looks for them: the
  argv rule, and the opt-out together with the "call the next `claude`" rule.
  The record does not repeat that argument; it points at the node.
- The node marks the `jq` 1.6 exit-2 claim "read from its source, not probed",
  as the review did. It does not upgrade the claim to a probe.
- The m7 items keep verified claims apart from inferred ones, and give the
  reason behind the inferred relaunch claim.
- The record's Major 2 fixture names (`skills/demo/build.log`, root names
  beginning `- ` and `+ `) match the fixture in `tests/dogfood-sync-test.sh`,
  which landed at the baseline commit.

## Recommendations

- `docs/references/dogfood.md` is at 399 of 400 lines. Pair the next addition
  with a split on a need-time seam. Candidates are "Probe evidence" plus "Bounds
  accepted", or "The copy guard" plus "The session check".

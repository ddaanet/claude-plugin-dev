# Outline Review 2: dist-copy-dogfood-launcher

- **Artifact:** plans/2026-09-26-dist-copy-dogfood-launcher/outline.md
- **Requirements:** plans/2026-09-26-brief-dist-copy-dogfood-launcher.md, as
  amended by my human partner's five settled decisions (sync only at launch and
  by `just dogfood`; `CLAUDE_CODE_PLUGIN_DIRS` exported by the shim; an
  unconditional copy guard; a `SessionStart` warning with no adoption gate;
  gitlore's variable out of scope)
- **Date:** 2026-09-29
- **Mode:** review + fix-all, PDR criteria

## Summary

The revision expresses all five settled decisions consistently. No sync-on-edit
residue remains: no marker, no lock, no `PostToolUse` and no subdirectory
refusal. The review found four Major defects:

- the Q3 fallback put an agent-facing mapping on a user-only channel;
- both hooks compared paths by raw spelling;
- the OUT section said gitlore's variable was unset, when gitlore's own `.envrc`
  sets it;
- the migration note had no item to write it.

A subdirectory launch was also claimed to "work" when its hooks are unverified.
Every issue is fixed in the outline. Five risks were added, one of them backed
by a probe run during this review.

**Overall Assessment:** Ready. Two points added in review are flagged in
Recommendations for my human partner's confirmation.

## Requirements Traceability

KD = key decision.

| Brief item | Outline section | Coverage | Notes |
|---|---|---|---|
| D: load a copy, edit the source | Approach; KD1 | Complete | Loaded via the variable, not the flag (settled decision 2; KD9) |
| D: sync at launch, `rsync -a --delete` | KD2, KD8, KD9 | Complete | `--delete-excluded` added |
| D: sync on edit (`PostToolUse`) | KD4 | Superseded | Rejected by my human partner; replaced by `just dogfood` (KD10) and restart through the shim |
| D: wire like version-guard | KD11; item 5 | Complete | — |
| D: `dist/plugin/` survives `clean`, gitignored | KD9, KD11, KD12; item 7 | Complete | — |
| C: root layout, explicit source set, root from manifest | KD2, KD3, KD9 | Complete | — |
| C: deletions propagate, test proves it | item 2 | Complete | — |
| C: compose with other shims | KD9; item 4 | Complete | — |
| C: sync failure is loud | KD8 | Complete | The hook half is moot (no hook sync) |
| C: whitespace-safe, jq, NUL lists | KD2, KD6, KD11 | Complete | — |
| C: shellcheck, tests, `precommit` | items 2–6 | Complete | — |
| OQ1 symlink | KD1 | Complete | — |
| OQ2 non-Edit changes | KD4 | Partial → Complete | Now stated explicitly: promotion syncs the whole tree (Minor 6) |
| OQ3 edits aimed at the copy | KD6; Q3; item 1 | Complete | Fallback channel fixed (Major 1) |
| OQ4 subagent `PostToolUse` | KD4 | Partial → Complete | Now marked moot (Minor 6) |
| OQ5 launch vehicle | KD9, KD10 | Complete | The shim for launch, the recipe for promotion |
| Rejected approaches | KD1 | Complete | — |
| Consumers | Approach; KD12; OUT | Complete | — |
| Settled 1: promotion-only sync, no refusal | Approach; KD4; KD9 | Complete | The subdirectory claim is now accurate (Major 5) |
| Settled 2: exported variable, overwrite | KD9; item 4 | Complete | — |
| Settled 3: unconditional guard | KD6; item 3 | Complete | — |
| Settled 4: `SessionStart` warning, no gate | KD7; item 3 | Complete | Comparison rule added (Major 2) |
| Settled 5: gitlore OUT | OUT | Partial → Complete | Factual claim corrected (Major 3) |

**Traceability Assessment:** Every brief item and settled decision is covered.
The gaps found were fixed in the outline.

## Scope-to-Component Traceability

The outline has no C1/C2 components. Its numbered Items are the units.

| Scope IN item | Item | Notes |
|---|---|---|
| probe | 1 | — |
| `dogfood.sh` | 2, 3 | — |
| shim | 4 | — |
| `install.sh` wiring | 5 | — |
| `dogfood` recipe | 6 | — |
| tests, shipped-tree bookkeeping | 2–6 | — |
| migration note | 7 | Was an **orphan**: only decision 12 described it, and item 6 misplaced it in the dist-tree list (Major 4) |
| docs | 7 | — |

**Scope Assessment:** The one orphan was found and fixed. OUT is enumerated.

**Cross-item interface check:**

- `session-start` against the variable Claude Code writes back: a spelling
  mismatch (Major 2).
- `pre-tool` against the copy path: the same mismatch (Major 2).
- The `dogfood` recipe against `_import-check`: the no-gate contract was
  unpinned (Minor 4).
- Item 6 against `tests/dist-tree-test.sh`: the test already admits any
  `migrations/vX.Y.Z.md`, so the note gets no list entry (Major 4).

## Review Findings

### Critical Issues

None.

### Major Issues

1. **The Q3 fallback put the agent's mapping on a user-only channel**
   - Location: Open question, Q3.
   - Problem: If the guard is dropped, "`session-start` then states the
     source-versus-copy mapping in its `systemMessage`". `systemMessage` never
     reaches the agent (`plugin-craft:hook-authoring` §3), and the mapping
     exists to stop the agent aiming at the copy. The fallback would have been
     dead text.
   - Fix: The mapping moves to `SessionStart` `additionalContext`. The
     fallback's cost is stated: a copy edit meets the path-safety `ask` instead,
     never a silent edit.
   - **Status:** FIXED

2. **Both hooks compared paths by raw spelling**
   - Location: KD6 and KD7; item 3.
   - Problem: KD9 records that Claude Code normalizes the variable and writes it
     back. Claude Code's own path check resolves through `realpath` (research
     Q1). KD7 said only "does not contain", which leaves two failures open:
     - a raw string test warns on every session when the repo path spells a
       symlink;
     - a substring test accepts `/other/<root>/dist/plugin`.

     KD6's copy test has the same exposure, and a miss there lets a copy edit
     through the guard.
   - Fix:
     - KD7 splits on `:` and compares each entry whole, both sides via `pwd -P`.
     - KD6 compares physical paths, resolving the nearest existing ancestor as
       Claude Code does.
     - Item 3 gains cases for multi-entry, symlinked, trailing-slash and
       substring spellings.
   - **Status:** FIXED

3. **The OUT section misstated where gitlore's variable is set**
   - Location: Scope OUT, gitlore bullet.
   - Problem: The outline said the variable is "unset in my human partner's
     environment". `/Users/david/code/gitlore/.envrc` line 10 has
     `export GITLORE_AUTO_CLAUDE_PLUGIN_DIR=true`, and gitlore is a toolkit
     consumer. The handed-over brief says so itself. The conclusion stands: the
     brief sequences the variable's removal with gitlore adopting the shim. The
     stated reason was wrong.
   - Fix: The claim is corrected, and the brief is named by its path
     (`gitlore/inbox/2026-09-29-brief-remove-auto-plugin-dir.md`, which already
     exists). "The shim does not work around it" is kept, per settled decision
     5.
   - **Status:** FIXED

4. **No item wrote the migration note, and item 6 misplaced it**
   - Location: Items 6 and 7; Scope IN.
   - Problem: Decision 12 specifies the note, but no item produced it. Item 6
     put "the migration note" into `tests/dist-tree-test.sh`'s list. That test
     already admits any `migrations/v[0-9][0-9.]*.md` without a list edit, and a
     list entry would make it fail on the first release that has no note.
   - Fix: Item 7 now writes the note. Item 6 lists only `dogfood.sh` and
     `bin/claude`, and says why the note needs no entry. Scope IN points the
     note at item 7.
   - **Status:** FIXED

5. **"A launch from a subdirectory works" was unverified for the hooks**
   - Location: KD9, Subdirectories bullet.
   - Problem: The absolute variable does load the copy from a subdirectory.
     Nothing establishes that the root's project hooks fire there, since they
     are wired through `${CLAUDE_PROJECT_DIR}`. If they do not fire, the session
     has neither guard nor warning, silently. My human partner settled on no
     refusal. The defect is the claim, not the choice.
   - Fix: KD9 states what is and is not established. Item 1 adds a second,
     non-gating launch from a subdirectory to record it. Item 7's README carries
     the finding, and Risks names the residual with its bound: a copy edit still
     meets the path-safety `ask`.
   - **Status:** FIXED (a probe observation added in review; see
     Recommendations)

### Minor Issues

1. **A sandboxed `just dogfood` leaves `.mcp.json` stale** (Risks; KD8). Probed
   in this review with rsync 3.4.1. With a masked char-device `.mcp.json` as
   source and a regular `.mcp.json` already in the destination,
   `rsync -a --delete` printed `skipping non-regular file ".mcp.json"`, exited
   0, and left the old destination file in place. `.mcp.json` is the one plugin
   component on the sandbox's mask list. KD8 called the warning "harmless"; it
   now names the exception. A risk was added with its bound: only an agent-run,
   sandboxed `just dogfood` is affected, and no consumer tracks a `.mcp.json`
   (`git ls-files` in cwd-safety and handoff returns nothing). The README
   carries the caveat. FIXED.
2. **The migration note would break craft's gate** (KD12).
   `/Users/david/code/craft/justfile` line 9 shellchecks `.bin/claude`, so
   deleting the shim as the note says fails craft's `precommit`. The note now
   says to drop recipe lines naming it. FIXED.
3. **`pre-tool` without `jq` was unspecified** (KD6). Now: exit 0 with no
   output. The path-safety `ask` still stops copy edits, and `session-start`
   already reported the missing `jq`. Item 3 tests it. This is a decision added
   in review. FIXED.
4. **`dogfood`'s no-gate contract was unpinned** (item 6; KD10). `_import-check`
   pins `resume-release`'s. It now pins `dogfood`'s the same way. KD10 now
   spells the recipe body like its neighbours'. FIXED.
5. **`<self>/../..` was ambiguous** (KD9). Read as the shim file, it names
   `plugin-dev/`, not the root. It is now `<shim dir>/../..`, with the path
   spelled out. FIXED.
6. **Brief OQ2 and OQ4 were not traced** (KD4). Both became moot under settled
   decision 1, but the outline never said so. KD4 now does. FIXED.
7. **Doc touch-points were incomplete** (items 6 and 7). The following were
   added:
   - `toolkit/README.md` Contents bullets, and `rsync` under Requirements;
   - the root `README.md`'s "What a consumer plugin gets";
   - CLAUDE.md's list of `docs/references/` nodes;
   - a note that the dogfood section stays out of the install/update sections,
     whose command blocks `tests/doc-sync-test.sh` pins in both READMEs.

   FIXED.
8. **Item 5 extends a suite already over the cap.**
   `tests/update-plugin-dev-test.sh` is 406 lines and already mixes install.sh
   and update.sh scenarios, against CLAUDE.md's one-script-per-suite convention.
   Item 5 now acknowledges this and keeps the additions compact. Splitting the
   suite is named as a separate cleanup. FIXED (see Recommendations).
9. **Risks were incomplete.** Four were added:
   - promotion is repo-wide across live sessions, because hook-script and `bin/`
     bodies are read per call;
   - a `claude` started from a dogfood session's Bash inherits the variable and
     loads this repo's copy;
   - a Bash write into `dist/plugin/` passes both guards and is lost at the next
     sync;
   - subdirectory launches may run without the hooks.

   FIXED.
10. **Scope IN folded item ranges.** The docs and migration-note line pointed at
    "items 2–7". It is now split, with item 7 named. FIXED.

## Provenance

Left as found, per the caller. `Derived from: none` names the brief as
requirements input, not as a superseded artifact. `Base:` is
`389e8b02cbbd19e8fa266175e293c5bc36323966`: a full sha, and
`git merge-base --is-ancestor` against HEAD exits 0.

## Fixes Applied

- KD4: OQ2 and OQ4 traced as settled.
- KD6: physical-path comparison; `jq`-missing behaviour.
- KD7: entry-wise, `pwd -P` comparison, with the reason.
- KD8: the "harmless" warning now names `.mcp.json` as the exception.
- KD9: `<shim dir>/../..`; the subdirectory claim narrowed to what is
  established.
- KD10: recipe body spelled like its neighbours'.
- KD12: drop recipe lines that name the old shim.
- Q3: fallback moved to `additionalContext`, with its cost stated; a non-gating
  subdirectory launch added to the probe.
- Item 3: seven cases, where there were five.
- Item 5: suite-size note.
- Item 6: `_import-check` pins `dogfood`; dist-tree list corrected; CLAUDE.md's
  references list.
- Item 7: writes the migration note; README Contents and Requirements; root
  README bullet; doc-sync boundary.
- Scope IN: item ranges split.
- Scope OUT: gitlore claim corrected; the brief named by path.
- Risks: five added (`.mcp.json`, subdirectory hooks, repo-wide promotion,
  inherited variable, Bash writes to the copy); the `.mcp.json` zero-byte
  variant noted as unprobed.
- Whole file: reflowed with `rumdl fmt` (0.2.60), 364 lines, none over 80.

## Positive Observations

- All five settled decisions land cleanly. The outline carries none of the
  rejected design's machinery, and it records why that design was rejected.
- KD4 grounds "sync only on promotion" in what Claude Code actually re-reads,
  and when. The argument cites the skill rather than asserting it.
- The copy guard's three-channel split and its rejection of `updatedInput`
  follow `plugin-craft:hook-authoring` exactly.
- Settled decision 2 is carried through into the tests: the shim overwrites an
  inherited value, and item 4 asserts that.
- Chaining reuses sandbox-lies's `-ef` strip, the one existing shim that is
  robust to spelling. It does not copy the `grep -vxF` form that craft,
  cwd-safety and handoff share.
- The probe states its unsandboxed requirement and its evidence source (hook
  log, transcript JSONL via `jq`), per `sandbox-effects`.

## Recommendations

1. **Confirm `pre-tool`'s `jq`-missing behaviour** (KD6), added in review. The
   alternative is a static deny of every edit, which fails closed but blocks all
   editing until `jq` is installed.
2. **Confirm the subdirectory observation in item 1.** It is one extra nested
   launch. If the hooks do not fire there, the README should say to launch from
   the root. Refusal stays off, as settled.
3. **The suite split** (Minor 8): consider a follow-up that moves install.sh's
   scenarios into `tests/install-test.sh`, per CLAUDE.md's one-script-per-suite
   rule.
4. **install.sh's closing "Next steps"** could name the three manual steps
   (`.envrc`, `.gitignore`, `clean`) as well as the README. That would be a
   decision beyond KD11, so it is left to my human partner.
5. **macOS rsync** is unchanged from the previous review: run item 2's suite on
   a macOS consumer before cutting the release.

---

**Ready for user presentation:** Yes. All findings are fixed in the outline.
Recommendations 1 and 2 cover points added in review.

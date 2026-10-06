# Deliverable Review: 2026-10-05-dogfood-drop-auto-sync

**Date:** 2026-10-06 **Methodology:** edify `deliverable-review` skill, two
layers. The node `docs/references/deliverable-review.md` that the skill cites is
not shipped in edify 0.3.0, so the axes and severity levels used here are the
ones the skill body states.

- **Baseline:** `plans/2026-10-05-dogfood-drop-auto-sync/outline.md`, with
  decisions 1-5. There is no runbook. The item map is `reports/build-summary.md`
  plus `reports/assert-pipe-fix.md`.
- **Range:** `e444427^..4a1aad6`. It holds the five job commits and the
  assertion fix.
- **Range source:** `edify-review-range.sh` printed `NO-PROVENANCE:`, so the
  range used is the one the dispatch named.
- **Settled material, not re-reported:**
  - the outline's decisions;
  - the prior review,
    `plans/2026-10-03-dogfood-review-fixes/reports/deliverable-review.md`, and
    the build summary's dispositions of its findings. Each disposition was
    checked in the tree and holds; see Gap Analysis.
  - the dated record `docs/changelog/2026-10-03-dogfood-review-fixes.md`.

## Inventory

| Type | File | +/- |
|---|---|---|
| Code | `toolkit/bin/claude` | +12/-21 |
| Code | `toolkit/install.sh` (Next steps) | +3 |
| Test | `tests/dogfood-launcher-test.sh` | +47/-121 |
| Test | `tests/install-test.sh` | +11/-2 |
| Test (here-string fix) | `check-version`, `citation`, `dist-tree`, `dogfood-pre-tool`, `dogfood-sync-refusal`, `dogfood-sync`, `release`, `self-release`, `update-plugin-dev`, `version-guard` suites | +53/-20 |
| Human docs | `docs/design.md` | +20/-23 |
| Human docs | `docs/references/dogfood.md` | +67/-77 |
| Human docs | `docs/changelog.md` | +7 |
| Human docs | `docs/changelog/2026-10-05-the-shim-stops-syncing.md` | +77 (new) |
| Human docs | `toolkit/README.md` | +47/-37 |
| Human docs | `README.md` | +7/-6 |
| Human docs | `toolkit/migrations/v0.9.0.md` | +3/-6 |
| Human docs | `toolkit/migrations/v0.9.1.md` | +22 (new) |
| Agent instructions | `CLAUDE.md` | +6/-8 |

That comes to about 700 changed lines outside `plans/`. Layer 1 therefore ran as
two opus agents, one for code and tests and one for prose and config.

**Design conformance.**

- The shim implements decisions 1 and 2 as worded:
  - physical root;
  - a missing-directory refusal with one `dogfood:` line and exit 1, placed
    before the export and the PATH strip;
  - the export, the strip, exit 127, and `exec claude "$@"`.
- The skip and the sync-failure path are gone, with no leftovers.
- Decision 4: only the v0.9.0 note's closing paragraph changed.
- Decision 5: the fallback is kept, in bash and fish forms.
- A sweep of the repo outside `plans/` and the exempt dated records found no
  text that still describes a launch-time sync, the skip, or the sync-failure
  path. Both layers swept independently.
- The here-string change is complete: no pipe into an early-exiting reader
  remains in `tests/` outside comments. It also preserves semantics: the
  patterns are still BRE without `-F`, and no needle matches an empty line.

**Gates run in the foreground at `4a1aad6`.** All exited 0 with no `FAIL` line:

- the `dogfood-launcher`, `install`, `docs`, `doc-sync`, `dist-tree` and
  `citation` suites;
- Layer 1 additionally ran `check-version`, `dogfood-pre-tool`,
  `dogfood-sync-refusal`, `dogfood-sync`, `version-guard`, `update-plugin-dev`,
  `self-release` and `release`;
- `shellcheck` on the shim, `install.sh` and every suite.

`just precommit` was not run, because it writes to the tree.

## Critical Findings

None.

## Major Findings

1. **A `just dogfood` that fails for lack of rsync leaves an empty copy, so the
   shim launches a plugin-less session in silence. That is the case the refusal
   exists for, on the cause the manual names.**
   - **Locations:**
     - `toolkit/dogfood.sh:67-69`, unchanged in the range:
       `mkdir -p "$root/dist/plugin"` runs before `rsync`.
     - `toolkit/bin/claude:22`: the check is `-d` only.
     - The docs that rest on the premise:
       - `toolkit/README.md:230-242`: "If `just dogfood` cannot create the copy,
         `rsync` missing among the causes", then the fallback.
       - `docs/references/dogfood.md:128-133` and
         `docs/changelog/2026-10-05-the-shim-stops-syncing.md:24-27`: "A session
         started anyway would load no plugin, and nothing would say so".
       - `docs/design.md:224-227`.
   - **Axes:** functional correctness (the shim and sync together), accuracy
     (the manual's fallback premise).
   - **Not a contest of decision 2.** The shim checks "not a directory" exactly
     as the outline words it. The finding is that the toolkit's own sync defeats
     the purpose the decision states for that check, and that the docs describe
     a state, "cannot create the copy", which the named cause does not produce.
   - **Probe (Layer 2, scratch consumer, unsandboxed):**
     1. On a fresh fixture, `dogfood.sh sync` ran with a PATH that lacked rsync.
        It printed `rsync: command not found` and exited 127.
     2. `dist/plugin/` was left as an empty directory.
     3. `claude --version` through the shim then exec'd the stub with
        `CLAUDE_CODE_PLUGIN_DIRS=<root>/dist/plugin` and exited 0. There was no
        refusal.
     4. `dogfood.sh session-start` with that variable printed nothing and exited
        0. It was silent.
   - **Failure scenario:**
     1. A maintainer on a minimal Linux image without rsync follows Setup or the
        v0.9.1 note and runs `just dogfood`. It fails.
     2. They type `claude`, and the session starts with no refusal line.
     3. It loads an empty plugin dir: no skills, hooks or agents. Neither the
        shim nor `session-start` says anything.
     4. The manual's fallback is never reached, because they never see "no
        copy". Its stated trigger cannot be observed for rsync.
   - **Partial-copy variant (outside the decision's scope):** a later rsync
     failure leaves a partial copy. Decision 2's "no staleness detection" covers
     that variant, so it is not part of this finding.
   - **Corroboration:** the launcher fixture treats an empty `dist/plugin` as a
     valid copy (`tests/dogfood-launcher-test.sh:70-71`, `:108`). The suite
     therefore encodes the same assumption.
   - **Fix options, for my human partner:**
     - Make `sync_copy` create the copy only once rsync can run. One way is
       `command -v rsync` before the `mkdir`, as a fourth refusal. Another is to
       rsync into a temporary sibling and rename it.
     - Or have the shim test for the copy's manifest
       (`dist/plugin/.claude-plugin/plugin.json`) rather than the directory.
       That changes decision 2's wording, so it is my human partner's call.
     - Either way, the manual's fallback sentence should name a cause that
       actually leaves no copy.
   - **Source:** Layer 2. Layer 1's code minor 1 (below) is the neighbouring
     `-d`/`-e` coverage gap.

2. **No test pins the decided precedence of exit 1 over 127.**
   - **Locations:**
     - the checks: `toolkit/bin/claude:22-25` (copy) and `:29-32` (127);
     - the scenarios: `tests/dogfood-launcher-test.sh:195-207` (missing copy)
       and `:333-349` (no next `claude`).
   - **Axes:** test coverage and specificity, for a specified scenario.
   - **What is specified:** outline decision 2 says "The check comes before the
     PATH strip". The build summary records the consequence as decided: with
     neither a copy nor another `claude`, exit 1 wins.
   - **What is tested:** the missing-copy scenario always has the stub on PATH,
     and the 127 scenario always has a copy.
   - **Probe:** Layer 1's mutant `order` moves the copy check below
     `command -v claude`. All 11 scenarios still pass.
   - **Failure scenario:**
     1. A later edit regroups the pre-exec checks.
     2. A fresh clone on a CI image or new machine, with no other `claude` on
        PATH, gets `dogfood: no other claude on PATH` with exit 127.
     3. The maintainer goes hunting for a `claude` install, when the remedy is
        `just dogfood`.
     4. The suite stays green.
   - **Fix:** one scenario with the copy removed and `path_exact` set to the
     shim directory plus `bash`/`dirname`. Assert:
     - rc 1;
     - one stderr line naming `just dogfood`;
     - no `dogfood: no other claude on PATH` line.
   - **Source:** Layer 1 code report, major 1. Layer 2 confirmed it against the
     suite.

## Minor Findings

### Accuracy and consistency

1. **The hub restates the retracted premise.**
   - **Location:** `docs/design.md:220-222`.
   - **What it says:** "Syncing at launch promoted the working tree repo-wide on
     every `claude` invocation".
   - **The conflict:** the node (`dogfood.md:116`) says "every `claude` that
     reaches the shim". The new record corrects the 2026-10-03 premise precisely
     because an agent's nested `claude` never reached the shim.
   - **Failure scenario:** a hub-only reader concludes that the exported PATH
     strip guards nothing. They then make it local, as gitlore's launcher does.
   - Source: prose report, minor 1.

2. **The record's premise correction overstates its own case.**
   - **Location:** `docs/changelog/2026-10-05-the-shim-stops-syncing.md:52-54`.
   - **What it says:** "The syncs that did happen were the human's own".
   - **Why it is too strong:** a session started past the shim, the documented
     fallback included, kept `plugin-dev/bin` on PATH with the variable unset.
     So an agent's `claude -p` there reached the 0.9.0 shim. The record's own
     minor-1 bullet concedes such sandboxed syncs.
   - **Failure scenario:** a reader takes the record as proof that no
     agent-driven sync ever ran.
   - **Note:** the record is new and has not been relied on yet, so amending it
     before release is my human partner's call.
   - Source: prose report, minor 2.

3. **The record gives all nine red failures to the new scenarios.**
   - **Location:** the record, `:36-40`.
   - **What the evidence shows:** `reports/red-launcher.txt` has 7 failures in
     the two new scenarios. The other 2 are in the rewritten inherited-variable
     and 127 scenarios.
   - **Failure scenario:** an auditor reconciling the record with the evidence
     finds 7 against 9.
   - Source: prose report, minor 3. Layer 2 re-counted.

4. **The record implies an earlier shim that synced without a skip.**
   - **Location:** the record, `:11-13`: "Through 0.9.0 the shim ran
     `dogfood.sh sync` … 0.9.0 added a skip".
   - **Why it misleads:** `toolkit/bin/claude` is absent at `v0.8.0`. The shim
     (`ff6c4c2`) and the skip (`9104046`) both landed in the 0.9.0 range.
   - **Failure scenario:** a reader goes looking for 0.8.x sync side effects,
     and none can exist.
   - Source: prose report, minor 4. Layer 2 verified it with `git log`.

5. **The hub and node tell the rejected launch sync as past events, not as an
   argument.**
   - **Location:** `docs/references/dogfood.md:115-124` and
     `docs/design.md:220-222`.
   - **Why it matters:** the node's other "Rejected:" entries argue in the
     conditional. `CLAUDE.md` keeps design docs present-tense and leaves history
     to the dated record. These sentences duplicate the record (`:11-18`), so
     the two can drift.
   - Source: prose report, minor 5.

6. **"And children" is left as a reason with nothing behind it.**
   - **Location:** `docs/design.md:239-242`.
   - **Why it is empty:** the clause that explained it ("how a nested `claude`
     knows…") went with the skip. The node now files child inheritance under
     "Bounds accepted" as a cost.
   - **Failure scenario:** someone weighing `--plugin-dir` against the variable
     counts as a requirement something the design no longer needs.
   - Source: prose report, minor 6.

### Completeness and usability

7. **The "bash or zsh" fallback is unprobed in zsh, whose `which` is a
   builtin.**
   - **Location:** `toolkit/README.md:230-236`.
   - **The difference:** zsh's `which -a` also lists aliases and functions. A
     `claude` alias puts `claude: aliased to …` first, `grep -v` keeps it, and
     the command fails. That reading is grounded in the zsh docs, not probed.
   - **What was probed:** the bash and fish forms, which Layer 1 ran against a
     stub PATH.
   - **Fix:** `command which -a claude`, or label the block bash only.
   - Source: prose report, minor 7.

8. **A hand reader of the 0.9.0 note is never told to run `just dogfood`.**
   - **Location:** `toolkit/README.md:186-189` scopes the step to "a plugin
     coming from 0.9.0". `toolkit/migrations/v0.9.0.md:52-54` defers it to the
     0.9.1 note "printed after this one".
   - **The gap:** two routes put the 0.9.0 note in front of a reader without
     `update.sh` printing the 0.9.1 note after it:
     - the manual's own pointer;
     - `update.sh`'s "previous toolkit version unknown — review … by hand".
   - **Failure scenario:** a pre-launcher plugin finishes steps 1-4, launches,
     and is refused. The refusal names the remedy, so the cost is one refused
     launch.
   - Source: prose report, minor 8.

9. **`-d` versus `-e` is not distinguished by any scenario.**
   - **Location:** `toolkit/bin/claude:22`, and
     `tests/dogfood-launcher-test.sh:195-207`, whose only negative case is
     `rm -r dist`.
   - **Probe:** mutant `e_test` passes every scenario.
   - **Failure scenario:** a regular file at `dist/plugin` and a regressed `-e`
     test give a session whose variable names a file. `session-start` compares
     that entry as spelled, matches it, and stays silent.
   - Source: code report, minor 1.

### Considered and not raised

- **`v0.9.0.md:3-4` "plus `just dogfood` to re-sync it".** This lies outside the
  closing paragraph, and decision 4 limits the edit to that paragraph.
- **No scenario with the inherited variable exactly equal to the copy.** The
  only mutant that slips through is a sync conditioned on equality, which is
  contrived.
- **A root holding `:` or a newline.** Both predate the range, and the
  variable's format imposes them.
- **The two `release-test.sh` comments (`:1602`, `:1656`) that quote the old
  pipe.** They describe `release.sh`'s former ladder and are outside the change.
- **`docs/references/distribution.md`'s `update-plugin-dev vX.Y.Z`.** It is a
  past-tense account, as the disposition says.

## Gap Analysis

| Outline requirement | Status |
|---|---|
| D1: shim keeps physical root, export, strip, 127, exec argv unchanged; skip and sync-failure path removed with no leftovers | covered |
| D2: missing copy refuses, one `dogfood:` line naming `just dogfood`, exit 1, before the strip | covered as worded; purpose defeated by an empty copy (Major 1); precedence untested (Major 2); `-d` untested (minor 9) |
| D3: hub, node, both READMEs, `CLAUDE.md` Layout bullet, `install.sh` Next steps rewritten in place | covered; minor 1, 5, 6 |
| D3: new `migrations/v0.9.1.md` | covered; minor 8 |
| D3: new dated record and index bullet; 2026-10-03 record untouched | covered; minor 2, 3, 4 |
| D4: v0.9.0 note, closing paragraph only | covered |
| D5: fallback kept, verbatim, bash and fish | covered; premise (Major 1), zsh (minor 7) |
| Work item 1: launcher scenarios added/dropped, 127 tool list trimmed, install names `just dogfood`, red recorded | covered |
| Prior Major 1, minor 2, minor 5: moot, and no doc describes the skip or a launch sync | holds |
| Prior minor 1: reworded for "the shim never syncs" | holds (`dogfood.md:382-384`, manual "a launch is unaffected") |
| Prior minor 3: `🔖 X.Y.Z` | holds |
| Prior minor 4: corrected in the new record | holds |
| Prior minor 6: verbatim fallback | holds; minor 7 |
| Prior minor 7: `CLAUDE.md` wrap | holds |
| Outside range: hub Limitations `dist-vX.Y.Z` | holds (`design.md:265`) |
| Follow-up 4a1aad6: helpers grep a here-string; inline checks and gitlink captures fixed | covered: complete, semantics preserved |

No deliverable is missing. One deliverable is outside the outline: the 11-suite
assertion fix. It explains itself in `reports/assert-pipe-fix.md` and in a
comment on each helper.

## Summary

- Critical: 0
- Major: 2
- Minor: 9

The shim, its tests and the docs match the outline's decisions. No text outside
the exempt records still describes a launch-time sync, the skip, or the
sync-failure path. The assertion fix is complete.

- **Major 1:** the sync creates `dist/plugin/` before it runs rsync. With rsync
  missing, the shim's presence check therefore passes, and the session loads an
  empty plugin with nothing saying so. That is the outcome the refusal was
  decided to prevent, on the cause the manual's fallback names.
- **Major 2:** the decided precedence of exit 1 over 127 has no test, and a
  reordering mutant passes the whole suite.
- **The minors:**
  - wording in the hub and the new record;
  - the zsh form of the fallback;
  - the hand-read migration path;
  - the `-d` coverage gap.

## Sub-reports

- `plans/2026-10-05-dogfood-drop-auto-sync/reports/deliverable-review-code-tests.md`
- `plans/2026-10-05-dogfood-drop-auto-sync/reports/deliverable-review-prose-config.md`

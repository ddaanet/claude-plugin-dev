# Deliverable review, Layer 1: prose and config

Job: `plans/2026-10-05-dogfood-drop-auto-sync`. Range: `e444427^..4a1aad6`.
Baseline: `outline.md` (decisions 1-5). Checked against the shipped
`toolkit/bin/claude`, `toolkit/install.sh`, `toolkit/dogfood.sh` and
`toolkit/update.sh`.

Files: `docs/design.md`, `docs/references/dogfood.md`, `docs/changelog.md`,
`docs/changelog/2026-10-05-the-shim-stops-syncing.md`, `toolkit/README.md`,
`README.md`, `toolkit/migrations/v0.9.0.md`, `toolkit/migrations/v0.9.1.md`,
`CLAUDE.md`.

Counts: Critical 0, Major 0, Minor 8.

## Findings

### 1. Minor: the hub still says the launch sync fired on every `claude`

- **Where:** `docs/design.md:220-222`.
- **Axes:** accuracy, consistency.
- **What it says:** "Syncing at launch promoted the working tree repo-wide on
  every `claude` invocation".
- **Why it is wrong:** the node (`dogfood.md:116`) correctly says "every
  `claude` that reaches the shim". The new record (`:46-54`) and its index
  bullet (`changelog.md:15-17`) correct the 2026-10-03 premise because a nested
  `claude` inside a dogfood session never reached the shim. The hub's "every
  `claude` invocation" restates the premise this same change retracts.
- **Failure scenario:** a maintainer reads only the hub, as the hub tells them
  to. They conclude that an agent's nested `claude -p` used to promote, then
  weigh a later change to the PATH strip (for example, making it local the way
  gitlore's launcher does) as if it guarded nothing.
- **Fix:** "on every `claude` that reached the shim".

### 2. Minor: the new record's premise correction overstates its own case

- **Where:** `docs/changelog/2026-10-05-the-shim-stops-syncing.md:52-54`.
- **Axis:** accuracy.
- **What it says:** "The syncs that did happen were the human's own, which the
  skip left syncing."
- **Why it is wrong:** prior review minor 1 (`deliverable-review.md:139-152`,
  settled) found a non-human route. In a session started *past* the shim, the
  variable is unset and `plugin-dev/bin` is still on PATH. Such sessions include
  the documented fallback and gitlore's launcher run by hand. There, an agent's
  `claude -p` reached the 0.9.0 shim and synced inside the sandbox. The record's
  own "Minor 1" bullet (`:68-70`) concedes that sandboxed syncs happen.
- **Failure scenario:** a reader treats the record as establishing that no
  agent-driven sync ever ran. The record makes the same kind of overstatement it
  was written to correct.
- **Fix:** "were run with `plugin-dev/bin` on PATH and the variable unset: the
  human's own terminal, or a session started past the shim".
- The record is this job's own and has not yet been relied on. Whether to amend
  it before release is my human partner's call.

### 3. Minor: the record gives all nine red failures to the new scenarios

- **Where:** `docs/changelog/2026-10-05-the-shim-stops-syncing.md:36-40`.
- **Axis:** accuracy.
- **What it says:** "the launcher suite's new scenarios … failed on nine
  assertions".
- **What the evidence shows:** `reports/red-launcher.txt` has 2 + 5 = 7 failures
  in the two new scenarios. The other 2 are in rewritten existing scenarios: "an
  inherited variable is overwritten: the launch does not sync" and "no next
  claude exits 127".
- **Failure scenario:** an auditor reconciling the record against the red
  evidence finds a 7/9 mismatch and doubts the evidence trail.
- **Fix:** "nine assertions, seven in the new scenarios and two in the rewritten
  inherited-variable and 127 scenarios".

### 4. Minor: the record implies a released shim that synced without a skip

- **Where:** `docs/changelog/2026-10-05-the-shim-stops-syncing.md:11-13`.
- **Axis:** accuracy.
- **What it says:** "Through 0.9.0 the shim ran `dogfood.sh sync` … 0.9.0 added
  a skip".
- **Why it is wrong:** the shim first shipped in 0.9.0, and it already had the
  skip. `git log v0.8.0..v0.9.0 -- toolkit/bin/claude` shows both the shim
  (`ff6c4c2`) and the skip (`9104046`) inside the 0.9.0 range.
- **Failure scenario:** a reader takes "through 0.9.0" and "added" to mean that
  0.8.x consumers ran a syncing shim. They then look for 0.8.x-era sync side
  effects that cannot exist.
- **Fix:** "The shim, new in 0.9.0, ran `dogfood.sh sync` before its exec,
  except when …".

### 5. Minor: hub and node narrate the overturned decision in the past tense

- **Where:**
  - `docs/references/dogfood.md:115-124` ("The shim synced before its exec …
    Each re-promoted … A skip … covered only");
  - `docs/design.md:220-222` ("Syncing at launch promoted").
- **Axis:** consistency with the `CLAUDE.md` convention that design and nodes
  are present-tense, with overturned decisions rewritten in place.
- **The inconsistency:** the node's other "Rejected:" entries argue in the
  conditional ("would re-run the sync after each call", `:104-113`). This one
  retells what happened, which is the dated record's job.
- **Failure scenario:**
  1. The node reads as half changelog.
  2. The next pass that touches the shim has to rewrite history sentences rather
     than an argument.
  3. The history duplicates `2026-10-05-the-shim-stops-syncing.md:11-18`, so the
     two can drift.
- **Fix:** restate the alternative conditionally. For example: "A shim that
  syncs before its exec would make every `claude` that reaches it a promotion… A
  skip on the variable would cover only…".

### 6. Minor: the hub keeps "and children" as a reason with nothing behind it

- **Where:** `docs/design.md:239-242`.
- **Axes:** vacuity, consistency.
- **What it says:** "the variable reaches hooks, which is what `session-start`
  checks, and children."
- **Why it is now empty:** before this change the clause went on to say "which
  is how a nested `claude` knows it is inside this repository's dogfood
  session". With the skip gone, nothing in the toolkit depends on children
  inheriting the variable. The node now files that inheritance under "Bounds
  accepted" (`dogfood.md:363-366`), together with the hooks-twice risk
  (`:250-252`). So the hub presents as a reason for the decision what the node
  treats as a cost.
- **Failure scenario:** a maintainer weighing `--plugin-dir` against the
  variable counts child inheritance as a requirement and rejects an option the
  design no longer needs to reject.
- **Fix:** drop "and children", or say what children gain from it (for example,
  "and children, so an eval run from the session loads the same copy").

### 7. Minor: the "bash or zsh" fallback was probed in bash only, and zsh's `which` differs

- **Where:** `toolkit/README.md:230-236`.
- **Axes:** usability, robustness edge case.
- **What was probed (this review):** the bash form and the fish form, against a
  stub PATH under `$TMPDIR`. The repo path held a space, the shim came first,
  and a stub next `claude` sat behind it.
  - Both exec the stub with `CLAUDE_CODE_PLUGIN_DIRS` unset, exit 0.
  - fish 4.0.2 rejects the bare `(…)` form in command position, as the build
    summary says.
  - With no other `claude` on PATH, bash prints
    `bash: line 1: : command not found` (127) and fish prints
    `The expanded command was empty.` (123). Both are opaque but harmless.
- **The zsh gap:** no zsh is installed here, so the zsh form is unprobed. In
  zsh, `which` is a builtin (`whence -c`), and with `-a` it also lists aliases
  and functions. Grounding: zsh documentation, not probed.
- **Failure scenario:** a zsh user has `alias claude=…` in their rc. Claude
  Code's older local installer wrote exactly such an alias; this is plausible,
  not verified here. For that user, `which -a claude` prints
  `claude: aliased to …` first. `grep -v` keeps that line, and the fallback runs
  it as a command name and fails, at the moment the tooling has already failed.
- **Fix:** `command which -a claude`. It runs the external `which` in both bash
  and zsh, and the fish line can keep its form. Alternatively, label the block
  "bash" only.

### 8. Minor: a hand reader of the 0.9.0 note is never told to run `just dogfood`

- **Where:**
  - `toolkit/README.md:186-189` scopes the step to "a plugin coming from 0.9.0".
  - `toolkit/migrations/v0.9.0.md:52-54` defers it to "The 0.9.1 note, printed
    after this one when your update crosses both".
- **Axes:** usability, completeness.
- **What works:** printed by `update.sh`, the two notes come out in order, 0.9.0
  then 0.9.1 (`sort -V`, range (old, new]; checked at `update.sh:82-96`). Read
  in that order they are coherent: steps 1-4 end with the copy ignored, which
  `just dogfood` in the 0.9.1 note needs.
- **The gap:** two routes put a reader in front of `v0.9.0.md` by hand:
  - the manual's pointer, "takes the steps in
    `plugin-dev/migrations/v0.9.0.md`";
  - `update.sh:83-84` ("previous toolkit version unknown — review
    `plugin-dev/migrations/` by hand").

  On either route, the 0.9.1 note was not "printed after this one", and the
  manual's sentence addresses only plugins coming from 0.9.0.
- **Failure scenario:** a pre-launcher plugin finishes steps 1-4, types
  `claude`, and is refused. The refusal line names `just dogfood`, so the cost
  is one refused launch.
- **Fix:** widen the manual's sentence to "so a plugin coming from before 0.9.1
  runs `just dogfood` before its next launch". The v0.9.0 note's closing could
  also name `migrations/v0.9.1.md` directly instead of "printed after this one".
  Both edits stay within decision 4's closing-paragraph limit.

## Verified clean

- **Shim message:** the refusal line is quoted byte-identically in the code
  (`toolkit/bin/claude:23`), the node (`:130`), the manual (`:227`) and
  `v0.9.1.md:15`.
- **Shim behaviour:** with no copy, the shim exits 1 with that one line. This
  review ran it against the probe fixture, with a space in the repo path.
- **Missing-copy check order:** the check precedes the PATH strip
  (`bin/claude:22-28`), as decision 2 requires. The node says the same at
  `dogfood.md:231-236`.
- **Outline decision 1:** export, strip, 127 and the exec with argv unchanged
  are described consistently in the hub, node, manual, `CLAUDE.md` and the
  record. Nothing outside `plans/` and the two exempt 2026-10-03 and 2026-09-30
  dated entries still describes a launch-time sync, the skip, or the
  sync-failure path. Swept with `git grep` over the whole repo outside `plans/`,
  the `memory/` store included, for:
  - sync at launch, launch sync, launch-time;
  - "sync failed", "not started", "names its own copy";
  - relaunch, re-promot, skip, re-sync.

  Every hit is the new wording or a deliberate "Rejected" account. The test
  comments in `dogfood-launcher-test.sh` describe the new behaviour.
- **Session-check claim:** `session-start` checks only what the variable names,
  never whether that path exists (`dogfood.sh:153-166`). This bears out the
  node's claim at `:131-132`.
- **Outline decision 3, docs touched:** the hub (Requirements, D4, the new
  missing-copy decision, failed sync, the shim, `just dogfood`, Limitations
  `dist-vX.Y.Z`), the node, both READMEs, the `CLAUDE.md` Layout bullet and the
  `install.sh` Next steps step 4 are all rewritten in place. The new dated
  record and its index bullet are present. The 2026-10-03 record and its bullet
  are untouched.
- **Outline decision 4:** in `v0.9.0.md` only the closing paragraph changed.
  Steps 1-4 are byte-identical in the diff.
- **Outline decision 5:** the fallback survives, narrowed to "`just dogfood`
  cannot create the copy", verbatim in bash and fish. The fish form runs under
  fish 4.0.2; see finding 7 for zsh.
- **Prior dispositions that hold in the tree:**
  - minor 1: `dogfood.md:382-384`, and the manual's "a launch is unaffected";
  - minor 2: the `CLAUDE.md` bullet has no "names";
  - minor 3: manual Conventions say `🔖 X.Y.Z`;
  - minor 4: corrected at record `:55-58`;
  - minor 5: manual Launching, "any other `claude` you run in the repo";
  - minor 6: fallback given verbatim;
  - minor 7: the `CLAUDE.md` wrap is joined;
  - outside the range: hub `:265`.

  The only remaining `update-plugin-dev vX.Y.Z` is
  `docs/references/distribution.md:257`, a past-tense account, as the
  disposition says.
- **Migration order:** for 0.8.x to 0.9.1, `update.sh` prints `v0.9.0.md` and
  then `v0.9.1.md`. The notes are coherent in that order (see finding 8 for the
  hand-read path).
- **Fresh install:** `install.sh` Next steps step 3 points at Setup, which
  ignores the copy, before step 4 runs `just dogfood`. That is the order
  `sync`'s ignore check needs.
- **Suites run in the foreground, all exit 0:**
  - `tests/docs-test.sh`: cap 400; the node is 389 lines; pointers resolve.
  - `tests/doc-sync-test.sh`: 5 shared blocks; the Layout matches `toolkit/`.
  - `tests/citation-test.sh`.
  - `tests/dist-tree-test.sh`: 11 files; `migrations/v0.9.1.md` is admitted.

## Considered and dropped

- **`v0.9.0.md:3-4` "plus `just dogfood` to re-sync it".** This implies some
  other first sync. It is outside the closing paragraph, and decision 4 limits
  the edit to that paragraph, so it is settled. In the printed sequence, the
  0.9.1 note follows and supplies the first `just dogfood`.
- **The `CLAUDE.md` bullet says the variable is "set to `dist/plugin/`".** The
  code exports `<root>/dist/plugin`, absolute and without the slash.
  `dist/plugin/` is the directory's name throughout the docs, and
  `session-start` strips trailing slashes. No plausible misreading.
- **No doc states that exit 1 beats 127 when both conditions hold.** The
  precedence is decided and tested. A consumer never needs it, because each
  message is self-describing.
- **Node `:131-132`, "nothing would say so", about a session with no copy.**
  Whether Claude Code itself warns about a `CLAUDE_CODE_PLUGIN_DIRS` entry that
  does not exist is unprobed. The memory note covers only the warning for a
  relative entry. The refusal is right either way, so the decision does not rest
  on it.
- **Requirements and node say only `just dogfood` promotes, while
  `dogfood.sh sync` also syncs.** The recipe is a one-line wrapper, and the
  node's sandbox-mask bound names both.
- **`.claude/handoff-*.md` still describe the 0.9.0 state ("399 of 400").**
  These are volatile session files, not deliverables.
- **A zsh alias for `claude` defeats the shim outright.** An alias beats PATH,
  and the `SessionStart` check would warn. This is outside the range.

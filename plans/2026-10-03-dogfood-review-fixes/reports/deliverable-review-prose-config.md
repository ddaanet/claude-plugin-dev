# Deliverable review, Layer 1: prose and configuration (dogfood review fixes)

## Scope

- **Range:** `git diff f7a9bcf^..HEAD` (f7a9bcf through 4c6c643), limited to
  these files: `docs/design.md`, `docs/references/dogfood.md`,
  `docs/changelog.md`, `docs/changelog/2026-10-03-dogfood-review-fixes.md`,
  `toolkit/README.md`, `README.md`, `toolkit/migrations/v0.9.0.md`, `CLAUDE.md`,
  the Next steps lines of `toolkit/install.sh`, `toolkit/VERSION` and the
  `memory` gitlink.
- **How I read them:** each doc whole at HEAD, not only its hunks.
- **What I checked the claims against:** the code at HEAD (`toolkit/bin/claude`,
  `toolkit/dogfood.sh`, `toolkit/install.sh`, `toolkit/release.just`,
  `toolkit/release.sh`), the test fixtures the changelog record cites, and
  `probe-hooks.md`. I also checked the deliverable-review code sub-report's m2
  evidence and the consumer release history in `handoff` and `gitmoji`, read
  only.
- **Baseline:** the outline's decisions (Major 1 rule, Major 2 as a test gap,
  m12 move, the settled out-of-scope items) are my human partner's and are not
  findings.
- **Settled material I read and excluded:** `review-code.md`, `review-docs.md`,
  `tdd-audit.md`, `preflight-v0.9.0.md` and every `item-*.md` in this job's
  `reports/`.

## Findings by severity

### Critical

None.

### Major

None.

### Minor

1. **The node says only `just dogfood` can sync under the command sandbox. The
   new rule lets an agent-run `claude` sync there too.**
   - **Location:** `docs/references/dogfood.md:392-394`. The manual's echo of
     the claim is at `toolkit/README.md:280-281`.
   - **Axis:** accuracy, and consistency with the node's own effects list
     (`dogfood.md:124-129`).
   - **What it says:** "It bites only a `just dogfood` run through an agent's
     sandboxed Bash — the shim runs in the human's shell". m2 rewrote this
     paragraph and kept the sentence.
   - **Why it is wrong:** under the Major 1 rule, the shim syncs whenever the
     variable is not exactly this repo's copy. That includes an agent's Bash in
     a session that was started past the shim but from the direnv shell, where
     `plugin-dev/bin` is on PATH and the variable is unset. Two ways to get such
     a session:
     - the absolute-path fallback this very pass documents (`toolkit/README.md`
       Launching, migration note closing paragraph);
     - gitlore's launcher invoked by hand.
   - **Failure scenario:**
     1. In such a session, the agent runs `just prerelease`.
     2. Each gitlore eval's `claude -p` reaches the shim inside the sandbox and
        syncs.
     3. Each of those syncs copies the zero-byte masks, so an empty `.mcp.json`
        lands in the copy of a plugin that ships none.
     4. A maintainer who trusts "only `just dogfood`" does not look for that
        source.
   - **Fix:** scope the sentence to "a sync run in an agent's sandboxed Bash,
     whether `just dogfood` or a `claude` the agent starts outside a dogfood
     session of this repo".
   - **Constraint:** the node is at 399 of 400 lines, so the fix must replace
     words, not add a line.

2. **The manual never says that every `claude` subcommand typed in your own
   shell promotes.**
   - **Location:** `toolkit/README.md:216-224` (Launching) and `:242-244`
     (Promoting changes).
   - **Axis:** completeness and usability, and consistency with the node.
   - **What the node says:** "Every `claude` that reaches the shim is a launch
     to it, whatever its arguments: `claude --version`, `claude mcp …`"
     (`dogfood.md:113-114`).
   - **What the manual says:** only that "a launch from a plain shell syncs". A
     maintainer does not read `claude mcp list` as a launch.
   - **Failure scenario:**
     1. A maintainer is editing a hook script in a live dogfood session.
     2. From a second terminal, they run `claude --version` or
        `claude mcp list`.
     3. That command re-promotes the half-edited hook into the live session,
        which is the exposure the launcher exists to prevent.
     4. The manual gave no warning. The behaviour itself is my human partner's
        decision; only its documentation for the consumer is missing.
   - **Fix:** one clause in the Launching list: "any `claude` command,
     `claude --version` and `claude mcp …` included".

3. **"Names that copy" in CLAUDE.md and the changelog index is the
   `session-start` match, not the shim's.**
   - **Location:** `CLAUDE.md:48-49` ("unless `CLAUDE_CODE_PLUGIN_DIRS` already
     names that copy") and `docs/changelog.md:15`, the 2026-10-03 bullet
     ("already names its own copy").
   - **Axis:** accuracy and consistency.
   - **What the code does:** `toolkit/bin/claude:27` skips the sync only on
     whole-value equality. A `:`-list that carries the copy among other entries
     syncs, and the node (`dogfood.md:128-129`), the hub (`design.md:244`) and
     the manual (`toolkit/README.md:216`) all say "equals".
   - **Why "names" misleads:** in this codebase, "names" is the word for
     `session-start`'s rule, where any whole `:`-entry matching counts.
   - **Failure scenario:**
     1. An agent maintaining the shim reads the Layout bullet as the contract.
     2. It "aligns" the shim with `session-start`'s entry split.
     3. The suite's list-valued scenario then reds, so the cost is a wasted
        cycle, not a shipped bug.
   - **Fix:** "already equals that copy" in CLAUDE.md. The index bullet is a
     dated record entry, so whether to touch it is a call for my human partner.

4. **The shipped manual's release-subject convention contradicts the fact this
   pass recorded in CLAUDE.md.**
   - **Location:** `toolkit/README.md:308-309`. It reads: "Release commit
     message: `release: X.Y.Z` (gitmoji hook maps it to `🔖 release X.Y.Z`)".
   - **Axis:** consistency and accuracy.
   - **What is true:** 4c6c643 made CLAUDE.md say that the hook lands the commit
     as `🔖 X.Y.Z`. The consumer flow commits the same `release: $V`
     (`toolkit/release.sh:663`) through the same hook. Consumer history shows
     the bare form: `handoff` has `🔖 0.14.0` and `🔖 0.13.1`, and `gitmoji` has
     `🔖 0.5.1`.
   - **Failure scenario:**
     1. A consumer maintainer greps `git log` for `🔖 release` to list release
        commits.
     2. The grep finds none.
   - **What the preflight covered:** its note 3 dispositioned CLAUDE.md only,
     not this line.
   - **Fix:** `🔖 X.Y.Z`.

5. **The macOS sync run is reported as done, but its result is recorded nowhere
   durable, and the hub and node still say "unprobed".**
   - **Locations:**
     - `docs/design.md:293-294` (Limitation);
     - `docs/references/dogfood.md:355-359` (bound);
     - `preflight-v0.9.0.md:66-67` ("Already verified before this run: … the
       macOS `dogfood.sh sync` suites");
     - `.claude/handoff-todo.md`, which this range changed and which dropped the
       "run the sync suites on a macOS consumer" item.
   - **Axis:** consistency and completeness.
   - **Not verifiable here:** no report, record or memory file names the rsync
     that ran (openrsync or 2.6.9) or the outcome.
   - **Two readings, both of which leave a defect:**
     - if the run passed, the Limitation and the bound are now false, and a
       maintainer keeps treating macOS as a risk;
     - if it did not happen as described, the dropped todo item has lost the
       only reminder.
   - **Scope:** the run itself is out of scope per the outline. The finding is
     only that the docs and the frame now disagree, with no source for the
     preflight's claim.
   - **Fix:** record the run (which rsync, which suites, the result) in the
     node's bound and the hub's Limitation, or restore the todo item.

6. **The migration note's and manual's fallback launch is described, not given
   as a runnable command.**
   - **Location:** `toolkit/migrations/v0.9.0.md:54-57` and
     `toolkit/README.md:228-231`. They say: "the first line of `which -a claude`
     that does not end in `plugin-dev/bin/claude`".
   - **Axis:** usability. Commands for a human should be verbatim-runnable.
   - **Failure scenario:** the reader is a maintainer whose `claude` just
     refused to start. They have to compose the command by hand at exactly the
     moment the tooling has failed them.
   - **Fix:** a one-liner works in bash, zsh and fish:
     `"$(which -a claude | grep -v '/plugin-dev/bin/claude$' | head -n1)"`. Fish
     users need `(…)` in place of `"$(…)"`, so either give both forms or keep
     the prose and add the bash form beside it.

7. **The changelog record overstates the m2 probe.**
   - **Location:** `docs/changelog/2026-10-03-dogfood-review-fixes.md:74-76`. It
     says "a sandboxed `just dogfood` was probed to copy a zero-byte sandbox
     mask".
   - **Axis:** accuracy, and consistency with the node.
   - **What was actually probed:** the evidence (`deliverable-review-code.md`
     m2) is a simulated mask (`: > .mcp.json && chmod 444`) followed by
     `bash plugin-dev/dogfood.sh sync`, not a sandboxed `just dogfood`. The node
     gets this right: "probed with a simulated mask on rsync 3.5.0".
   - **Impact:** low. The evidence chain reads one step stronger than it is.
   - **Fix:** this pass's own record. If it is still open to correction, "probed
     with a simulated zero-byte mask".

8. **A stray hand-wrap in CLAUDE.md.**
   - **Location:** `CLAUDE.md:143-144`, where "cuts the" sits alone on a line.
     4c6c643 introduced it, and `format-docs` does not cover CLAUDE.md.
   - **Axis:** style.
   - **Impact:** none when rendered. Re-flow the paragraph.

### Unprobed observation (no severity)

- **Premise:** the Major 1 fix rests on a Bash-tool child of a dogfood session
  seeing `CLAUDE_CODE_PLUGIN_DIRS` byte-identical to what the shim exported. The
  docs state it as fact: `dogfood.md:121-122` and `toolkit/README.md:217-218`
  ("passes to everything it starts").
- **Evidence for it:**
  - `probe-hooks.md` observed hooks receiving the exact value;
  - the bundle reading says Claude Code writes the normalized value back into
    its own environment.
- **What is unprobed:** a Bash-tool child, under the command sandbox, has not
  been observed.
- **Why it matters:** if the value differs (normalization, sandbox env
  filtering), the fix silently does nothing. Every nested `claude -p`
  re-promotes, and nothing reports it.
- **Cheapest settlement:** the planned same-day dogfood. In a dogfood session,
  have the agent run `printf '%s\n' "$CLAUDE_CODE_PLUGIN_DIRS"` and check that a
  nested `claude -p` leaves `dist/plugin/`'s mtime untouched.

### Outside the range (not a finding of this deliverable)

- `docs/design.md:267-269` still says each consumer "must run
  `just update-plugin-dev vX.Y.Z`". A bare `vX.Y.Z` ref is refused; the dist
  form is `dist-vX.Y.Z`. This text predates the range, and this pass did not
  make it false.

## Checks that passed

- **Outline conformance, docs half.** Every item is present:
  - Major 1 is rewritten in place, present tense, in the hub (Requirements, D4,
    D9), the node ("Sync only on deliberate promotion" plus its subsection, "The
    shim", "Children inherit the variable") and the manual (Contents, Launching,
    Promoting changes). The front page needed nothing for Major 1.
  - m2: the node's bound is settled as probed, and the manual's advice is no
    longer scoped to plugins that ship `.mcp.json`.
  - m4: `install.sh`'s Next steps step 3, and both READMEs after the Commit
    block, outside the shared fenced blocks.
  - m5 and m6: the migration note's step 2, rsync named in the intro, and the
    fallback paragraph.
  - m7: commands, `.mcp.json` and output styles, with each unverified claim
    marked as such.
  - m8: the hub's Motivation and the front page.
  - m9: "four repositories".
  - The changelog record and its index bullet, newest first.
- **Code accuracy.** Each of these matches the code at HEAD:
  - the shim's skip condition: a quoted whole-value compare against the `cd -P`
    root;
  - export in every case;
  - the exact not-started line, after the sync's stderr, with the sync's status
    (`exit "$status"`);
  - `pre-tool` exits 1 on either `jq` failure (`|| exit 1` on both calls);
  - the `jq` 1.6 claim is marked "read from its source, not probed".
  - The hub's D8 and D9 bullets, the node's "Sync failure is loud" and "The
    shim", and the manual's Launching all say the same.
- **Migration note.**
  - A missing rsync makes the sync exit 127 under `set -e`, which reaches the
    shim's non-zero branch, so the note's claim holds.
  - Steps 2 and 4 are idempotent as written.
  - `grep -n '\.bin' .envrc justfile` surfaces the lines that step 2 talks
    about.
- **The changelog record's test claims.** Each holds at HEAD:
  - the Major 2 fixture (`tests/dogfood-sync-test.sh:161-178`: `/build.log`,
    tracked `skills/demo/build.log`, and root names beginning `- ` and `+ `);
  - the m11 decoy (`tests/dogfood-launcher-test.sh:234-245`);
  - the m12 claim that the session-start suite had no
    invoked-through-a-symlinked-repo case before. At f7a9bcf its only symlink
    case spelled the variable through a link.
- **Anchors.** `#dogfooding` and `#setup` resolve: there is one `### Setup` in
  `toolkit/README.md`. The front page links to `toolkit/README.md#setup`.
- **Suites run in the foreground at HEAD, all rc 0:**
  - `docs-test.sh` (cap 400, pointers resolve);
  - `doc-sync-test.sh` (5 shared blocks, Layout matches `toolkit/`);
  - `citation-test.sh`;
  - `dist-tree-test.sh` (11 files);
  - `install-test.sh`;
  - `dogfood-launcher-test.sh`.

  The tracked tree was unchanged afterwards.
- **Living-doc rules.**
  - The hub and node are present tense, with no strike-through and no narrated
    history; the history is in the dated record only.
  - The record and the frame say "my human partner".
  - Recipe doc comments in `release.just` are single-line.
  - The `install.sh` Next steps lines are plain `echo` with no backticks.
- **`toolkit/VERSION` is not anomalous.**
  - It reads 0.9.0.
  - The release commit 0ca385f changes only that file and carries the `v0.9.0`
    tag.
- **The `memory` gitlink is not anomalous.**
  - 4c6c643 moves it from e931f5e, the commit `v0.9.0` pins, to 01a5e88.
  - 01a5e88 descends from e931f5e and is contained in memory's `origin/live`.
  - The dist tree carries no gitlink.

## Settled items confirmed and skipped

- **`docs/references/dogfood.md` near the cap.** It is at 399 of 400 lines,
  confirmed with `wc -l`, and is not re-reported. It does constrain the fix for
  minor 1.
- **Unprobed questions recorded as unprobed.** These are not re-reported:
  - hooks firing twice in the gitlore evals;
  - an empty plugin-root `.mcp.json`;
  - the `/reload-plugins` scope for commands, `.mcp.json` and output styles;
  - the `jq` 1.6 status.
- **Release-commit gitmoji subject (preflight note 3).** CLAUDE.md now carries
  `🔖 X.Y.Z`, verified against `git log` (`🔖 0.9.0`). Minor 4 is the separate,
  unraised manual line.
- **Stale handoff frame (preflight note 2).** 4c6c643 refreshed it, so it is not
  re-reported. Minor 5 concerns only the macOS item it dropped without a durable
  record.
- **`review-docs.md` fixes, each verified at HEAD:**
  - the CLAUDE.md Layout bullet states the condition (its wording is minor 3);
  - the node's migration summary follows m5 (`dogfood.md:311-314`);
  - the A→B wording is in the node (`:127`) and the record (`:28-29`);
  - the hub's D4 says "of the same repository" (`design.md:222`, `:225`);
  - the manual's failed-sync paragraph is re-wrapped.
- **`item-2-1.md` and `item-2-2.md` claims, each verified at HEAD:**
  - the Next steps text and `$TOOLKIT_PREFIX`;
  - the m5 and m6 wording;
  - the m7 unverified markers;
  - the m4 paragraph outside the fenced blocks, with `doc-sync-test.sh` green.
- **Outline-settled, out of scope:** the v0.9.0 minor bump, no explicit symlink
  refusal, the 80-column README reflow, the nested `CLAUDE.md` and
  case-insensitive APFS observations.

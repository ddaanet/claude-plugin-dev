# Item 2.2 — manuals, install pointer and migration note

Prose follow-through of the deliverable review's Major 1, m2, m4, m5, m6, m7 and
m8 into the shipped manual, the front page, `install.sh`'s closing output and
the v0.9.0 migration note. Wording follows the hub and node as amended in Item
2.1 and the shim as it now behaves (`git diff f7a9bcf..HEAD -- toolkit/`).

## Changes per file

### `toolkit/README.md`

- **Major 1.**
  - The Contents bullet for `bin/claude` says the shim syncs "unless it runs
    inside a dogfood session of the same repo".
  - Launching has a new paragraph: the sync is skipped when
    `CLAUDE_CODE_PLUGIN_DIRS` already equals `<root>/dist/plugin`. It is
    followed by a three-item list:
    - a launch from a plain shell syncs, `claude -c` included;
    - a `claude` run inside a dogfood session of the same repo, such as an
      agent's `claude -p`, skips the sync;
    - a `just prerelease` run from your own terminal syncs on each `claude -p`
      it starts.
  - Promoting changes no longer says "Every launch through the shim promotes".
    It now says that a launch from your own shell promotes, and that a `claude`
    run inside the session does not, linking Launching.
- **m3 wording (the failed-sync line).** In Launching, "A failed sync aborts the
  launch" now names the line that follows the sync's own errors,
  `dogfood: sync failed, so claude was not started`, and says the shim exits
  with the sync's status.
- **m6 (manual side).** The same Launching paragraph gives the fallback while
  the sync stays broken. Start a session from the repo root by the next
  `claude`'s absolute path, which is the first line of `which -a claude` that
  does not end in `plugin-dev/bin/claude`. That session does not load the copy,
  and the `SessionStart` check says so. The prose sub-report's m2 named the
  manual's Launching (`toolkit/README.md:204-209`) as lacking this.
- **m2.** The `.mcp.json` paragraph used to open "If your plugin ships a
  `.mcp.json`".
  - It now opens with the rule, "whether or not your plugin ships a
    `.mcp.json`".
  - It names both mask shapes as the node settles them:
    - a character-device mask is skipped with `skipping non-regular file` and
      leaves the old `.mcp.json` stale;
    - a zero-byte mask is copied as an empty file, an empty `.mcp.json` landing
      in a plugin that ships none, and stays until the next sync from your
      shell.
  - It states that how Claude Code reads an empty `.mcp.json` is unverified,
    matching the node's "unprobed".
- **m4.** After the Installing section's Commit block, one paragraph sits
  outside every fenced block. It points at [Dogfooding](#dogfooding) →
  [Setup](#setup) and says why: the `SessionStart` check warns on every session
  until the shim is on PATH, and the sync refuses until git ignores the copy.
- **m7.** The "what goes live" list gains two items:
  - **Commands:** read at session start, so a relaunch through the shim makes
    them live. Whether `/reload-plugins` does too is unverified.
  - **`.mcp.json` and output styles:** whether `/reload-plugins` picks them up
    is unverified. A relaunch through the shim does, since it re-reads
    everything Claude Code reads at start.

### `README.md`

- **m8.** "Why it exists" gains a paragraph on the third problem, matching the
  hub's Motivation in substance:
  - every file under a loaded plugin root is sensitive, so a self-loaded plugin
    prompts on every agent edit;
  - whatever is on disk runs, so a half-edited hook script runs in the session
    editing it;
  - hand-copied launcher shims drifted the way the release recipes had;
  - the shim loads a synced copy that only a deliberate promotion changes.

  The link to `docs/design.md` moved into a paragraph of its own after it.
- **m4.** After the Commit block, a paragraph points at the manual's
  `toolkit/README.md#dogfooding` → `#setup`, with the same reason as the manual.
- **Major 1.** The front page does not state when the shim syncs. Its two
  bullets say only that the shim "loads the plugin from a synced copy" and that
  `just dogfood` "re-syncs that copy mid-session". Nothing there needed changing
  for Major 1.

### `toolkit/install.sh`

- **m4.** The Next steps output gains a third step, after the commit, made of
  plain `echo` lines with no backticks:

  ```text
    3. Set up the dogfood launcher: plugin-dev/README.md, section
       Dogfooding, subsection Setup. Until then the SessionStart check
       warns on every session.
  ```

  The path comes from `$TOOLKIT_PREFIX`.
- `tests/install-test.sh` does not pin the Next steps text. It asserts only the
  "already installed, nothing to do" report, so it was left unchanged.

### `toolkit/migrations/v0.9.0.md`

- **m5.** Step 2's prose was rewritten:
  - delete the `.envrc` `PATH_add .bin` line and its comment;
  - in `justfile`, remove the `.bin` reference from each line the `grep` lists,
    whether it is `.bin/claude` or a `.bin/*` glob;
  - delete the line only when that reference is all it checks.

  The step then names both failure modes for a `shellcheck` or file-list line
  that names `.bin/*` beside other paths:
  - left in, the glob matches nothing once `.bin/` is gone, and the check fails
    on it;
  - deleted with its line, the other paths lose their check.

  The line shapes are described generically, and no consumer repository is
  named.
- **m6.**
  - The intro now says "The sync needs `rsync` on PATH."
  - A closing paragraph explains the consequence:
    - from step 3 on, every `claude` typed in the repo goes through the shim;
    - a failed sync, `rsync` missing among the causes, aborts with the
      `dogfood: sync failed, so claude was not started` line;
    - the fallback is the next `claude`'s absolute path, using the same
      `which -a claude` rule as the manual;
    - that session does not load the copy, and its `SessionStart` check says so.
  - A missing `rsync` makes `dogfood.sh sync` exit non-zero (status 127 from the
    shell). The shim prints its line on any non-zero sync status
    (`toolkit/bin/claude`'s `if ((status != 0))` branch).

## Sources for the m7 facts

- **Skill bodies after `/reload-plugins`; agent definitions and hook events only
  in a new session; `claude -c` a full restart.** These were already in the
  list. Source: `plugin-craft:verifying-plugin-changes` 0.1.3:
  - "Fix for a skill body: `/reload-plugins`", scoped there as "verified for
    skill bodies only";
  - hook event registration "frozen";
  - "`claude -c` is a full restart … Everything frozen at process start is
    re-read on a resume".
- **Commands read at session start, so a relaunch makes them live.** Source:
  `memory/ddaanet/cc-agent-discovery.md`. It says edits to `agents/<name>.md` or
  `commands/<plugin>/<name>.md` after session start "do NOT take effect … the
  harness reads them at start", and that a restart is needed. The relaunch half
  rests on the `claude -c` full-restart finding above.
- **Commands under `/reload-plugins`: unverified.** No source tested it. The
  skill's `/reload-plugins` claim is scoped to skill bodies, and
  `cc-agent-discovery` records the restart only.
- **`.mcp.json` and output styles under `/reload-plugins`: unverified.** No
  memory file, skill or plan report covers them. A search of `memory/`, `docs/`
  and `plans/` for `reload-plugins`, `output style` and `output-styles` found
  nothing that bears on them.
- **`.mcp.json` and output styles live after a relaunch.** This is an inference
  from the `claude -c` full-restart finding: a relaunch re-reads everything read
  at start. It is stated in the manual as that reason, not as an observation.

## Inconsistency found outside scope (not edited)

The `docs/references/dogfood.md` section "The migration is a note" still
summarizes step 2 as "delete any hand-copied `.bin/claude`, its `PATH_add`, and
any recipe line naming it". After m5 the note removes the `.bin` reference and
deletes a line only when that reference is all it checks. The node's summary
should follow. It belongs to Item 2.1's scope, `docs/references/`.

## Verification

- `just format-docs`, then `just precommit` in the foreground: rc 0. The
  following passed:
  - the `release.just` import check;
  - the version-guard, check-version, release, self-release and install suites;
  - `dist tree ok (11 files …)` and `docs ok (cap 400 lines, pointers resolve)`;
  - `doc sync ok (5 shared command blocks, Layout matches toolkit/)` and
    `citations ok`;
  - the dogfood sync, sync-refusal, pre-tool, session-start and launcher suites.

  No flake occurred in this run.
- The prose lines in the three edited markdown files are at most 80 characters,
  excluding fenced blocks, matching the hand wrap already in use. `format-docs`
  does not run over the READMEs or `toolkit/migrations/`.
- The Next steps output was checked by evaluating its `echo` lines with
  `TOOLKIT_PREFIX=plugin-dev`. It prints as shown above.

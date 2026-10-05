# Deliverable review, Layer 1: code and tests

## Scope

- **Range:** `git diff f7a9bcf^..HEAD` (`f7a9bcf` through `4c6c643`).
- **Files, each read whole at HEAD and as a diff:**
  - `toolkit/bin/claude`
  - `toolkit/dogfood.sh`
  - `toolkit/install.sh` (the Next steps `echo` lines, as shell code)
  - `tests/dogfood-launcher-test.sh`
  - `tests/dogfood-pre-tool-test.sh`
  - `tests/dogfood-session-start-test.sh`
  - `tests/dogfood-sync-test.sh` (Major 2's fixture, which landed in `f7a9bcf`)
- **Baseline:** `plans/2026-10-03-dogfood-review-fixes/outline.md`. The ids come
  from
  `plans/2026-09-26-dist-copy-dogfood-launcher/reports/deliverable-review.md`.
- **Environment:** GNU bash 5.2.37, jq 1.7, rsync 3.5.0, Linux.
- **Mutations and probes:** run only in a `git archive HEAD` extract or in
  scratch fixtures under `$TMPDIR`. Both are removed. No tracked file was
  touched.

## Findings by severity

### Critical

None.

### Major

None.

### Minor

1. **The skip branch's stated beneficiary never reaches the shim. Its own PATH
   export routes a nested `claude` past it.**
   - **Location:**
     - The skip: `toolkit/bin/claude:27`.
     - The rationale for the skip: `toolkit/bin/claude:10-14`.
     - The PATH strip, which is exported to the exec'd `claude`:
       `toolkit/bin/claude:36-37`.
   - **Axes:** vacuity and functional correctness of the rationale.
   - **This is not a departure from the outline.** The code implements decision
     1 exactly. The finding is about a premise that decision 1 and the shim's
     header share.
   - **Mechanism:**
     - The shim drops every PATH entry whose `claude` is itself and exports the
       result. The suite pins this behaviour: "the shim strips its own entry in
       any spelling" asserts that 0 shim entries are left.
     - Claude Code's Bash tool inherits the launch environment's PATH. Two
       pieces of evidence support this:
       - This session's Bash PATH begins with the `.envrc` entries `.venv/bin`
         and `.gitlore/bin`. The second one survives because gitlore's launcher
         does not export its own strip.
       - `memory/ddaanet/sandbox-effects.md` records that direnv "runs in the
         launching shell".
     - So inside a dogfood session, `plugin-dev/bin` is not on the agent's PATH.
       A `claude -p` the agent runs resolves to the next `claude` (gitlore's
       launcher or the real binary) and never reaches the shim.
   - **Probe, in a scratch fixture:**
     - Setup: the shim execs a stand-in "session" `claude`. That stand-in
       deletes `dist/plugin` and then runs a nested `claude -p` by PATH lookup.
     - At HEAD: `PATH has plugin-dev/bin? no`. The nested `claude` resolves to
       the stand-in, and there is no re-sync.
     - With the pre-fix shim from `f7a9bcf`: also no re-sync.
     - Only with `plugin-dev/bin` put back on PATH does the pre-fix shim
       re-sync.
     - So for the case the header names, "a claude an agent runs inside a
       dogfood session of this same repo", the change makes no difference. The
       nested run did not promote before the change either.
   - **When the skip does fire:** only when `plugin-dev/bin` is put back on PATH
     inside a session. Examples:
     - `direnv exec`;
     - an interactive subshell with the direnv hook;
     - a script that names `plugin-dev/bin/claude` or prepends that directory;
     - a human terminal that inherited a session's environment, such as a tmux
       server or an IDE started from the session's Bash.
   - **Failure scenario for the last case:** the human types `claude` in that
     terminal. The variable already equals the copy, so the sync is skipped
     silently and the session runs the last-promoted copy. Decision 1 meant "a
     launch from a plain shell syncs", and nothing tells the human this one did
     not.
   - **Docs:** they state the same premise as mechanism. Hub D4 and the node's
     "A `claude` started inside a dogfood session does not promote" say such a
     `claude -p` "inherits the variable and skips the sync". The effect is true,
     since no sync happens, but the reason is the PATH strip, not the skip. The
     node's Risks bullet hedges with "if it reaches this repository's shim".
   - **Who notices:** nobody. The behaviour is the same in the common case.
   - **For my human partner's call:**
     - Keep the branch for the direnv and explicit-path cases, and correct the
       stated rationale.
     - Or reconsider decision 1 knowing that the agent case was already safe.
     - Either way, a one-command probe settles the premise: in a consumer's
       dogfood session, the agent runs `command -v claude; printenv PATH`.
   - **Severity:** it would be Major (vacuous) if the probe confirms that no
     common route reaches the branch. It is rated minor here because the direnv
     and explicit-path routes are real.

No other findings. Everything else I checked is listed below.

## Checks that passed

- **Suites green at HEAD:** launcher, pre-tool, session-start, sync and
  sync-refusal all exit 0 with no FAIL lines. `shellcheck` is clean on all seven
  files.
- **Major 1, outline conformance:**
  - The shim compares `${CLAUDE_CODE_PLUGIN_DIRS-}` against
    `"$root/dist/plugin"`. The right-hand side is quoted, so the match is
    literal, and `root` comes from `cd -P`, so it is physical.
  - The export happens unconditionally after the branch.
  - All three outline scenarios are present:
    - unset: syncs, and stderr is empty;
    - equal: no sync, still execs with the variable, same pid, reached through a
      symlinked spelling;
    - another path: syncs and overrides.
  - Two more scenarios pin the match: a list value and a glob-named root.
- **Wrong GREENs I considered for the shim:**
  - Not exporting on the skip path is an equivalent mutant. The inherited value
    is already exported and equal.
  - Skipping the PATH strip on the skip path would re-exec the shim forever, and
    the 10 s watchdog reds it.
  - Syncing only when the variable is unset is caught by "an inherited variable
    naming another path still syncs".
- **m3:**
  - The status is captured in the `|| status=$?` form, then there is one stderr
    line and `exit "$status"`.
  - An exit by signal passes through as 128+n.
  - The line's position after sync's stderr is forced by construction: a line
    printed before the sync could not know whether it failed, and printing it
    unconditionally reds the empty-stderr assertion.
- **m1:**
  - Both jq calls in `pre_tool` carry `|| exit 1`.
  - I re-walked every other exit path in `pre_tool`: none yields 2, which agrees
    with the item 1.2/1 code review's audit.
  - Three scenarios assert `rc == 1`:
    - real jq 1.7, which exits 5;
    - a stub exiting 2 on the payload read;
    - a stub exiting 2 on the deny build, with the payload read by the real jq.
  - Exit 1 is non-blocking for `PreToolUse`, and only exit 2 blocks.
- **m10, m11, m12:**
  - m10: every `pre-tool` payload comes from `pre_tool_payload` and carries the
    decoy `cwd`. The "path outside the repo" case sits under that decoy's
    `dist/plugin/`, so a root taken from `cwd` gives the wrong verdict both
    ways.
  - m11: the export scenario sets `CLAUDE_PROJECT_DIR` to a viable decoy.
  - m12: both halves of the case live in the session-start suite. The launcher
    suite runs only the shim.
- **Major 2 (`f7a9bcf`):**
  - Mutation: `printf '/%s\0'` changed to `printf '%s\0'` in an extract. Three
    assertions red: the tracked `skills/demo/build.log` goes missing, and
    `- dash file` and `+ plus file` get copied.
  - The outline names a root entry beginning `- ` or `#`. The fixture uses `- `
    plus `+ `, which satisfies the "or".
  - I probed `#` separately. Under `--from0`, rsync 3.5.0 reads an unanchored
    `#h` (and `;s`) as a comment and copies the file, while `/#h` is excluded.
    That is a different mechanism from the `- ` and `+ ` rule prefixes, but no
    plausible implementation fails on `#` while passing the existing three
    assertions. So leaving it out costs no mutation-killing power.
- **`install.sh` Next steps:**
  - The lines are plain literal `echo`s in the `changed` branch, consistent with
    steps 1 and 2.
  - `$TOOLKIT_PREFIX/README.md` is relative to the consumer root, where the
    script refuses to run anywhere else.
  - The named section "Dogfooding" and subsection "Setup" exist in
    `toolkit/README.md` (lines 178 and 190).
- **Repo rules:**
  - Whitespace: the stub directories hold spaces, and the consumer paths hold a
    space, a newline and `[ ]`.
  - bash 3.2: the change adds only `${VAR-}`, `(( ))`, `local` and `+=`, and the
    stubs are POSIX `sh`.
  - One script under test per suite, each with its own harness copy: holds.
  - Prefix assignments on function calls reach the child and do not persist, so
    the scenarios are independent.
- **Fixture correctness:** the launcher stub hard-codes the pre-move consumer
  path for its `copy` record. The glob-named scenario moves the consumer, but it
  asserts on `"$consumer/dist"` and not on `recorded copy`, so it is not misled.

## Settled items confirmed and skipped

These are confirmed or dispositioned in `review-code.md`, `review-docs.md`,
`tdd-audit.md`, `preflight-v0.9.0.md` and the item reports. I did not re-report
them.

- Suite lengths over 400 lines (launcher 429, pre-tool 448).
- The `install.sh` Next steps line being untested.
- RED and GREEN report bookkeeping, and item 1.3 having no test review.
- The m12 rejection half: claimed restored in `cb64414`. Verified present at
  HEAD (`tests/dogfood-session-start-test.sh:199-212`).
- The `pre_tool_payload` decoy helper and the removed redundant `unset`.
  Verified at HEAD.
- The label mismatch in "an inherited variable is overwritten".
- `usage` exits 2 only on a miswired hook subcommand.
- jq 1.6's parse-error status being read from source, not probed.
- The out-of-scope items in outline decision 4, and the outline's unprobed
  observations.
- The m10, m11, glob-root and logical-root mutation proofs. These were
  reproduced by `review-code.md` and `tdd-audit.md`, and I did not repeat them.

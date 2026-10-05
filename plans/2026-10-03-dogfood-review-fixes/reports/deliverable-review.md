# Deliverable Review: 2026-10-03-dogfood-review-fixes

**Date:** 2026-10-04 **Methodology:** edify `deliverable-review` skill (two
layers). The node `docs/references/deliverable-review.md` it cites is not
shipped in edify 0.3.0, so the axes and severity levels are the ones the skill
body states.

- **Baseline:** `plans/2026-10-03-dogfood-review-fixes/outline.md`. It has no
  runbook; the item map is `reports/build-summary.md`.
- **Range:** `f7a9bcf^..HEAD`. That covers `f7a9bcf` (Major 2's anchor fixture,
  landed before the build) through `4c6c643`, and includes the 0.9.0 release
  commit `0ca385f`.
- **Range source:** `edify-review-range.sh` printed `NO-PROVENANCE:`. The range
  above is the one the dispatch named.
- **Already-settled material:** `review-code.md`, `review-docs.md`,
  `tdd-audit.md`, `preflight-v0.9.0.md`, and the `item-*` reports. Read in full.
  Nothing they raised and resolved or dispositioned is reported again.

## Inventory

| Type | File | +/- |
|---|---|---|
| Code | `toolkit/bin/claude` | +17/-2 |
| Code | `toolkit/dogfood.sh` | +10/-7 |
| Code / config | `toolkit/install.sh` (Next steps output) | +3 |
| Test | `tests/dogfood-launcher-test.sh` | +90/-12 |
| Test | `tests/dogfood-pre-tool-test.sh` | +74/-10 |
| Test | `tests/dogfood-session-start-test.sh` | +22 |
| Test | `tests/dogfood-sync-test.sh` (`f7a9bcf`) | +24 |
| Human docs | `docs/design.md` | +25/-9 |
| Human docs | `docs/references/dogfood.md` | +77/-24 |
| Human docs | `docs/changelog.md` | +7 |
| Human docs | `docs/changelog/2026-10-03-dogfood-review-fixes.md` | +98 |
| Human docs | `toolkit/README.md` | +42/-9 |
| Human docs | `README.md` | +18/-2 |
| Human docs | `toolkit/migrations/v0.9.0.md` | +17/-6 |
| Agent instructions | `CLAUDE.md` | +8/-4 |
| Config | `toolkit/VERSION` (0.8.0 to 0.9.0) | +1/-1 |
| Config | `memory` gitlink | +1/-1 |

That is 672 changed lines outside `plans/`. Layer 1 ran as two opus agents: one
for code and tests, one for prose and config.

**Design conformance.** Every outline Work item has a deliverable, and the code
implements decisions 1–3 as worded:

- the skip is a quoted whole-value compare against the `cd -P` root;
- the variable is exported in every case;
- the not-started line comes after the sync's stderr, and the shim exits with
  the sync's status;
- both `jq` calls in `pre_tool` end in `|| exit 1`;
- the m12 move is complete.

Run in the foreground at HEAD, all exit 0 with no FAIL lines:

- the five dogfood suites;
- `doc-sync`, `docs`, `install`, `dist-tree` and `citation`;
- `shellcheck` on the seven code and test files.

`just precommit` was not run, because its `whitespace` and `format-docs` steps
write to the tree.

## Critical Findings

None.

## Major Findings

1. **The skip's stated beneficiary never reaches the shim. The recorded
   rationale for decision 1 describes a mechanism the code does not exercise.**
   - **Locations:**
     - The skip: `toolkit/bin/claude:27`. Its rationale is the header at
       `toolkit/bin/claude:10-14`.
     - The strip: `toolkit/bin/claude:36-37`. It *exports* a PATH with every
       entry whose `claude` is the shim removed.
     - The rationale repeated in the docs:
       - `docs/design.md:221-227` (D4);
       - `docs/references/dogfood.md:111-129`;
       - `toolkit/README.md:216-222` and `:242-244`;
       - `CLAUDE.md:48-51`;
       - `docs/changelog/2026-10-03-dogfood-review-fixes.md:12-20` and `:26-29`.
   - **Axes:** vacuity (code), accuracy (docs).
   - **Not a contest of the decision.** The code implements decision 1 exactly.
     The finding is about the premise the deliverable states for it.
   - **Mechanism:**
     - The session `claude` the shim execs inherits the stripped PATH, and so
       does the session's Bash tool. Evidence from this session: its Bash PATH
       opens with the direnv entries `.venv/bin` and `.gitlore/bin`, inherited
       from the launching shell, and `DIRENV_DIR` is set. `.gitlore/bin`
       survives only because gitlore's launcher strips its own directory into a
       local, unexported `newpath`.
     - So inside a dogfood session `plugin-dev/bin` is not on the agent's PATH.
     - gitlore's eval runner calls `claude` by PATH lookup
       (`/Users/david/code/gitlore/tests/evals/lib/claude-runner.sh:64`). An
       agent's `just prerelease` therefore reaches gitlore's launcher or the
       real binary, never the shim.
   - **Probe (Layer 1, scratch fixture):** a stand-in session deletes
     `dist/plugin` and then runs a nested `claude -p`.
     - At HEAD: no re-sync.
     - With the pre-fix shim from `f7a9bcf`: also no re-sync.
     - Only with `plugin-dev/bin` put back on PATH does the pre-fix shim
       re-sync.
   - **What the record and node get wrong.** "Run by an agent inside a dogfood
     session, each of those re-promoted the tree under the live session" (the
     record's opening section, and the node's Major 1 paragraph) did not happen
     on that route before the fix either. The prior review's Major 1 itself
     named the human's direnv shell, a case decision 1 deliberately leaves
     syncing.
   - **Where the skip does fire:** only where `plugin-dev/bin` comes back on
     PATH inside a session. Examples: `direnv exec`, a script that names
     `plugin-dev/bin/claude` or prepends that directory, and a shell that
     re-evaluates `.envrc` afresh. That is defence in depth, not the main guard.
   - **Failure scenario:**
     1. My human partner, or a maintainer, reads D4 and the record as saying the
        variable check is what stops nested agent runs from promoting.
     2. They weigh the patch release, the consumer rollout, and any future
        change to the strip, such as making it local the way gitlore's launcher
        does, against a mechanism that is not the one at work.
     3. The docs also teach consumers (`toolkit/README.md:221-222`) that an
        agent's `claude -p` "skips the sync". That outcome is true, but for a
        reason they cannot see.
   - **Settle cheaply first.** In a consumer's dogfood session, have the agent
     run
     `command -v claude; printenv PATH | tr : '\n' | grep -c plugin-dev/bin`. A
     `0` confirms the finding.
   - **Then reword the rationale** in the shim header, hub, node, manual,
     `CLAUDE.md` and the record. The record is this job's own, but it is a dated
     record, so editing it is my human partner's call. The node is at 399/400,
     so the rewording must replace words, not add lines.
   - **Source:** Layer 1 code report, minor 1, re-rated here. Layer 2 verified
     the exported strip at `f7a9bcf` and HEAD, the inherited direnv PATH, and
     gitlore's PATH-lookup invocation. The rating is Major because the
     deliverable's central change and five documents rest on the stated premise.

## Minor Findings

### Accuracy and consistency

1. **The node scopes sandbox-mask exposure to `just dogfood` alone.**
   - **Location:** `docs/references/dogfood.md:392-394`, echoed at
     `toolkit/README.md:280-281`.
   - **What it says:** "It bites only a `just dogfood` run through an agent's
     sandboxed Bash — the shim runs in the human's shell".
   - **Why it is too narrow:** a session started past the shim from the direnv
     shell keeps `plugin-dev/bin` on PATH with the variable unset. That covers
     the absolute-path fallback this pass documents, and gitlore's launcher run
     by hand.
   - **Failure scenario:** in such a session, an agent-run `claude -p` (an
     eval's, say) syncs inside the sandbox and copies the zero-byte masks. An
     empty `.mcp.json` lands in the copy of a plugin that ships none, from a
     source the node rules out.
   - Source: Layer 1 prose report, minor 1.

2. **"Names that copy" describes `session-start`'s match, not the shim's.**
   - **Location:** `CLAUDE.md:48-49` and `docs/changelog.md:15` ("already names
     its own copy").
   - **The conflict:** the shim skips only on whole-value equality
     (`toolkit/bin/claude:27`). The hub, the node and the manual all say
     "equals". In this codebase "names" is the word for `session-start`'s
     per-entry rule.
   - **Failure scenario:** an agent maintaining the shim takes the Layout bullet
     as the contract and "aligns" it to the entry split. The list-valued
     scenario reds, so the cost is a wasted cycle.
   - Source: Layer 1 prose report, minor 3.

3. **The shipped manual still says the release subject becomes
   `🔖 release X.Y.Z`.**
   - **Location:** `toolkit/README.md:308-309`. The line predates the range
     (`6266b6a`).
   - **The conflict:** this range's `4c6c643` made `CLAUDE.md` state that the
     gitmoji hook lands `release: X.Y.Z` as `🔖 X.Y.Z`. Consumer history shows
     the bare form too: `🔖 0.14.0` in handoff, `🔖 0.5.1` in gitmoji.
   - **Failure scenario:** a consumer maintainer greps `git log` for
     `🔖 release` to list release commits and finds none.
   - **Settled material:** the preflight's note 3 dispositioned `CLAUDE.md`
     only, not this line.
   - Source: Layer 1 prose report, minor 4.

4. **The changelog record overstates the m2 probe.**
   - **Location:** `docs/changelog/2026-10-03-dogfood-review-fixes.md:74-76`. It
     says "a sandboxed `just dogfood` was probed to copy a zero-byte sandbox
     mask".
   - **What was probed:** the evidence is a simulated mask (`: > .mcp.json`,
     `chmod 444`) followed by an unsandboxed `dogfood.sh sync`, as the node
     correctly says ("probed with a simulated mask on rsync 3.5.0").
   - **Failure scenario:** a reader of the record treats the
     sandboxed-`just dogfood` path as observed end to end and skips a check it
     still needs.
   - Source: Layer 1 prose report, minor 7.

### Completeness and usability

5. **The manual never says that a `claude` subcommand typed in your own shell
   promotes.**
   - **Location:** `toolkit/README.md:216-224` (Launching) and `:242-244`.
   - **The gap:** the node says every `claude` reaching the shim is a launch,
     `claude --version` and `claude mcp …` included (`dogfood.md:113-114`). The
     manual says only "a launch from a plain shell syncs".
   - **Failure scenario:**
     1. A maintainer is mid-edit on a hook script in a live dogfood session.
     2. In a second terminal, they run `claude mcp list`.
     3. That re-promotes the half-edited hook repo-wide, with no warning in the
        manual.

     The behaviour is decided; only its consumer documentation is missing.
   - Source: Layer 1 prose report, minor 2.

6. **The broken-sync fallback launch is described, not given as a command.**
   - **Location:** `toolkit/migrations/v0.9.0.md:54-57` and
     `toolkit/README.md:228-231`. They say "the first line of `which -a claude`
     that does not end in `plugin-dev/bin/claude`".
   - **Failure scenario:** a maintainer whose `claude` just refused to start has
     to compose the command by hand, at the moment the tooling has failed. This
     goes against the repo's verbatim-runnable rule for commands meant for a
     human.
   - **Suggested form:**
     `"$(which -a claude | grep -v '/plugin-dev/bin/claude$' | head -n1)"`, with
     the fish form `(…)` given beside it.
   - Source: Layer 1 prose report, minor 6.

### Style

7. **A stray hand-wrap in `CLAUDE.md`.**
   - **Location:** `CLAUDE.md:143-144`, where "cuts the" sits alone on a line.
     `4c6c643` introduced it.
   - **Why the gate missed it:** `format-docs` covers `docs/` and `plans/`, not
     `CLAUDE.md`.
   - **Impact:** none when rendered. A reader of the raw file sees a ragged
     line.
   - Source: Layer 1 prose report, minor 8. Layer 2 found it independently.

### Considered and not raised

- **The Major 2 fixture uses `+ `, not `#`.** Decision 2 names a root entry
  beginning "`- ` or `#`", and the fixture uses `- ` and `+ `.
  - Layer 2 probed rsync 3.5.0 with `--from0`. An unanchored `#hash` or `;semi`
    is read as a comment and copied. An anchored `/#hash` is excluded.
  - That is a distinct mechanism, but the `- ` entry satisfies the decision's
    "or". The anchor-dropping mutant reds three assertions, and no plausible
    implementation fails on `#` alone. Both layers agree.
- **The macOS sync run.** The prose agent's minor 5 is dropped:
  - The preflight says the run was already done, and `4c6c643` dropped it from
    the task frame.
  - No durable record of it exists, and the hub Limitation (`design.md:293`) and
    the node bound (`dogfood.md:355`) still say "unprobed".
  - The run is outline decision 4, out of scope, and the frame is not a
    deliverable. If the run did happen, record its rsync and its result in the
    node and the hub; if not, the docs stand.
- **Unprobed: the exact value a Bash-tool child sees.** Layer 1's prose report
  raised this as an observation.
  - The premise is that a child sees `CLAUDE_CODE_PLUGIN_DIRS` byte-identical to
    the shim's export. That is now secondary to Major 1, since the child rarely
    reaches the shim at all.
  - The bundle reading (`memory/ddaanet/cc-plugin-dirs-env-var.md`) says Claude
    Code writes back the normalized list. That leaves a single physical path
    unchanged.
- **Outside the range:** `docs/design.md:267-269` still tells consumers to run
  `just update-plugin-dev vX.Y.Z`, and a bare `vX.Y.Z` ref is refused. The text
  predates this range.

## Gap Analysis

| Outline requirement | Status |
|---|---|
| Major 1 code: skip when the variable equals `<root>/dist/plugin`; export always | covered (code conforms; premise: Major 1) |
| Major 1 launcher scenarios: unset, equal, other path | covered |
| m1: `pre-tool` never exits 2 on a `jq` failure; exact status asserted | covered |
| m3: one not-started line, sync stderr kept, non-zero exit | covered |
| m10: payloads carry a foreign `cwd` | covered |
| m11: export scenario with a foreign `CLAUDE_PROJECT_DIR` | covered |
| Major 2: anchor fixture (`/build.log` vs tracked `skills/demo/build.log`, `- `/`#` root name) | covered (`- ` and `+ `; see Considered) |
| m12: symlinked `session-start` case moved, not relabelled | covered |
| Major 1 docs: D4/D9 rewritten in hub and node; manual; front page | covered; rationale inaccurate (Major 1); minor 2, 5 |
| m2: sandbox masks; manual scoping widened; Risk settled | covered; minor 1, minor 4 |
| m4: `install.sh` Next steps and both READMEs point at Setup | covered |
| m5, m6: migration note step 2, rsync, absolute-path launch | covered; minor 6 |
| m7: liveness list covers commands, `.mcp.json`, output styles | covered |
| m8: problem stated in hub Motivation and `README.md` | covered |
| m9: "four repositories" | covered |
| Dated changelog record plus index bullet | covered; minor 2, minor 4 |

No missing deliverables. One deliverable is outside the outline: `4c6c643`'s
`CLAUDE.md` release-subject note and its preflight report, which come from the
release step and explain themselves. It gave rise to minor 3 and minor 7.

## Summary

- Critical: 0
- Major: 1
- Minor: 7

Every outline item is delivered, and the code matches decisions 1–3 to the
letter. The Major finding concerns the premise: inside a dogfood session, the
shim's own exported PATH strip already keeps an agent's nested `claude` off the
shim. So the new skip branch is not what protects that case, and the rationale
written into the shim header, hub, node, manual, `CLAUDE.md` and the dated
record describes a mechanism that does not run on the route they name. One
command in a consumer's dogfood session settles it.

## Sub-reports

- `plans/2026-10-03-dogfood-review-fixes/reports/deliverable-review-code-tests.md`
- `plans/2026-10-03-dogfood-review-fixes/reports/deliverable-review-prose-config.md`

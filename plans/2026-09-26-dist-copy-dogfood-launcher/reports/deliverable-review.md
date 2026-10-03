# Deliverable Review: 2026-09-26-dist-copy-dogfood-launcher

**Date:** 2026-10-02 **Methodology:** docs/references/deliverable-review.md
(edify)

## Inventory

Range: `edify-review-range.sh` returned `389e8b02..HEAD`, which is the outline's
recorded base. The build baseline `fd16ae65` sits five commits later. The only
non-`plans/` difference between the two bases is the `memory` gitlink pointer,
so both ranges give the same deliverable set.

| Type | File | +/- |
|------|------|-----|
| Code | `toolkit/dogfood.sh` | +254 |
| Code | `toolkit/bin/claude` | +47 |
| Code | `toolkit/install.sh` | +39/-32 |
| Config | `toolkit/release.just` | +5/-1 |
| Config | `justfile` | +18/-3 |
| Test | `tests/dogfood-sync-test.sh` | +355 |
| Test | `tests/dogfood-sync-refusal-test.sh` | +244 |
| Test | `tests/dogfood-pre-tool-test.sh` | +384 |
| Test | `tests/dogfood-session-start-test.sh` | +323 |
| Test | `tests/dogfood-launcher-test.sh` | +351 |
| Test | `tests/install-test.sh` | +395 |
| Test | `tests/update-plugin-dev-test.sh` | +7/-132 |
| Test | `tests/dist-tree-test.sh` | +10/-1 |
| Human docs | `toolkit/README.md` | +215/-114 |
| Human docs | `README.md` | +92/-96 |
| Human docs | `toolkit/migrations/v0.9.0.md` | +46 |
| Human docs | `docs/design.md` | +55/-5 |
| Human docs | `docs/references/dogfood.md` | +346 |
| Human docs | `docs/references/distribution.md` | +11/-4 |
| Human docs | `docs/changelog.md`, `docs/changelog/2026-09-30-dogfood-launcher.md` | +7, +106 |
| Human docs | `CLAUDE.md` | +45/-17 |
| — | `memory` (gitlink) | pointer move, not reviewed |

There are about 3,700 changed lines, so Layer 1 ran as three opus agents: code,
tests, and prose plus config.

**Design conformance:** decisions D1–D12 are implemented as written. The Finish
code review already accepted two divergences: the PATH strip has no `paste`, and
a leaf link is resolved with `readlink -fn`. Every Item 1–6 deliverable exists.
Nothing unspecified was produced.

**Excluded:** anything Finish's `review-code.md`, `review-docs.md`,
`tdd-audit.md` and `tdd-audit-followup.md` fixed, and the residuals
orchestrator-3 lists as "Unpinned by choice". Also excluded are the decisions my
human partner has taken: v0.9.0, no explicit symlink refusal, the README reflow,
and the pending macOS run.

## Specific attention: `the shim exports the copy`

**Verdict: the strengthened scenario is sound evidence.**

- **The failing state.** It fails for the state of the world it claims to guard,
  a `<root>` that is not the shim's physical location. It reds under six mutants
  of the shim's root line. Layer 2 ran two of them, and the tests sub-report ran
  the other four.
  - **Logical `cd`:** the only failure is the export assertion, which records
    `…/link/dist/plugin`.
  - **Root from `$PWD`:** three reds — the export, the decoy `assert_absent`,
    and the session-start follow-on.
  - **`git rev-parse --show-toplevel` from the cwd:** the same three reds.
  - **cwd-relative `bash plugin-dev/dogfood.sh sync`:** the decoy
    `assert_absent` reds, and so do three other scenarios.
  - **M-GIT and M-MAN** (`tdd-audit-followup.md`): both red.
- **Reached.** Every assertion is reached. Nothing exits early, and `recorded`
  returns a marker that can never equal an expected value when the stub did not
  run.
- **Invoked as production.** The shim is found by PATH lookup through a
  symlinked `PATH_add`-style entry, not called by absolute path. It execs a stub
  found further down PATH.
- **The decoy is not vacuous.** It is a viable consumer, so a cwd-derived root
  syncs it rather than aborting. The paired `assert_absent` moves from green to
  red under every cwd mutant.

Its gaps are m11 and m12 below.

## Critical Findings

None.

## Major Findings

1. **The shim syncs and loads the copy on every `claude` it fronts, scripted
   runs included.**
   - **Location:** `toolkit/bin/claude:19-27`.
   - **Design reference:** D4, sync only on deliberate promotion.
   - **Impact.** After migration, any `claude` that a recipe or script runs from
     the user's direnv shell inside the consumer goes through the shim. That
     includes `claude --version`, `claude mcp …`, and the gitlore evals'
     `claude -p` in `tests/evals/lib/claude-runner.sh:64`, which runs under
     `just prerelease`. Each such call does two things:
     - it re-promotes the working tree, repo-wide, under every live session;
     - it exports `CLAUDE_CODE_PLUGIN_DIRS` to the copy.
   - **The gitlore evals.** They deliberately wire the plugin's hooks into the
     eval repo's `.claude/settings.json` and copy its skills in
     (`tests/evals/lib/setup.sh:53-80`). The shim's own root resolution means
     the copy is loaded into them as well. gitlore's current launcher does not
     do this: it adds `--plugin-dir .` only when the cwd holds a manifest.
     Whether the copy's hooks then fire twice under `--setting-sources project`
     is unprobed.
   - **Not covered by the Risks.** "Children inherit the variable" covers only
     children of a dogfood session. No bypass exists, and none is documented.
   - **What it needs.** A design call (venue for my human partner): either a
     shim-side opt-out or no sync for a non-interactive argv, or a documented
     rule that scripts call the next `claude`. Source: code sub-report M1, with
     the gitlore claims re-checked in Layer 2.

2. **The ignore list's leading-`/` anchor is unpinned.**
   - **Location:** `tests/dogfood-sync-test.sh` and
     `tests/dogfood-sync-refusal-test.sh`.
   - **Design reference:** D2 and runbook Item 1.1, "each entry anchored with a
     leading `/`".
   - **Impact.** Mutating `printf '/%s\0'` to `printf '%s\0'` in `sync_copy`
     leaves both sync suites green. Layer 2 reproduced this. The mutant silently
     produces a wrong copy:
     - an ignored root `/build.log` drops a tracked `skills/demo/build.log` from
       the copy, again reproduced in Layer 2;
     - an ignored root name starting `- ` is read as a filter rule, and the file
       is copied.
   - **What would pin it.** A fixture where a tracked file deeper in the tree
     shares its name with an ignored root entry, plus an ignored root name
     starting `- ` or `#`. Source: tests sub-report F1.

## Minor Findings

### Robustness and error signalling (code)

- **m1. `pre-tool` can exit with jq's status 2 under jq 1.6.**
  - **Location:** `toolkit/dogfood.sh:85-98`.
  - **Problem.** jq 1.6 exits 2 on a parse error, and an exit of 2 from a
    `PreToolUse` hook is a blocking error. The comment promises a non-blocking
    one, and jq 1.7 exits 5. The 1.6 status comes from reading the source and
    was not probed. The suite asserts only "non-zero".
  - **Trigger.** Near-hypothetical, since Claude Code sends valid JSON.
  - Source: code m1.
- **m2. A sandboxed `just dogfood` copies zero-byte sandbox masks into the
  copy.**
  - **Location:** `toolkit/dogfood.sh:56-69`.
  - **Probe.** A plugin with no `.mcp.json` gains an empty
    `dist/plugin/.mcp.json`, which stays until the next unsandboxed sync. This
    was probed with a simulated zero-byte mask; the mask in this session has
    that shape.
  - **Doc impact.**
    - The manual's "If your plugin ships a `.mcp.json`" scoping
      (`toolkit/README.md:244-248`) is too narrow.
    - The node's "zero-byte shape, unprobed" (`docs/references/dogfood.md`
      Risks) is now settled.
    - This supersedes the prose sub-report's m7, which called the manual's
      "copies an empty file" unevidenced.
  - Source: code m2.
- **m3. A failed sync at launch is not attributed to the shim.**
  - **Location:** `toolkit/bin/claude:19`.
  - **Problem.** When rsync fails, the user typed `claude` and sees only rsync's
    stderr. Nothing says that `claude` was not started.
  - Source: code m3.

### Usability and completeness (docs and install output)

- **m4. A fresh install is never pointed at the dogfood Setup.**
  - **Locations:**
    - `toolkit/install.sh:189-193`, the "Next steps" output;
    - `toolkit/README.md:61-131`;
    - `README.md:47-102`.
  - **Problem.** The `SessionStart` hook warns on every session. Following the
    warning's remedy then hits `dist/plugin/ is not git-ignored`, and only after
    that does the user find `## Dogfooding` → Setup.
  - Source: found independently by Layer 2, code m4 and prose m3.
- **m5. The migration note's step 2 does not fit the consumers' justfile
  lines.**
  - **Location:** `toolkit/migrations/v0.9.0.md:26-28`.
  - **Problem.** handoff's `shellcheck -x .bin/* bin/* …` and sandbox-lies's
    `tracked … '.bin/*'` name `.bin/*`, not `.bin/claude`. Kept, the glob fails
    once `.bin/` is gone. Deleted as told, the line takes shellcheck coverage of
    `bin/`, `scripts/` and `tests/` with it. Layer 2 verified both lines.
  - **Fix.** Remove the `.bin` reference, and delete the line only when that
    reference is all it checks.
  - Source: prose m1.
- **m6. The note never names rsync, and nothing says how to launch while the
  sync is broken.**
  - **Problem.** After step 3, a failing sync makes `claude` unlaunchable by
    name in that repo.
  - **Fix.** The next `claude` by absolute path works, and its session gets the
    correct `SessionStart` warning.
  - Source: prose m2.
- **m7. The manual's "what goes live when" list omits some component kinds.**
  - **Location:** `toolkit/README.md:227-234`.
  - **Problem.** It leaves out `commands/`, `.mcp.json` and output styles, so a
    command editor cannot tell whether `/reload-plugins` suffices.
  - Source: prose m4.
- **m8. Neither the hub nor the front page states the problem the launcher
  solves.**
  - **Locations:** `docs/design.md:14-34` (Motivation) and `README.md:12-23`.
  - **Problem.** The problem is that a self-loaded plugin prompts on every edit
    and runs half-edited hooks, and only the node and the changelog say so.
  - Source: prose m5.
- **m9. "Across four consumers" counts edify.**
  - **Location:** `docs/references/dogfood.md:104`.
  - **Problem.** edify is not a toolkit consumer. "Four repositories" is
    accurate.
  - Source: prose m6.

### Test coverage and specificity

- **m10. `pre-tool`'s payloads never carry a `cwd`.**
  - **Location:** `tests/dogfood-pre-tool-test.sh`, `run_pre_tool`.
  - **Problem.** A root taken from the payload `cwd` passes the suite, though D5
    forbids it.
  - **Fix.** Add `cwd: "$sandbox/elsewhere"` to the payload.
  - Source: tests F2.
- **m11. The launcher suite leaves `CLAUDE_PROJECT_DIR` to the runner.**
  - **Problem.** A shim preferring `CLAUDE_PROJECT_DIR` passes when the variable
    is unset. When it is set, the suite reds only by accident of setup.
  - **Fix.** Export `CLAUDE_PROJECT_DIR="$sandbox/elsewhere"` in
    `the shim exports the copy`.
  - Source: tests F3.
- **m12. The session-start follow-on in the launcher suite is mislabelled and
  tests a second script.**
  - **Mislabelled.** `session_start /elsewhere/dist/plugin` is not "another
    repo's copy". What it actually pins is the physical copy named when
    `dogfood.sh` is reached through a symlink.
  - **Second script.** That coverage, a `session-start` invoked through a
    symlinked spelling, exists only here. That runs against CLAUDE.md's "One
    script under test per suite file".
  - **Options.** Relabel it and name it as the cross-script contract check, or
    move the symlinked invocation into the session-start suite. The choice is my
    human partner's.
  - Source: tests F4 and F5.

### Unprobed observations (no severity)

- **A nested `CLAUDE.md` in the copy.** `dist/plugin/CLAUDE.md` is a copy of the
  root's. If Claude Code loads a subdirectory's `CLAUDE.md` on a Read under it,
  then reading promoted content injects a stale second copy of the project
  instructions. Source: code sub-report.
- **Case-insensitive APFS.** `<root>/Dist/Plugin/x` names the copy but passes
  the guard's case-sensitive match. Claude Code's own `ask` may still stand.
  This could not be probed on Linux. Source: code sub-report.

## Gap Analysis

| Design requirement | Status |
|---|---|
| D1 real copy, not a symlink | covered |
| D2 source set: ignore list anchored, `.git` and `/dist/plugin/` excludes, pattern-character refusal | implemented; anchor untested (Major 2) |
| D3 root layout, manifest required | covered |
| D4 sync only on deliberate promotion | implemented for sessions; scripted `claude` runs also promote (Major 1) |
| D5 root from the script's own location | covered; payload-`cwd` and launcher `CLAUDE_PROJECT_DIR` cases untested (m10, m11) |
| D6 copy guard, three-channel deny, physical paths, silent without jq | covered; jq-1.6 exit status (m1) |
| D7 session-start whole-entry match, two channels, jq notice | covered |
| D8 loud sync failure | covered; attribution at launch (m3) |
| D9 shim: sync, export, `unset CDPATH`, `-ef` strip, 127 | covered |
| D10 `just dogfood`, no gate, one-line doc comment | covered |
| D11 `install.sh` wiring, any-matcher presence, quoted commands | covered; fresh-install pointer (m4) |
| D12 migration note | present, and printed for 0.6.0 through 0.8.0 consumers; step 2 wording (m5), rsync (m6) |
| Item 1 sync suites | covered except the anchor (Major 2) |
| Item 2 pre-tool and session-start suites | covered (m10) |
| Item 3 launcher suite | covered (m11, m12) |
| Item 4 install wiring tests | covered |
| Item 5 recipe, `_import-check`, dist-tree list, precommit wiring, CLAUDE.md | covered |
| Item 6 manual, front page, hub, node, changelog | covered (m2, m7, m8, m9) |

## Summary

- Critical: 0
- Major: 2
- Minor: 12

Every specified deliverable exists and conforms to D1–D12. The two Major
findings are:
- a design gap, where the shim fronts non-interactive `claude` runs in a
  consumer;
- one test gap, where D2's anchoring could regress silently.

The specifically flagged launcher scenario holds up under six mutants.

## Sub-reports

- `plans/2026-09-26-dist-copy-dogfood-launcher/reports/deliverable-review-code.md`
- `plans/2026-09-26-dist-copy-dogfood-launcher/reports/deliverable-review-tests.md`
- `plans/2026-09-26-dist-copy-dogfood-launcher/reports/deliverable-review-prose-config.md`

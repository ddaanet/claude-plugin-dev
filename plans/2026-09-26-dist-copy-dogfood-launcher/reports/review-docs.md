# Review: dogfood launcher, documentation group (Items 3.2–3.6)

**Scope**: `toolkit/README.md`, `README.md`, `toolkit/migrations/v0.9.0.md`,
`docs/design.md`, `docs/references/dogfood.md`,
`docs/references/distribution.md`, `docs/changelog.md`,
`docs/changelog/2026-09-30-dogfood-launcher.md`, `CLAUDE.md`, diffed against
baseline `fd16ae65f4b244f1098b94b7ee848f5a7f74c8f2`. Checked against the shipped
code (`toolkit/dogfood.sh`, `toolkit/bin/claude`, `toolkit/install.sh`,
`toolkit/release.just`, `justfile`, `toolkit/update.sh`,
`toolkit/version-guard.sh`), runbook Phase 3 Items 3.2–3.6, outline D1–D12, and
the probe reports `research-probes.md`, `probe-hooks.md` and
`probe-subdir-hooks.md`.

**Date**: 2026-09-30

**Mode**: review + fix

## Summary

The documentation group is complete against every clause of Items 3.2–3.6 and
tells one story across manual, front page, hub, node, CLAUDE.md and migration
note. Behavioural statements match the code: warning strings, refusal
conditions, the any-matcher presence rule, the quoted dogfood commands, exit 127
and the sync's exclude set. One factual error was found in the changelog's
account of the consumers' hand-copied shims. The consumer repos were read, not
edited. Four smaller wording and width defects were also fixed.

**Overall Assessment**: Ready

Pre-review gate: `just precommit` green on the first run, with no intermittent
rerun needed.

## Issues Found

### Critical Issues

None.

### Major Issues

1. **Changelog misstates which consumer shims loaded the repo root, and which
   unset `CDPATH`**
   - Location: `docs/changelog/2026-09-30-dogfood-launcher.md`, "The consumers
     made it worse" paragraph
   - Problem: The entry said craft's, cwd-safety's and handoff's shims passed
     the repo root as the plugin root, and that only craft's unset `CDPATH`. It
     took this from the brief. The shims as they stood when the entry was
     written (read-only check of the four repos) say otherwise:
     - `craft/.bin/claude` execs `--plugin-dir "$dist"`, a copy of
       `.claude-plugin` and `skills` rebuilt at each launch. craft's commit "dev
       launcher loads a plugin copy" is dated 2026-09-26, four days before this
       entry.
     - `sandbox-lies/.bin/claude` execs `--plugin-dir "$root"` and also runs
       `unset CDPATH`.
     - handoff's and cwd-safety's exec `--plugin-dir "$root"` and do not unset
       it.
   - Fix: the entry now names cwd-safety, handoff and sandbox-lies as the shims
     that load the root, and says craft's had already moved to a copy of its
     own. It also says craft and sandbox-lies unset `CDPATH`. This corrects a
     factual error in the dated record and adds no later event.
   - **Status**: FIXED

### Minor Issues

1. **Node describes the rejected sync-on-edit design in narrative past tense**
   - Location: `docs/references/dogfood.md`, "Rejected: sync on edit"
   - Note: "re-ran the sync", "It cost", "it made", "each carried" read as
     history. CLAUDE.md requires nodes to be present-tense standing truth, and
     the history already has its place in the changelog entry. The passage now
     describes the alternative in the conditional or present ("would re-run",
     "costs", "makes", "carry"). The measured 60–108 ms figure stays, because it
     is grounded evidence.
   - **Status**: FIXED

2. **Manual's Hooks subsection says `install.sh` wires "two hooks"**
   - Location: `toolkit/README.md`, `### Hooks`
   - Note: Contents, "Installing in a plugin" step 3, the hub and the
     distribution node all say three hooks: the version-guard plus two dogfood
     hooks. Read alone, "wires two hooks" contradicts them. It now reads "wires
     two dogfood hooks into `.claude/settings.json`, beside the version-guard".
   - **Status**: FIXED

3. **Manual attributes an inherited foreign `CLAUDE_CODE_PLUGIN_DIRS` to any
   `claude` started from a dogfood session's Bash**
   - Location: `toolkit/README.md`, Session check paragraph
   - Note: A `claude` started from a dogfood session in the same repo inherits
     that repo's own copy path, so `session_start` stays silent: an entry equal
     to `$root/dist/plugin` exits 0. The warning fires only when the child runs
     in another plugin. The text now says "as a `claude` started from another
     plugin's dogfood session does". The node's "Children inherit the variable"
     bound already stated it this way.
   - **Status**: FIXED

4. **CLAUDE.md Quality gate line over width**
   - Location: `CLAUDE.md`, Quality gate paragraph, the "passed, not just the
     linters. **One script under test per suite file**…" line (89 columns)
   - Note: The Item 3.6 edit left one line at 89 columns in a file wrapped at
     about 72. It is now split at the bold span. The unchanged lines after it
     were not reflowed.
   - **Status**: FIXED

## Fixes Applied

- `docs/changelog/2026-09-30-dogfood-launcher.md`: corrected which shims loaded
  the repo root and which unset `CDPATH` (Major 1). `just format-docs` rewrapped
  the rest of that paragraph without changing its words.
- `docs/references/dogfood.md`: "Rejected: sync on edit" moved from past tense
  to conditional or present (Minor 1).
- `toolkit/README.md`: the Hooks lead-in names the two dogfood hooks beside the
  version-guard (Minor 2). The Session check wording now says "another plugin's
  dogfood session" (Minor 3). The paragraph was rewrapped to 80 columns, and
  `rumdl check` is clean.
- `CLAUDE.md`: split the 89-column Quality gate line (Minor 4).

No fenced block in "Installing in a plugin" or "Updating in a plugin" was
touched, and no script, test or justfile was edited.

## Requirements Validation

| Requirement | Status | Evidence |
|-------------|--------|----------|
| 3.2 migration note, D12 steps in order | Satisfied | `toolkit/migrations/v0.9.0.md` steps 1–4: re-run `install.sh` (from the human's shell, since the sandbox denies `.claude/settings.json`); remove `.bin/claude`, its `PATH_add .bin` and recipe lines; `PATH_add plugin-dev/bin` after `.gitlore/bin`, then `direnv allow`; ignore `/dist/plugin/`; `clean` spares it. Named for 0.8.0 → 0.9.0 (`toolkit/VERSION` is 0.8.0), and `update.sh` prints the (old, new] range. |
| 3.3 manual `## Dogfooding` | Satisfied | Setup (`.envrc`, `.gitignore`, `clean`), Launching (repo root, subdirectory hooks), Promoting (`just dogfood`, `/reload-plugins` vs a restart, lag by design, `.mcp.json`), Hooks (both warnings, verbatim against `session_start`'s strings). Contents gains `dogfood.sh` and `bin/claude`; the `release.just` and `install.sh` bullets are updated; Requirements lists `rsync`; step 3 prose names both dogfood hooks. |
| 3.4 front page | Satisfied | Opening summary names the shim. "What a consumer plugin gets" has shim and `just dogfood` bullets linking the manual's `#dogfooding`. Install prose names the dogfood hooks, and Requirements lists `rsync`. The shared fenced blocks are unchanged and `doc-sync-test.sh` is green. |
| 3.5 hub, node, distribution, changelog | Satisfied | The hub has a Requirements bullet, a Motivation line, the Distribution `install.sh` bullet with the any-matcher rule, a 12-bullet decision group (D1–D12) linking `references/dogfood.md`, and Limitations for the subdirectory launch and macOS rsync. The node carries the D1–D12 arguments, the sync-on-edit rejection, the Q3 and subdirectory probes on CC 2.1.284, and the six surviving Risks. `distribution.md` says three hooks and gives the any-matcher rule. The changelog entry is dated 2026-09-30 and indexed. |
| 3.6 CLAUDE.md | Satisfied | Layout bullets for `dogfood.sh` and `bin/claude`. The `release.just` bullet names `dogfood`, and the `install.sh` bullet names the dogfood hooks. Quality gate names `install-test.sh`, the four `dogfood.sh` suites and `dogfood-launcher-test.sh`. The node list gains `dogfood`. The Conventions bullet covers `pretool_cmd` and `session_cmd` and why `hook_cmd` stays unquoted. |

**Gaps:** none.

## Positive Observations

- The manual's two warning lines are byte-for-byte the strings `session_start`
  emits, less the ANSI reset.
- The node's physical-path and dangling-leaf description matches `pre_tool` and
  `physical_path` exactly, the stated non-refusal of a Write through a dangling
  link included.
- The node states the version-guard's unquoted-command rationale in the same
  terms as `add_hook`'s `select(.command == $cmd)`, and CLAUDE.md does too.
- The probe claims (control and deny runs, the `PreToolUse:Edit hook error:`
  prefix, the `toolUseID`-tied attachment, `sub/deeper/` firing nothing) match
  the probe reports.
- The changelog's "departs from the outline" section records the temp-file
  exclude list, the `paste`-free PATH strip and the unbuilt Homebrew fallback,
  each true of the code.

## Recommendations

- The note name `v0.9.0` appears in `toolkit/README.md`,
  `docs/references/dogfood.md` and the changelog entry, as well as in the file
  name. If the release picks another bump, rename it in all four places.

## Final state

Line counts after `just format-docs`:

- `toolkit/README.md` 303
- `README.md` 184
- `toolkit/migrations/v0.9.0.md` 46
- `docs/design.md` 291
- `docs/references/dogfood.md` 346
- `docs/references/distribution.md` 271
- `docs/changelog/2026-09-30-dogfood-launcher.md` 106
- `CLAUDE.md` 234

Every file is under 400 lines. `rumdl check` is clean on both READMEs and the
migration note.

Final `just precommit`, run after `just format-docs`: green on the first run
(exit 0, closing `ok`), with no intermittent rerun needed.

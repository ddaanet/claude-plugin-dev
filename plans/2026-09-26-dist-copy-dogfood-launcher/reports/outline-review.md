# Outline Review: dist-copy-dogfood-launcher

**Artifact**: plans/2026-09-26-dist-copy-dogfood-launcher/outline.md
**Requirements**: plans/2026-09-26-brief-dist-copy-dogfood-launcher.md (brief:
Decisions, Constraints, Open questions) **Date**: 2026-09-26 **Mode**: review +
fix-all (PDR criteria)

## Summary

The outline is sound. It chooses one option per question, and the rsync source
set, symlink rejection and Bash-matcher decisions rest on probe evidence. Two
interface defects were real and are now fixed. The hooks read `file_path` while
also matching `NotebookEdit`, whose field is `notebook_path`. And the item 1
probe was specified to run "through the new launcher", which item 4 only builds
later. Several decisions were also under-specified in ways that fail silently: a
subdirectory launch leaves the hooks inert, a killed sync strands its lock
forever, the hook command string is not whitespace-safe, and the new suites are
never run by `precommit`. All are now fixed. The Provenance `Derived from:` is
in a form the range script does not accept. By this agent's repair rules the
`Base:` became `TODO`, and fixing `Derived from:` is left to the author.

**Overall Assessment**: Needs Iteration. The design is ready, but two new design
decisions added in review need my human partner's confirmation (the non-root
`$PWD` refusal and the stale-lock bound), and Provenance needs the author's
repair.

## Requirements Traceability

| Brief item | Outline Section | Coverage | Notes |
|---|---|---|---|
| D: load a copy, edit the source | Approach; KD1 | Complete | — |
| D: sync at launch, `rsync -a --delete` | KD2, KD8, KD10 | Complete | Adds `--delete-excluded` so newly ignored paths leave the copy |
| D: sync on edit, `PostToolUse` `Edit\|Write` | KD4, KD6 | Complete | Widened to `NotebookEdit\|Bash` plus `PostToolUseFailure`. NotebookEdit's field name fixed (Major 2) |
| D: wire like `version-guard.sh` in settings.json | KD11; item 5 | Complete | Identity key and quoting now stated (Major 5, Minor 3) |
| D: `dist/plugin/` survives `clean`; copy gitignored | KD3, KD11, KD12; item 7 | Complete | Launcher enforces the ignore; README documents `clean` |
| C: root layout, explicit source set | KD2, KD3 | Complete | `--files-from` rejected with evidence |
| C: deletions propagate, proven by a test | item 2 | Complete | Red against the naive sync |
| C: plugin root from the manifest's location | KD3 | Partial → Complete | Launcher now checks `<root>/.claude-plugin/plugin.json` (Minor 1) |
| C: compose with other shims, strip own dir | KD10; item 4 | Complete | Ordering after `.gitlore/bin` explained in KD12 |
| C: sync failure is loud | KD8, KD9 | Partial → Complete | Silent-stale paths closed: subdirectory launch (Major 3), stranded lock (Major 4) |
| C: whitespace-safe, `jq`, NUL lists | KD2, KD4, KD11 | Partial → Complete | Portable escaper (Minor 2), quoted hook command (Major 5) |
| C: shellcheck, tests, `precommit` green | items 2–6 | Partial → Complete | New suites now run by `precommit` (Major 6) |
| OQ1 symlinked `--plugin-dir` | KD1; research Q1; item 1 | Complete | Settled by bundle reading. Probe now observes the premise live under `acceptEdits` |
| OQ2 non-Edit changes | KD6 | Complete | Bash matched, measured 60–110 ms |
| OQ3 edits aimed at the copy | KD7; Q3; item 1 | Complete | Fallback made concrete (Minor 4) |
| OQ4 subagent coverage | Q4; item 1 | Complete | Fallback wired into KD11 |
| OQ5 launch vehicle | KD10 | Partial → Complete | Rationale for shim over recipe added (Minor 5) |
| Rejected approaches | KD1, KD7 | Complete | Consistent with the brief |
| Consumers (craft/cwd-safety/handoff; edify) | Approach; KD12; Scope OUT | Complete | edify OUT, as `edify-release-flow` supports |

**Traceability Assessment**: All brief items are covered. Gaps were found and
fixed in the outline.

## Scope-to-Component Traceability

The outline has no C1/C2 components. Its numbered Items are the implementation
units.

| Scope IN Item | Component (Item) | Notes |
|---|---|---|
| Q3/Q4/Q5 probe | Item 1 | Was an **orphan**: item 1 existed but Scope IN did not name it (Minor 6) |
| launcher | Item 4 | — |
| sync | Item 2 | — |
| post-tool / pre-tool | Item 3 | — |
| `install.sh` wiring | Item 5 | — |
| shipped-tree bookkeeping (dist-tree, justfile, CLAUDE.md) | Item 6 | Was folded under "tests, docs" and is now explicit |
| docs and migration note | Items 6–7, KD12 | — |

**Scope Assessment**: The orphan was found and fixed. OUT is enumerated and
matches the brief (nested roots and edify, read-only consumer repos, no
`install.sh` edits to `.envrc`/`.gitignore`/`clean`, no hot reload, no release).

**Cross-item interface check**: `post-tool`/`pre-tool` against the CC payload
had a mismatch for `NotebookEdit` (Major 2). Item 1 against item 4 had an
ordering mismatch (Major 1). The launcher's marker and `CLAUDE_PROJECT_DIR`
mismatch on a subdirectory launch (Major 3). KD11's four entries against the jq
identity check could shadow each other; this is now stated (Minor 3).

## Review Findings

### Critical Issues

None.

### Major Issues

1. **Probe depends on an artifact built three items later**
   - Location: Open questions, probe paragraph; Items 1 and 4.
   - Problem: Item 1 ran "through the new launcher", which item 4 builds. Item 1
     could not be executed as written.
   - Fix: The probe now reproduces the launcher by hand on a scratch plugin. It
     rsyncs into `dist/plugin/`, writes throwaway hooks into the scratch
     `.claude/settings.json`, and runs
     `claude -p --model haiku --permission-mode acceptEdits --plugin-dir …`.
     `acceptEdits` is pinned, because without it a source edit and a copy edit
     are both refused in `-p` and the outcomes cannot be told apart. The probe
     now also asserts the core premise live (a source edit goes through) and
     that `PostToolUseFailure` fires on a failing Bash call. It extracts the
     transcript with `jq`, not by reading it whole.
   - **Status**: FIXED

2. **`NotebookEdit` matched but its path field never read**
   - Location: KD4 (`post-tool`), KD7 (`pre-tool`), item 3.
   - Problem: Both hooks match `NotebookEdit` but read `tool_input.file_path`.
     NotebookEdit's input field is `notebook_path` (grep of the CC 2.1.283
     bundle:
     `notebook_path:o().describe("The absolute path to the Jupyter notebook file…`).
     A notebook edit to the source would never sync, and a notebook edit to the
     copy would never be denied.
   - Fix: The edited path is now
     `.tool_input.file_path // .tool_input.notebook_path` in both hooks, with
     test cases for both payload shapes in item 3.
   - **Status**: FIXED

3. **A subdirectory launch silently disables every hook**
   - Location: KD5, KD10.
   - Problem: The hooks act only when
     `PLUGIN_DEV_DOGFOOD_COPY == $CLAUDE_PROJECT_DIR/dist/plugin`.
     `CLAUDE_PROJECT_DIR` is the launch directory, so `claude` run from `docs/`
     makes the check fail, the hooks exit 0, and the copy goes stale with no
     signal. This contradicts the brief's "a stale copy looks exactly like a
     working one". Separately, `git rev-parse --show-toplevel` (KD10) names the
     wrong tree when run from inside the consumers' `memory/` gitlink, and KD10
     gave no reason for choosing it.
   - Fix: The launcher now derives the root from its own location
     (`<self>/../..`, since `plugin-dev/` is always at the consumer root) and
     refuses unless `$PWD` is that root. The refusal is flagged as a design
     decision added in review. A new Q5 in the probe records what CC does on a
     subdirectory launch, so the refusal can be relaxed. Item 4 tests it.
   - **Status**: FIXED (new decision; needs confirmation, see Recommendations)

4. **A killed sync strands the lock, and every later hook fails**
   - Location: KD9, item 2.
   - Problem: A `mkdir` lock with only a bounded wait has no recovery once its
     holder dies without running its trap (SIGKILL or OOM, which this box is
     prone to). From then on, every hook call times out and fails loudly until
     someone removes the lock by hand. The "lock serializes two syncs" test case
     was also not deterministic.
   - Fix: The holder removes the lock via a `trap`. A lock older than a bound
     (`find <lock> -maxdepth 0 -mmin +1`, which is portable where `stat` is not)
     is broken. PID liveness is rejected because of split PID namespaces
     (`sandbox-effects`). The timeout message names the lock path. The test case
     became two deterministic ones: a fresh pre-created lock gives a timeout
     plus the path on stderr, and a stale lock is broken.
   - **Status**: FIXED (the bound value needs confirmation)

5. **Hook command string is not whitespace-safe**
   - Location: KD11.
   - Problem: `install.sh`'s existing `hook_cmd` is
     `bash ${CLAUDE_PROJECT_DIR}/plugin-dev/version-guard.sh`, unquoted inside
     the command string (install.sh:51). Copying that shape for the dogfood
     entries splits on a space in the repo path. This violates the brief's
     "whitespace-safe throughout".
   - Fix: The new commands are
     `bash "${CLAUDE_PROJECT_DIR}/plugin-dev/dogfood.sh" <sub>`. version-guard's
     string is left unchanged, because a changed string would duplicate the
     entry on re-run. Item 5 asserts the quoting.
   - **Status**: FIXED

6. **New suites are never run by the gate**
   - Location: Item 6.
   - Problem: Item 6 only added the new scripts to `shellcheck`. The `precommit`
     recipe lists every suite by name (justfile:9–19), so `dogfood-test.sh` and
     `dogfood-launcher-test.sh` would never run, and a green `precommit` would
     no longer mean the whole suite passed (a CLAUDE.md invariant).
   - Fix: Item 6 now adds `bash -n` and a run line for both suites, and updates
     CLAUDE.md's Quality gate paragraph.
   - **Status**: FIXED

7. **Provenance `Derived from:` in a form the range script rejects**
   - Location: Provenance.
   - Problem: `Derived from:` names the brief, which is neither `none` nor
     "report … superseding `artifact`". The brief resolves but carries no
     `Base:`. The prior `Base:` value was
     `389e8b02cbbd19e8fa266175e293c5bc36323966`. It is a full sha and reachable
     from HEAD (`git merge-base --is-ancestor` exit 0), but by the repair table
     it cannot stand without a prior artifact to copy it from.
   - Fix: `Base:` replaced with `TODO`, per the row "`Derived from:` resolves,
     prior artifact has no usable `Base:`". The replaced value is quoted above.
     `Derived from:` was left as found.
   - **Status**: FIXED per the repair table. The author finishes the repair (see
     Recommendations).

### Minor Issues

1. **Plugin root not tied to the manifest** (KD3). The brief asks for the root
   to come from the manifest's location. The launcher now checks
   `<root>/.claude-plugin/plugin.json` and refuses without it, and item 4 tests
   this. FIXED.
2. **Escaper portability unstated** (KD2). The research used GNU `sed -z`, which
   macOS lacks. KD2 now specifies bash `read -r -d ''` plus parameter expansion.
   The hard exclude was also widened from `/dist/plugin/` to `/dist/`, because a
   consumer that ignores only `/dist/plugin/` (cwd-safety and handoff ignore
   nothing under `dist/` today) would otherwise copy the lock and other `dist/`
   output. Item 2 tests the nested-repo `.git` and `dist/` exclusion. FIXED.
3. **install.sh identity key unstated** (KD11). The two `post-tool` entries
   share a command under different events, and the current jq check keys on
   matcher regex plus command. KD11 now states that identity is (event, command)
   whatever the matcher, and lists the four entries. FIXED.
4. **Q3 fallback could not reach the agent**. "Put the mapping in the launcher's
   session notice" goes to the terminal only. The fallback is now an
   `--append-system-prompt` line on the exec argv. FIXED.
5. **Launch-vehicle choice lacked rationale** (KD10; brief OQ5). A one-sentence
   argument for the shim over a `release.just` recipe was added, and the script
   is stated to be bash. FIXED.
6. **Scope IN omitted the probe and the bookkeeping**. Both are now listed with
   item references. FIXED.
7. **Item 5 left a choice to the executor** ("extend … or add … (the executor
   picks)"). This fails the PDR "options selected" criterion. It is now decided:
   extend `tests/update-plugin-dev-test.sh`'s existing scenario "install.sh:
   wires into an existing settings.json without replacing it", which already
   owns install.sh's settings assertions, including the matcher-less case (lines
   343–375). An added case asserts the quoting. FIXED.
8. **Migration note version and direnv step** (KD12). The note now tells the
   consumer to run `direnv allow` and explains the `PATH_add` ordering. It also
   states that the file must not be named above the release actually cut,
   because `update.sh` prints old-exclusive/new-inclusive (update.sh:92). FIXED.
9. **`PostToolUseFailure` claim uncited** (KD6). It now cites
   `plugin-craft:hook-authoring` §3, which states that a non-zero Bash exit
   fires it instead of `PostToolUse`. The probe re-confirms this. FIXED.
10. **Risks incomplete**. Three were added: macOS `openrsync`/2.6.9 option
    support is unprobed (the research ran rsync 3.4.1 on Linux only); rsync exit
    24 on a concurrent delete gives an accepted false alarm; and the copy
    carries non-plugin directories (`plugin-dev/`, `memory/`). FIXED.
11. **Stale reason in KD3**. "An unignored copy would appear … in the next
    sync's source set" became false once `/dist/` is hard-excluded, so that
    clause was removed. FIXED.
12. **Wrap**. `rumdl fmt` was run on the outline. Five lines remain over 80;
    each is an unbreakable code span. FIXED.

## Fixes Applied

- Provenance: `Base:` `389e8b02cbbd19e8fa266175e293c5bc36323966` → `TODO`
- KD2: `/dist/` hard exclude, unanchored `.git` rationale, bash escaper
- KD3: manifest existence check; stale source-set clause removed
- KD4: `file_path // notebook_path`
- KD6: hook-authoring citation for `PostToolUseFailure`
- KD7: edited path read as in KD4
- KD9: trap, mtime-based stale-lock break, PID liveness rejected, lock path
  named on timeout
- KD10: bash; shim-over-recipe rationale; root from own path; non-root `$PWD`
  refusal
- KD11: the four entries enumerated; (event, command) identity; quoted
  `"${CLAUDE_PROJECT_DIR}"`
- KD12: `direnv allow`, `PATH_add` ordering, version naming rule
- Open questions: Q3 fallback via `--append-system-prompt`; Q4 fallback wired
  into KD11; new Q5; brief OQ1/2/5 cross-referenced; probe rewritten (hand-built
  copy, `acceptEdits`, four assertions, `jq` extraction)
- Items 1–6: probe Q5; deterministic lock cases; nested `.git`/`dist/`;
  foreign-marker, outside-repo and `notebook_path` cases; launcher refusals;
  item 5 decided; `precommit` runs new suites; CLAUDE.md Quality gate
- Scope IN: probe and bookkeeping listed with item references
- Risks: macOS rsync, exit 24, non-plugin content
- Whole file: reflowed with rumdl

## Positive Observations

- Decisions are evidence-backed. Rejecting `--files-from` is argued from two
  observed failures (no deletion propagation, exit 23 on a deleted tracked
  file), not from preference.
- The symlink option is closed by reading the bundle's `realpath` path, and the
  probe re-checks it, so the design's premise has a regression check.
- The env-marker liveness gate applies `detect-liveness-not-presence` correctly.
  It also makes unconditional wiring harmless for consumers that do not adopt
  the launcher.
- Sharing one script between the launcher and the hook addresses the root cause
  of the drift the brief complains about.
- The copy-edit guard follows the three-way channel split from
  `plugin-craft:hook-authoring` and rejects `updatedInput`, with a reason.
- The no-redirect stance on rsync's `skipping non-regular file` noise follows
  `no-stderr-suppression`.

## Recommendations

1. **Provenance (author action).** If the brief is requirements input rather
   than an artifact this outline supersedes, set `Derived from: none` and
   restore `Base: 389e8b02cbbd19e8fa266175e293c5bc36323966`. That sha is
   verified full and reachable from HEAD. This agent may not overwrite a present
   `Derived from:`.
2. **Confirm the non-root `$PWD` refusal** (KD10). The alternatives are to `cd`
   to the root before exec (silent), or to relax the hook check to
   "`CLAUDE_PROJECT_DIR` at or under the root". The second helps only if Q5
   shows the root's `.claude/settings.json` loads on a subdirectory launch.
3. **Confirm the stale-lock bound** (KD9). One minute is far above a 0.1 s sync,
   but a slow first sync of a large tree on a cold cache should be measured
   against it.
4. **macOS rsync.** Run the item 2 suite once on a macOS consumer the day it
   ships, before cutting the release.

---

**Ready for user presentation**: Yes. All findings are fixed in the outline.
Recommendations 1–3 are open for my human partner.
